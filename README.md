# Cross-Account Kafka Connect: MSK (Account A) → ClickHouse Cloud via Transit Gateway

Complete Terraform setup for connecting MSK in AWS Account A to ClickHouse Cloud using Kafka Connect in AWS Account B, connected via Transit Gateway.

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                  AWS ACCOUNT A                                          │
│                                  (MSK Account)                                          │
│                                                                                         │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐│
│  │                         VPC A (10.0.0.0/16)                                        ││
│  │                                                                                     ││
│  │  ┌──────────────────────────────────────────────────────────────────────────────┐ ││
│  │  │                      Private Subnet                                           │ ││
│  │  │                                                                                │ ││
│  │  │  ┌─────────────────────────────────────┐                                      │ ││
│  │  │  │   MSK Cluster (Existing)            │                                      │ ││
│  │  │  │                                     │                                      │ ││
│  │  │  │   ┌───────────────────────────┐    │                                      │ ││
│  │  │  │   │  Kafka Topics             │    │                                      │ ││
│  │  │  │   │  - events                 │    │                                      │ ││
│  │  │  │   │  - logs                   │    │                                      │ ││
│  │  │  │   └───────────────────────────┘    │                                      │ ││
│  │  │  │                                     │                                      │ ││
│  │  │  │   Security Group:                  │                                      │ ││
│  │  │  │   - INBOUND: 9094 from 10.16.0.0/16│                                      │ ││
│  │  │  │     (Account B VPC CIDR)           │                                      │ ││
│  │  │  └─────────────────┬───────────────────┘                                      │ ││
│  │  │                    │                                                          │ ││
│  │  │                    │ Port 9094 (TLS)                                         │ ││
│  │  │                    │ Private IP: 10.0.x.x                                    │ ││
│  │  │                    │                                                          │ ││
│  │  └────────────────────┼──────────────────────────────────────────────────────────┘ ││
│  │                       │                                                            ││
│  │                       │                                                            ││
│  │  ┌────────────────────▼────────────────────────┐                                  ││
│  │  │  Transit Gateway Attachment                 │                                  ││
│  │  │  - Attached to VPC A                        │                                  ││
│  │  │  - Routes: 10.16.0.0/16 → TGW              │                                  ││
│  │  └────────────────────┬────────────────────────┘                                  ││
│  └───────────────────────┼─────────────────────────────────────────────────────────────┘│
└────────────────────────┼──────────────────────────────────────────────────────────────┘
                         │
                         │ TRANSIT GATEWAY
                         │ (Cross-Account Connection)
                         │ Routes traffic between Account A ↔ Account B
                         │
┌────────────────────────▼──────────────────────────────────────────────────────────────┐
│                                  AWS ACCOUNT B                                          │
│                                  (Kafka Connect Account)                                │
│                                                                                         │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐│
│  │                         VPC B (10.16.0.0/16)                                       ││
│  │                                                                                     ││
│  │  ┌────────────────────┬────────────────────────┐                                   ││
│  │  │  Transit Gateway   │                        │                                   ││
│  │  │  Attachment        │                        │                                   ││
│  │  │  - Attached to VPC B                       │                                   ││
│  │  │  - Routes: 10.0.0.0/16 → TGW              │                                   ││
│  │  └────────────────────┼────────────────────────┘                                   ││
│  │                       │                                                            ││
│  │                       │                                                            ││
│  │  ┌──────────────────────────────────────────────────────────────────────────────┐ ││
│  │  │                      Private Subnet (10.16.x.x/24)                           │ ││
│  │  │                                                                               │ ││
│  │  │                                                                               │ ││
│  │  │  ┌──────────────────────────────────────────────────────────┐                │ ││
│  │  │  │   EC2 Instance - Kafka Connect                           │                │ ││
│  │  │  │   t3.large                                               │                │ ││
│  │  │  │   Private IP: 10.16.x.x                                  │                │ ││
│  │  │  │                                                           │                │ ││
│  │  │  │   ┌────────────────────────────────────────────────┐    │                │ ││
│  │  │  │   │  Kafka Connect Consumer                        │    │                │ ││
│  │  │  │   │  PULLS from MSK via TGW                        │    │                │ ││
│  │  │  │   │  ↓                                              │    │                │ ││
│  │  │  │   │  Processes & Transforms Data                   │    │                │ ││
│  │  │  │   │  ↓                                              │    │                │ ││
│  │  │  │   │  ClickHouse Sink Connector                     │    │                │ ││
│  │  │  │   │  PUSHES to ClickHouse via PrivateLink          │    │                │ ││
│  │  │  │   └────────────────────────────────────────────────┘    │                │ ││
│  │  │  │                                                           │                │ ││
│  │  │  │   Security Group:                                        │                │ ││
│  │  │  │   OUTBOUND:                                              │                │ ││
│  │  │  │   - 9094 to 10.0.0.0/16 (MSK in Account A via TGW)      │                │ ││
│  │  │  │   - 8443 to VPC Endpoint SG (ClickHouse)                │                │ ││
│  │  │  │   - 443/80 to 0.0.0.0/0 (Internet for plugins)          │                │ ││
│  │  │  └────────────────────────┬──────────────────────────────┘                │ ││
│  │  │                            │                                               │ ││
│  │  │                            │ OUTBOUND (Port 8443 HTTPS)                    │ ││
│  │  │                            │ PUSHES data to ClickHouse                     │ ││
│  │  │                            ▼                                               │ ││
│  │  │  ┌──────────────────────────────────────────────────────────┐             │ ││
│  │  │  │   VPC Endpoint (PrivateLink Interface)                   │             │ ││
│  │  │  │   Private IP: 10.16.y.y                                  │             │ ││
│  │  │  │   DNS: your-cluster.clickhouse.cloud → 10.16.y.y         │             │ ││
│  │  │  │                                                           │             │ ││
│  │  │  │   Security Group:                                        │             │ ││
│  │  │  │   INBOUND:                                               │             │ ││
│  │  │  │   - 8443 from Kafka Connect EC2 SG                       │             │ ││
│  │  │  └────────────────────────┬──────────────────────────────────┘             │ ││
│  │  │                            │                                               │ ││
│  │  └────────────────────────────┼───────────────────────────────────────────────┘ ││
│  └───────────────────────────────┼─────────────────────────────────────────────────┘│
└────────────────────────────────┼──────────────────────────────────────────────────────┘
                                 │
                                 │ AWS PrivateLink
                                 │ (Private AWS Backbone)
                                 │
                      ┌──────────▼────────────┐
                      │  ClickHouse Cloud     │
                      │  (Fully Managed)      │
                      │                       │
                      │  Port: 8443 (HTTPS)   │
                      │  Your Tables          │
                      └───────────────────────┘
```

---

## Data Flow Explained

### Step 1: MSK (Account A) → Kafka Connect (Account B) via TGW

```
MSK Cluster (Account A)
Private IP: 10.0.x.x
Port: 9094 (TLS)
    │
    │ INBOUND Security Group Rule:
    │ Allow 9094 from CIDR 10.16.0.0/16 (Account B VPC)
    │
    ▼
Transit Gateway
    │
    │ Routing:
    │ - Account A VPC → 10.16.0.0/16 goes to Account B
    │ - Account B VPC → 10.0.0.0/16 goes to Account A
    │
    ▼
Kafka Connect EC2 (Account B)
Private IP: 10.16.x.x
    │
    │ OUTBOUND Security Group Rule:
    │ Allow 9094 to CIDR 10.0.0.0/16 (Account A VPC)
    │
    └─► Kafka Connect PULLS data from MSK topics
```

**What happens:**
- Kafka Connect in Account B connects to MSK in Account A
- Traffic goes through Transit Gateway (private AWS network)
- Uses **CIDR-based security group rules** (can't reference SG across accounts)
- Kafka Connect **PULLS** messages from MSK topics
- Port: **9094** with **TLS encryption**

### Step 2: Kafka Connect (Account B) → ClickHouse Cloud via PrivateLink

```
Kafka Connect EC2 (Account B)
    │
    │ ClickHouse Sink Connector processes data
    │
    │ OUTBOUND Security Group Rule:
    │ Allow 8443 to VPC Endpoint Security Group
    │
    ▼
VPC Endpoint (PrivateLink) in Account B
Private IP: 10.16.y.y
    │
    │ INBOUND Security Group Rule:
    │ Allow 8443 from Kafka Connect EC2 SG
    │
    ▼
AWS PrivateLink
    │
    ▼
ClickHouse Cloud
    │
    └─► Data inserted into tables
```

**What happens:**
- Kafka Connect **PUSHES** data to ClickHouse via HTTPS
- Uses **VPC Endpoint** (private IP in Account B VPC)
- Traffic travels via **AWS PrivateLink** (never touches internet)
- Port: **8443** (HTTPS)

---

## Security Groups Summary

### Account A - MSK Security Group

```hcl
# INBOUND - Allow Kafka Connect from Account B via TGW
Source: 10.16.0.0/16 (Account B VPC CIDR)
Port: 9094
Protocol: TCP
Description: "Allow Kafka Connect from Account B via TGW"
```

**Note:** Cannot reference Account B's security group directly because it's in a different account. Must use CIDR block.

### Account B - Kafka Connect EC2 Security Group

```hcl
# OUTBOUND - Allow connection to MSK in Account A via TGW
Destination: 10.0.0.0/16 (Account A VPC CIDR)
Port: 9094
Protocol: TCP
Description: "Allow Kafka Connect to pull from MSK in Account A via TGW"

# OUTBOUND - Allow pushing to ClickHouse VPC Endpoint
Destination: clickhouse_endpoint Security Group
Port: 8443, 9440
Protocol: TCP
Description: "Allow Kafka Connect to push to ClickHouse"

# OUTBOUND - Internet for downloading plugins
Destination: 0.0.0.0/0
Port: 443, 80
Protocol: TCP
Description: "Allow HTTPS/HTTP for plugins"

# INBOUND - SSH from Account B VPC
Source: 10.16.0.0/16
Port: 22
Protocol: TCP
Description: "Allow SSH from VPC"
```

### Account B - ClickHouse VPC Endpoint Security Group

```hcl
# INBOUND - Allow Kafka Connect to push data
Source: kafka_connect_ec2 Security Group
Port: 8443, 9440
Protocol: TCP
Description: "Allow Kafka Connect to ClickHouse"
```

---

## Prerequisites

### 1. Transit Gateway Setup (CRITICAL)

Both accounts must be connected via Transit Gateway:

#### Account A (MSK):
```
✅ Transit Gateway Attachment to VPC A
✅ Route table entry: 10.16.0.0/16 → Transit Gateway
✅ TGW route table: 10.16.0.0/16 → Account B VPC attachment
```

#### Account B (Kafka Connect):
```
✅ Transit Gateway Attachment to VPC B
✅ Route table entry: 10.0.0.0/16 → Transit Gateway
✅ TGW route table: 10.0.0.0/16 → Account A VPC attachment
```

**Verify connectivity:**
```bash
# From EC2 in Account B, test connection to MSK in Account A
telnet 10.0.x.x 9094
```

### 2. Cross-Account IAM Role (Account A)

Create IAM role in Account A that Account B can assume:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_B_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "terraform-cross-account"
        }
      }
    }
  ]
}
```

Attach policies:
- `AmazonEC2FullAccess` (for security groups)
- `AmazonMSKReadOnlyAccess` (for MSK data sources)

### 3. From ClickHouse Cloud

- PrivateLink service name: `com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx`
- Cluster hostname: `your-cluster.us-east-1.aws.clickhouse.cloud`
- Database credentials

### 4. MSK Information (Account A)

- Cluster name
- Bootstrap servers (TLS): `b-1.cluster.kafka.region.amazonaws.com:9094`
- VPC ID
- VPC CIDR: `10.0.0.0/16`

---

## Terraform Files

### 1. Main Configuration (`cross_account_kafka_connect.tf`)

# ==============================================================================
# Cross-Account Kafka Connect: AWS Account B → MSK (Account A) → ClickHouse
# Connected via Transit Gateway
# ==============================================================================

# ==============================================================================
# PROVIDER CONFIGURATION
# ==============================================================================

# Provider for AWS Account B (where Kafka Connect EC2 will be deployed)
provider "aws" {
  region = var.aws_region
  alias  = "account_b"
  
  # Use your Account B credentials
  # profile = "account-b"
}

# Provider for AWS Account A (where MSK exists)
provider "aws" {
  region = var.aws_region
  alias  = "account_a"
  
  # Use your Account A credentials
  # profile = "account-a"
  assume_role {
    role_arn = var.account_a_role_arn
  }
}

# ==============================================================================
# DATA SOURCES - ACCOUNT B (Kafka Connect)
# ==============================================================================

data "aws_vpc" "account_b" {
  provider = aws.account_b
  
  filter {
    name   = "tag:Name"
    values = ["mfx-aggre-data-platform"]
  }
}

data "aws_subnet" "account_b_private" {
  provider = aws.account_b
  
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.account_b.id]
  }
}

data "aws_ami" "amazon_linux_2" {
  provider    = aws.account_b
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==============================================================================
# DATA SOURCES - ACCOUNT A (MSK)
# ==============================================================================

data "aws_msk_cluster" "account_a" {
  provider     = aws.account_a
  cluster_name = var.msk_cluster_name
}

data "aws_vpc" "account_a" {
  provider = aws.account_a
  id       = var.account_a_vpc_id
}

# ==============================================================================
# SECURITY GROUPS - ACCOUNT B (Kafka Connect)
# ==============================================================================

# Security Group for ClickHouse VPC Endpoint (Account B)
resource "aws_security_group" "clickhouse_endpoint" {
  provider    = aws.account_b
  name        = "${var.environment}-clickhouse-endpoint-sg"
  description = "Security group for ClickHouse VPC Endpoint"
  vpc_id      = data.aws_vpc.account_b.id

  tags = {
    Name        = "${var.environment}-clickhouse-endpoint-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# Security Group for Kafka Connect EC2 (Account B)
resource "aws_security_group" "kafka_connect_ec2" {
  provider    = aws.account_b
  name        = "${var.environment}-kafka-connect-ec2-sg"
  description = "Security group for Kafka Connect EC2 instance"
  vpc_id      = data.aws_vpc.account_b.id

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# ==============================================================================
# SECURITY GROUPS - ACCOUNT A (MSK)
# ==============================================================================

# Security Group for MSK Cluster (Account A)
resource "aws_security_group" "msk_cross_account" {
  provider    = aws.account_a
  name        = "${var.environment}-msk-cross-account-sg"
  description = "Security group for MSK - allows cross-account access via TGW"
  vpc_id      = data.aws_vpc.account_a.id

  tags = {
    Name        = "${var.environment}-msk-cross-account-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# ==============================================================================
# SECURITY GROUP RULES - ACCOUNT B (Kafka Connect)
# ==============================================================================

# --- Kafka Connect to MSK (Account A) via TGW ---

# OUTBOUND: Kafka Connect → MSK (via TGW to Account A)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_msk_tgw" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = var.account_a_vpc_cidr
  from_port   = 9094
  to_port     = 9094
  ip_protocol = "tcp"
  description = "Allow Kafka Connect to pull data from MSK in Account A via TGW"
}

# --- Kafka Connect to ClickHouse VPC Endpoint ---

# OUTBOUND: Kafka Connect → ClickHouse VPC Endpoint (HTTPS)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_https" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to push data to ClickHouse HTTPS"
}

# OUTBOUND: Kafka Connect → ClickHouse VPC Endpoint (Native)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_native" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 9440
  to_port                      = 9440
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to push data to ClickHouse Native"
}

# INBOUND: ClickHouse VPC Endpoint ← Kafka Connect (HTTPS)
resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_https" {
  provider          = aws.account_b
  security_group_id = aws_security_group.clickhouse_endpoint.id

  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to ClickHouse HTTPS"
}

# INBOUND: ClickHouse VPC Endpoint ← Kafka Connect (Native)
resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_native" {
  provider          = aws.account_b
  security_group_id = aws_security_group.clickhouse_endpoint.id

  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 9440
  to_port                      = 9440
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to ClickHouse Native"
}

# --- Internet Access for Plugins ---

# OUTBOUND: Kafka Connect → Internet (HTTPS)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_https_egress" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  description = "Allow HTTPS outbound for downloading plugins"
}

# OUTBOUND: Kafka Connect → Internet (HTTP)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_http_egress" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  description = "Allow HTTP outbound"
}

# OUTBOUND: Kafka Connect → DNS
resource "aws_vpc_security_group_egress_rule" "kafka_connect_dns" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"
  description = "Allow DNS"
}

# --- SSH Access ---

# INBOUND: SSH → Kafka Connect (from Account B VPC)
resource "aws_vpc_security_group_ingress_rule" "kafka_connect_ssh" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = data.aws_vpc.account_b.cidr_block
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  description = "Allow SSH from VPC"
}

# ==============================================================================
# SECURITY GROUP RULES - ACCOUNT A (MSK)
# ==============================================================================

# INBOUND: MSK ← Kafka Connect (from Account B via TGW)
resource "aws_vpc_security_group_ingress_rule" "msk_from_account_b_tgw" {
  provider          = aws.account_a
  security_group_id = aws_security_group.msk_cross_account.id

  cidr_ipv4   = var.account_b_vpc_cidr
  from_port   = 9094
  to_port     = 9094
  ip_protocol = "tcp"
  description = "Allow Kafka Connect from Account B via TGW to access MSK"
}

# Attach this security group to existing MSK cluster
# Note: You may need to manually add this SG to your MSK cluster
# or use aws_msk_cluster data source and update

# ==============================================================================
# VPC ENDPOINT - CLICKHOUSE (Account B)
# ==============================================================================

resource "aws_vpc_endpoint" "clickhouse" {
  provider          = aws.account_b
  vpc_id            = data.aws_vpc.account_b.id
  service_name      = var.clickhouse_privatelink_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    data.aws_subnet.account_b_private.id
  ]

  security_group_ids = [
    aws_security_group.clickhouse_endpoint.id
  ]

  private_dns_enabled = true

  tags = {
    Name        = "${var.environment}-clickhouse-endpoint"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# ==============================================================================
# IAM ROLE - KAFKA CONNECT EC2 (Account B)
# ==============================================================================

resource "aws_iam_role" "kafka_connect_ec2" {
  provider = aws.account_b
  name     = "${var.environment}-kafka-connect-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-role"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "kafka_connect_ec2" {
  provider = aws.account_b
  name     = "${var.environment}-kafka-connect-ec2-policy"
  role     = aws_iam_role.kafka_connect_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.environment}/clickhouse/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = var.account_a_role_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kafka_connect_ssm" {
  provider   = aws.account_b
  role       = aws_iam_role.kafka_connect_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "kafka_connect_ec2" {
  provider = aws.account_b
  name     = "${var.environment}-kafka-connect-ec2-profile"
  role     = aws_iam_role.kafka_connect_ec2.name

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-profile"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# ==============================================================================
# EC2 INSTANCE - KAFKA CONNECT (Account B)
# ==============================================================================

resource "aws_instance" "kafka_connect" {
  provider      = aws.account_b
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.large"
  subnet_id     = data.aws_subnet.account_b_private.id

  vpc_security_group_ids = [
    aws_security_group.kafka_connect_ec2.id
  ]

  iam_instance_profile = aws_iam_instance_profile.kafka_connect_ec2.name

  user_data = templatefile("${path.module}/kafka_connect_userdata.sh", {
    msk_bootstrap_servers = var.msk_bootstrap_servers
    environment           = var.environment
    clickhouse_host       = var.clickhouse_host
    clickhouse_database   = var.clickhouse_database
  })

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true

    tags = {
      Name        = "${var.environment}-kafka-connect-root-volume"
      App         = "mfx-aggre-data-platform"
      Environment = var.environment
    }
  }

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
    Role        = "kafka-connect"
  }
}

# ==============================================================================
# CLOUDWATCH LOG GROUP (Account B)
# ==============================================================================

resource "aws_cloudwatch_log_group" "kafka_connect" {
  provider          = aws.account_b
  name              = "/aws/ec2/kafka-connect/${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-kafka-connect-logs"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "kafka_connect_instance_id" {
  description = "ID of the Kafka Connect EC2 instance"
  value       = aws_instance.kafka_connect.id
}

output "kafka_connect_private_ip" {
  description = "Private IP of the Kafka Connect EC2 instance"
  value       = aws_instance.kafka_connect.private_ip
}

output "clickhouse_vpc_endpoint_id" {
  description = "ID of the ClickHouse VPC Endpoint"
  value       = aws_vpc_endpoint.clickhouse.id
}

output "msk_cross_account_sg_id" {
  description = "Security Group ID for MSK cross-account access (Account A)"
  value       = aws_security_group.msk_cross_account.id
}

output "connection_command" {
  description = "Command to connect to the Kafka Connect instance"
  value       = "aws ssm start-session --target ${aws_instance.kafka_connect.id} --profile account-b"
}

output "important_notes" {
  description = "Important setup notes"
  value = <<-EOT
  
  IMPORTANT SETUP STEPS:
  
  1. Add the MSK cross-account security group to your MSK cluster in Account A:
     Security Group ID: ${aws_security_group.msk_cross_account.id}
  
  2. Verify Transit Gateway attachment is active in both accounts
  
  3. Verify route tables in both VPCs have routes to each other via TGW:
     - Account A: Route ${var.account_b_vpc_cidr} → TGW
     - Account B: Route ${var.account_a_vpc_cidr} → TGW
  
  4. Test connectivity from Account B to MSK:
     telnet <msk-broker-private-ip> 9094
  
  EOT
}

---

### 2. Variables (`variables.tf`)

# ==============================================================================
# Variables for Cross-Account Kafka Connect Setup
# ==============================================================================

# --- General ---

variable "aws_region" {
  description = "AWS region for both accounts"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., test, prod)"
  type        = string
}

# --- AWS Account A (MSK) ---

variable "account_a_role_arn" {
  description = "IAM role ARN in Account A to assume for Terraform operations"
  type        = string
  # Example: "arn:aws:iam::111111111111:role/TerraformCrossAccountRole"
}

variable "account_a_vpc_id" {
  description = "VPC ID in Account A where MSK is deployed"
  type        = string
}

variable "account_a_vpc_cidr" {
  description = "CIDR block of Account A VPC"
  type        = string
  # Example: "10.0.0.0/16"
}

variable "msk_cluster_name" {
  description = "Name of the MSK cluster in Account A"
  type        = string
}

variable "msk_bootstrap_servers" {
  description = "MSK bootstrap servers (TLS endpoint)"
  type        = string
  # Example: "b-1.msk-cluster.xxxxx.kafka.us-east-1.amazonaws.com:9094,b-2.msk-cluster.xxxxx.kafka.us-east-1.amazonaws.com:9094"
}

# --- AWS Account B (Kafka Connect) ---

variable "account_b_vpc_cidr" {
  description = "CIDR block of Account B VPC where Kafka Connect will be deployed"
  type        = string
  # Example: "10.16.0.0/16"
}

# --- ClickHouse Configuration ---

variable "clickhouse_privatelink_service_name" {
  description = "ClickHouse Cloud PrivateLink service name"
  type        = string
  # Example: "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxxxxx"
}

variable "clickhouse_host" {
  description = "ClickHouse Cloud hostname"
  type        = string
  # Example: "your-cluster.us-east-1.aws.clickhouse.cloud"
}

variable "clickhouse_database" {
  description = "ClickHouse database name"
  type        = string
  default     = "default"
}

variable "clickhouse_username" {
  description = "ClickHouse username"
  type        = string
  default     = "default"
  sensitive   = true
}

variable "clickhouse_password" {
  description = "ClickHouse password"
  type        = string
  sensitive   = true
}

# --- Transit Gateway ---

variable "transit_gateway_id" {
  description = "Transit Gateway ID connecting Account A and Account B"
  type        = string
}

---

### 3. terraform.tfvars Example

```hcl
# General
aws_region  = "us-east-1"
environment = "prod"

# Account A (MSK)
account_a_role_arn     = "arn:aws:iam::111111111111:role/TerraformCrossAccountRole"
account_a_vpc_id       = "vpc-0123456789abcdef0"
account_a_vpc_cidr     = "10.0.0.0/16"
msk_cluster_name       = "mfx-aggre-msk-cluster"
msk_bootstrap_servers  = "b-1.msk.xxxxx.kafka.us-east-1.amazonaws.com:9094,b-2.msk.xxxxx.kafka.us-east-1.amazonaws.com:9094"

# Account B (Kafka Connect)
account_b_vpc_cidr = "10.16.0.0/16"

# ClickHouse
clickhouse_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxxxxx"
clickhouse_host                     = "abc123.us-east-1.aws.clickhouse.cloud"
clickhouse_database                 = "default"
clickhouse_username                 = "default"
clickhouse_password                 = "your-secure-password"

# Transit Gateway
transit_gateway_id = "tgw-0123456789abcdef0"
```

---

### 4. User Data Script (`kafka_connect_userdata.sh`)

#!/bin/bash
set -e

# ==============================================================================
# Kafka Connect EC2 User Data Script
# ==============================================================================

# Variables from Terraform
MSK_BOOTSTRAP_SERVERS="${msk_bootstrap_servers}"
ENVIRONMENT="${environment}"
CLICKHOUSE_HOST="${clickhouse_host}"
CLICKHOUSE_DATABASE="${clickhouse_database}"

# System updates
echo "Starting system updates..."
yum update -y
yum install -y java-11-amazon-corretto-headless wget tar unzip curl jq

# Create kafka user
echo "Creating kafka user..."
useradd -r -s /bin/false kafka || true

# Install Kafka (includes Connect)
echo "Installing Kafka..."
KAFKA_VERSION="3.5.1"
SCALA_VERSION="2.13"
cd /opt

if [ ! -d "/opt/kafka" ]; then
    wget "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_$${SCALA_VERSION}-$KAFKA_VERSION.tgz"
    tar -xzf "kafka_$${SCALA_VERSION}-$KAFKA_VERSION.tgz"
    ln -s "kafka_$${SCALA_VERSION}-$KAFKA_VERSION" kafka
    rm "kafka_$${SCALA_VERSION}-$KAFKA_VERSION.tgz"
    chown -R kafka:kafka /opt/kafka*
fi

# Create directories
echo "Creating directories..."
mkdir -p /var/log/kafka-connect
mkdir -p /opt/kafka-connect/plugins
mkdir -p /opt/kafka-connect/config
chown -R kafka:kafka /var/log/kafka-connect
chown -R kafka:kafka /opt/kafka-connect

# Download ClickHouse Kafka Connect Plugin
echo "Downloading ClickHouse Kafka Connect plugin..."
cd /opt/kafka-connect/plugins
if [ ! -d "clickhouse-kafka-connect" ]; then
    mkdir -p clickhouse-kafka-connect
    cd clickhouse-kafka-connect
    
    # Download the latest version of ClickHouse Kafka Connect
    wget https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.0.6/clickhouse-kafka-connect-v1.0.6.zip
    unzip clickhouse-kafka-connect-v1.0.6.zip
    rm clickhouse-kafka-connect-v1.0.6.zip
    
    chown -R kafka:kafka /opt/kafka-connect/plugins
fi

# Create Kafka Connect standalone configuration
echo "Creating Kafka Connect configuration..."
cat > /opt/kafka-connect/config/connect-standalone.properties <<EOF
# Kafka broker settings
bootstrap.servers=$MSK_BOOTSTRAP_SERVERS
security.protocol=SSL

# Kafka Connect settings
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Plugin path
plugin.path=/opt/kafka-connect/plugins

# Offset storage (for standalone mode)
offset.storage.file.filename=/tmp/connect.offsets
offset.flush.interval.ms=10000

# Producer settings
producer.security.protocol=SSL
producer.compression.type=gzip

# Consumer settings
consumer.security.protocol=SSL
consumer.max.poll.records=500
EOF

chown kafka:kafka /opt/kafka-connect/config/connect-standalone.properties

# Create ClickHouse Connector configuration template
echo "Creating ClickHouse connector configuration template..."
cat > /opt/kafka-connect/config/clickhouse-sink.properties <<'EOF'
name=clickhouse-sink-connector
connector.class=com.clickhouse.kafka.connect.ClickHouseSinkConnector
tasks.max=1

# Kafka topics to consume from
topics=your_kafka_topic

# ClickHouse connection settings
clickhouse.server.url=https://CLICKHOUSE_HOST:8443
clickhouse.server.database=CLICKHOUSE_DATABASE
clickhouse.server.user=default
clickhouse.server.password=YOUR_PASSWORD

# ClickHouse table settings
clickhouse.table.name=your_table_name

# Converter settings
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Error handling
errors.tolerance=all
errors.log.enable=true
errors.log.include.messages=true
errors.deadletterqueue.topic.name=dlq-clickhouse-sink

# Batching settings
batch.size=1000
buffer.count.records=10000
EOF

# Replace placeholders
sed -i "s|CLICKHOUSE_HOST|$CLICKHOUSE_HOST|g" /opt/kafka-connect/config/clickhouse-sink.properties
sed -i "s|CLICKHOUSE_DATABASE|$CLICKHOUSE_DATABASE|g" /opt/kafka-connect/config/clickhouse-sink.properties

chown kafka:kafka /opt/kafka-connect/config/clickhouse-sink.properties

# Create systemd service for Kafka Connect
echo "Creating systemd service..."
cat > /etc/systemd/system/kafka-connect.service <<EOF
[Unit]
Description=Apache Kafka Connect
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms1G -Xmx1G"
Environment="KAFKA_JVM_PERFORMANCE_OPTS=-XX:+UseG1GC -XX:MaxGCPauseMillis=20"
ExecStart=/opt/kafka/bin/connect-standalone.sh /opt/kafka-connect/config/connect-standalone.properties /opt/kafka-connect/config/clickhouse-sink.properties
StandardOutput=append:/var/log/kafka-connect/kafka-connect.log
StandardError=append:/var/log/kafka-connect/kafka-connect-error.log
Restart=on-failure
RestartSec=10
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

# Install and configure CloudWatch agent
echo "Installing CloudWatch agent..."
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/kafka-connect/kafka-connect.log",
            "log_group_name": "/aws/ec2/kafka-connect/$ENVIRONMENT",
            "log_stream_name": "{instance_id}/kafka-connect.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/kafka-connect/kafka-connect-error.log",
            "log_group_name": "/aws/ec2/kafka-connect/$ENVIRONMENT",
            "log_stream_name": "{instance_id}/kafka-connect-error.log",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

# Configure logrotate
echo "Configuring log rotation..."
cat > /etc/logrotate.d/kafka-connect <<EOF
/var/log/kafka-connect/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0644 kafka kafka
}
EOF

# Create helper scripts
echo "Creating helper scripts..."

# Script to test ClickHouse connectivity
cat > /home/ec2-user/test-clickhouse.sh <<'TESTEOF'
#!/bin/bash
echo "Testing ClickHouse connectivity..."
echo "1. Testing DNS resolution:"
nslookup CLICKHOUSE_HOST

echo -e "\n2. Testing HTTPS connectivity (port 8443):"
curl -k -s https://CLICKHOUSE_HOST:8443/ping

echo -e "\n3. Testing with credentials:"
echo "Please run manually with your credentials:"
echo "curl -k -u default:YOUR_PASSWORD https://CLICKHOUSE_HOST:8443/ping"
TESTEOF

sed -i "s|CLICKHOUSE_HOST|$CLICKHOUSE_HOST|g" /home/ec2-user/test-clickhouse.sh
chmod +x /home/ec2-user/test-clickhouse.sh
chown ec2-user:ec2-user /home/ec2-user/test-clickhouse.sh

# Script to update connector configuration
cat > /home/ec2-user/update-connector.sh <<'UPDATEEOF'
#!/bin/bash

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <kafka_topic> <clickhouse_table> <clickhouse_password>"
    exit 1
fi

KAFKA_TOPIC=$1
CLICKHOUSE_TABLE=$2
CLICKHOUSE_PASSWORD=$3

echo "Updating ClickHouse connector configuration..."

# Backup original
cp /opt/kafka-connect/config/clickhouse-sink.properties /opt/kafka-connect/config/clickhouse-sink.properties.backup

# Update configuration
sudo sed -i "s|topics=.*|topics=$KAFKA_TOPIC|g" /opt/kafka-connect/config/clickhouse-sink.properties
sudo sed -i "s|clickhouse.table.name=.*|clickhouse.table.name=$CLICKHOUSE_TABLE|g" /opt/kafka-connect/config/clickhouse-sink.properties
sudo sed -i "s|clickhouse.server.password=.*|clickhouse.server.password=$CLICKHOUSE_PASSWORD|g" /opt/kafka-connect/config/clickhouse-sink.properties

echo "Configuration updated. Restarting Kafka Connect..."
sudo systemctl restart kafka-connect

echo "Done! Check status with: sudo systemctl status kafka-connect"
UPDATEEOF

chmod +x /home/ec2-user/update-connector.sh
chown ec2-user:ec2-user /home/ec2-user/update-connector.sh

# Create README
cat > /home/ec2-user/README.txt <<'README'
================================================================
Kafka Connect with ClickHouse Sink - Setup Complete
================================================================

IMPORTANT: Before starting Kafka Connect, you must:
1. Update the connector configuration with your actual values
2. Run the test script to verify ClickHouse connectivity

Quick Start Guide:
------------------

1. Test ClickHouse Connectivity:
   ./test-clickhouse.sh

2. Update Connector Configuration:
   ./update-connector.sh <kafka_topic> <clickhouse_table> <password>
   
   Example:
   ./update-connector.sh my_events events_table mySecurePassword

3. Start Kafka Connect:
   sudo systemctl start kafka-connect

4. Check Status:
   sudo systemctl status kafka-connect

5. View Logs:
   sudo tail -f /var/log/kafka-connect/kafka-connect.log

Useful Commands:
----------------
# Check Kafka Connect service
sudo systemctl status kafka-connect

# View logs
sudo tail -f /var/log/kafka-connect/kafka-connect.log
sudo tail -f /var/log/kafka-connect/kafka-connect-error.log

# Restart service
sudo systemctl restart kafka-connect

# Stop service
sudo systemctl stop kafka-connect

# View connector configuration
cat /opt/kafka-connect/config/clickhouse-sink.properties

# Test MSK connectivity
telnet <MSK_BROKER> 9094

Configuration Files:
-------------------
- Kafka Connect config: /opt/kafka-connect/config/connect-standalone.properties
- ClickHouse connector: /opt/kafka-connect/config/clickhouse-sink.properties
- Plugins: /opt/kafka-connect/plugins/
- Logs: /var/log/kafka-connect/

Troubleshooting:
---------------
1. If connector fails to start:
   - Check logs in /var/log/kafka-connect/
   - Verify ClickHouse credentials
   - Test connectivity: ./test-clickhouse.sh
   
2. If data is not flowing:
   - Verify Kafka topic exists and has data
   - Check ClickHouse table schema matches data
   - Review error logs

3. Check VPC Endpoint:
   - nslookup should resolve to private IP (10.16.x.x)
   - If resolving to public IP, check VPC Endpoint configuration

For more information:
- Kafka Connect: https://kafka.apache.org/documentation/#connect
- ClickHouse Connector: https://github.com/ClickHouse/clickhouse-kafka-connect
================================================================
README

chown ec2-user:ec2-user /home/ec2-user/README.txt

# Wait for MSK cluster to be ready
echo "Waiting for MSK cluster to be available..."
sleep 30

# Enable Kafka Connect (but don't start yet - user needs to configure)
echo "Enabling Kafka Connect service..."
systemctl daemon-reload
systemctl enable kafka-connect

echo "================================================================"
echo "Kafka Connect installation completed!"
echo "================================================================"
echo "IMPORTANT: Before starting Kafka Connect:"
echo "1. SSH to this instance"
echo "2. Read /home/ec2-user/README.txt"
echo "3. Update connector configuration with your settings"
echo "4. Test ClickHouse connectivity"
echo "5. Start the service: sudo systemctl start kafka-connect"
echo "================================================================"

---

## Deployment Steps

### Step 1: Configure AWS Credentials

```bash
# ~/.aws/credentials
[account-a]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[account-b]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

# ~/.aws/config
[profile account-a]
region = us-east-1

[profile account-b]
region = us-east-1
```

### Step 2: Update Provider Configuration

Edit the providers in `cross_account_kafka_connect.tf`:

```hcl
provider "aws" {
  region  = var.aws_region
  alias   = "account_b"
  profile = "account-b"
}

provider "aws" {
  region  = var.aws_region
  alias   = "account_a"
  profile = "account-a"
}
```

### Step 3: Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Plan (review what will be created)
terraform plan

# Apply
terraform apply
```

### Step 4: Manually Attach MSK Security Group

**IMPORTANT:** After Terraform creates the security group in Account A, you must manually attach it to your existing MSK cluster:

```bash
# Get the security group ID from Terraform output
terraform output msk_cross_account_sg_id

# In AWS Console (Account A):
# 1. Go to MSK → Clusters → Your Cluster
# 2. Click "Edit" under Security groups
# 3. Add the new security group
# 4. Save
```

Or via AWS CLI:
```bash
aws kafka update-security \
  --cluster-arn <your-msk-cluster-arn> \
  --current-version <cluster-version> \
  --client-authentication '{"Sasl":{"Scram":{"Enabled":false},"Iam":{"Enabled":false}},"Tls":{"CertificateAuthorityArnList":[],"Enabled":true},"Unauthenticated":{"Enabled":false}}' \
  --security-group-ids <existing-sg-1> <existing-sg-2> <new-cross-account-sg> \
  --profile account-a
```

### Step 5: Verify Connectivity

#### Test TGW Connectivity (Account B → Account A)

```bash
# Connect to Kafka Connect EC2
aws ssm start-session --target <instance-id> --profile account-b

# Test MSK connectivity
telnet 10.0.x.x 9094
# Should connect successfully

# If connection fails, check:
# 1. TGW attachments are active in both accounts
# 2. Route tables have correct routes
# 3. Security groups allow traffic
```

#### Test ClickHouse VPC Endpoint

```bash
# On Kafka Connect EC2
./test-clickhouse.sh

# Expected: DNS resolves to private IP (10.16.y.y)
```

### Step 6: Configure Connector

```bash
# On Kafka Connect EC2
./update-connector.sh my_kafka_topic my_clickhouse_table my_password
```

### Step 7: Monitor

```bash
# Check service
sudo systemctl status kafka-connect

# View logs
sudo tail -f /var/log/kafka-connect/kafka-connect.log

# CloudWatch
aws logs tail /aws/ec2/kafka-connect/prod --follow --profile account-b
```

---

## Troubleshooting

### Issue 1: Can't Connect to MSK from Account B

**Symptoms:**
```
telnet: Unable to connect to 10.0.x.x port 9094: Connection timed out
```

**Debug Steps:**

1. **Verify TGW attachments:**
```bash
# Account A
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=vpc-id,Values=<vpc-a-id>" \
  --profile account-a

# Account B
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=vpc-id,Values=<vpc-b-id>" \
  --profile account-b

# Both should show State: available
```

2. **Verify route tables:**
```bash
# Account A - should have route: 10.16.0.0/16 → TGW
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-a-id>" \
  --profile account-a

# Account B - should have route: 10.0.0.0/16 → TGW
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-b-id>" \
  --profile account-b
```

3. **Verify TGW route tables:**
```bash
# Check TGW route table associations
aws ec2 describe-transit-gateway-route-tables \
  --transit-gateway-route-table-ids <tgw-rt-id>
```

4. **Verify security groups:**
```bash
# Account A - MSK SG should allow 9094 from 10.16.0.0/16
aws ec2 describe-security-groups \
  --group-ids <msk-sg-id> \
  --profile account-a

# Account B - Kafka Connect SG should allow egress to 10.0.0.0/16
aws ec2 describe-security-groups \
  --group-ids <kafka-connect-sg-id> \
  --profile account-b
```

5. **Check if MSK has the cross-account SG attached:**
```bash
aws kafka describe-cluster \
  --cluster-arn <msk-arn> \
  --query 'ClusterInfo.BrokerNodeGroupInfo.SecurityGroups' \
  --profile account-a
```

### Issue 2: MSK Bootstrap Servers Not Resolving

**Problem:** DNS can't resolve MSK broker hostnames in Account B

**Solution:**
Use private IPs directly or set up Route53 private hosted zone:

```bash
# Option 1: Get MSK private IPs
aws kafka describe-cluster \
  --cluster-arn <msk-arn> \
  --query 'ClusterInfo.BrokerNodeGroupInfo.ClientSubnets' \
  --profile account-a

# Option 2: Create Route53 private hosted zone in Account B
# Associate it with both VPCs
```

### Issue 3: ClickHouse VPC Endpoint Not Working

**Problem:** DNS resolves to public IP instead of private

**Solution:**
```bash
# Verify VPC Endpoint status
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids <endpoint-id> \
  --profile account-b

# Should show:
# - State: available
# - PrivateDnsEnabled: true

# Wait 5-10 minutes for DNS propagation
# Restart EC2 to flush DNS cache
sudo reboot
```

### Issue 4: Kafka Connect Can't Authenticate to MSK

**Problem:** MSK uses IAM authentication but Kafka Connect can't authenticate

**Solution:**

If MSK uses IAM auth, you need to update the IAM role in Account B:

```hcl
# Add to kafka_connect_ec2 IAM policy
{
  "Effect": "Allow",
  "Action": [
    "kafka-cluster:Connect",
    "kafka-cluster:DescribeCluster",
    "kafka-cluster:ReadData",
    "kafka-cluster:DescribeTopic"
  ],
  "Resource": [
    "arn:aws:kafka:us-east-1:ACCOUNT_A_ID:cluster/msk-cluster/*",
    "arn:aws:kafka:us-east-1:ACCOUNT_A_ID:topic/msk-cluster/*"
  ]
}
```

Also need resource-based policy on MSK in Account A.

---

## Network Flow Summary

```
┌─────────────────────────────────────────────────────────┐
│  DIRECTION    │  FROM         │  TO           │  PORT   │
├─────────────────────────────────────────────────────────┤
│  OUTBOUND     │  Kafka Connect│  MSK (A)      │  9094   │
│  (via TGW)    │  (Account B)  │  via TGW      │  TCP    │
├─────────────────────────────────────────────────────────┤
│  OUTBOUND     │  Kafka Connect│  VPC Endpoint │  8443   │
│  (PrivateLink)│  (Account B)  │  (Account B)  │  TCP    │
├─────────────────────────────────────────────────────────┤
│  INBOUND      │  VPC Endpoint │  ClickHouse   │  8443   │
│  (PrivateLink)│  (Account B)  │  Cloud        │  TCP    │
└─────────────────────────────────────────────────────────┘
```

**All traffic is private:**
- ✅ MSK ↔ Kafka Connect: Via Transit Gateway (AWS private network)
- ✅ Kafka Connect ↔ ClickHouse: Via PrivateLink (AWS private network)
- ❌ No public internet involved in data transfer

---

## Cost Estimate

| Component | Account | Monthly Cost |
|-----------|---------|--------------|
| Transit Gateway (data processed) | Both | ~$0.02/GB |
| Transit Gateway attachments | Both | ~$36 ($18 per attachment) |
| VPC Endpoint | B | ~$7-10 |
| Data Transfer (PrivateLink) | B | $0.01/GB |
| EC2 t3.large | B | ~$60 |
| EBS 50GB GP3 | B | ~$5 |
| **Total** | | **~$108-118/month** |

*Plus data transfer costs based on your throughput*

---

## Quick Reference

### Connect to Kafka Connect EC2
```bash
aws ssm start-session --target <instance-id> --profile account-b
```

### Check MSK Connectivity
```bash
telnet <msk-private-ip> 9094
```

### View Kafka Connect Logs
```bash
sudo tail -f /var/log/kafka-connect/kafka-connect.log
```

### Test ClickHouse
```bash
./test-clickhouse.sh
```

### Update Connector
```bash
./update-connector.sh <topic> <table> <password>
```

---

## Important Notes

1. **Cross-Account Security Groups:** Cannot reference security groups across accounts. Must use CIDR blocks.

2. **Transit Gateway Routing:** Both VPCs must have routes to each other via TGW.

3. **MSK Security Group:** Must manually attach the cross-account security group to MSK cluster.

4. **VPC Endpoint:** ClickHouse endpoint is created in Account B only.

5. **IAM Permissions:** Account B needs assume role permissions to Account A for Terraform to create resources.

---

## Resources

- [AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [Cross-Account VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [ClickHouse Kafka Connect](https://github.com/ClickHouse/clickhouse-kafka-connect)

---

**Version:** 1.0.0  
**Last Updated:** December 2024
