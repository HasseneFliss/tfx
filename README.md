# Cross-Account Kafka Connect: MSK (Account A) → ClickHouse Cloud via Transit Gateway

Complete Terraform setup for connecting MSK in AWS Account A to ClickHouse Cloud using Kafka Connect in AWS Account B, connected via Transit Gateway.

---

## 📋 Table of Contents

- [Architecture Diagram](#architecture-diagram)
- [Data Flow](#data-flow)
- [Security Groups](#security-groups)
- [Prerequisites](#prerequisites)
- [Terraform Configuration](#terraform-configuration)
- [Deployment Steps](#deployment-steps)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## 🏗️ Architecture Diagram

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

## 🔄 Data Flow

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

---

## 🔐 Security Groups

### Account A - MSK Security Group

| Direction | Source/Destination | Port | Protocol | Description |
|-----------|-------------------|------|----------|-------------|
| INBOUND | 10.16.0.0/16 | 9094 | TCP | Allow Kafka Connect from Account B via TGW |

**Note:** Cannot reference Account B's security group directly because it's in a different account. Must use CIDR block.

### Account B - Kafka Connect EC2 Security Group

| Direction | Source/Destination | Port | Protocol | Description |
|-----------|-------------------|------|----------|-------------|
| OUTBOUND | 10.0.0.0/16 | 9094 | TCP | Pull from MSK in Account A via TGW |
| OUTBOUND | ClickHouse Endpoint SG | 8443 | TCP | Push to ClickHouse HTTPS |
| OUTBOUND | ClickHouse Endpoint SG | 9440 | TCP | Push to ClickHouse Native |
| OUTBOUND | 0.0.0.0/0 | 443 | TCP | Download plugins (HTTPS) |
| OUTBOUND | 0.0.0.0/0 | 80 | TCP | Download plugins (HTTP) |
| OUTBOUND | 0.0.0.0/0 | 53 | UDP | DNS queries |
| INBOUND | 10.16.0.0/16 | 22 | TCP | SSH from VPC |

### Account B - ClickHouse VPC Endpoint Security Group

| Direction | Source/Destination | Port | Protocol | Description |
|-----------|-------------------|------|----------|-------------|
| INBOUND | Kafka Connect EC2 SG | 8443 | TCP | Allow Kafka Connect HTTPS |
| INBOUND | Kafka Connect EC2 SG | 9440 | TCP | Allow Kafka Connect Native |

---

## ✅ Prerequisites

### 1. Transit Gateway Setup (CRITICAL)

Both accounts must be connected via Transit Gateway with proper routing.

#### Account A (MSK):
- ✅ Transit Gateway Attachment to VPC A
- ✅ Route table entry: `10.16.0.0/16 → Transit Gateway`
- ✅ TGW route table: `10.16.0.0/16 → Account B VPC attachment`

#### Account B (Kafka Connect):
- ✅ Transit Gateway Attachment to VPC B
- ✅ Route table entry: `10.0.0.0/16 → Transit Gateway`
- ✅ TGW route table: `10.0.0.0/16 → Account A VPC attachment`

**Test connectivity:**
```bash
# From EC2 in Account B
telnet <msk-broker-private-ip> 9094
```

### 2. Cross-Account IAM Role (Account A)

Create IAM role in Account A for Terraform to assume:

**Trust Policy:**
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

**Attach Policies:**
- `AmazonEC2FullAccess`
- `AmazonMSKReadOnlyAccess`

### 3. ClickHouse Cloud Information

- PrivateLink service name
- Cluster hostname
- Database credentials

### 4. MSK Information (Account A)

- Cluster name
- Bootstrap servers (TLS endpoint)
- VPC ID and CIDR

---

## 📦 Terraform Configuration

### File Structure

```
.
├── cross_account_kafka_connect.tf    # Main configuration
├── variables.tf                       # Variable definitions
├── terraform.tfvars                   # Variable values
└── kafka_connect_userdata.sh          # EC2 bootstrap script
```

### 1. Main Configuration

**File:** `cross_account_kafka_connect.tf`

```hcl
# Providers for both accounts
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

# VPC Endpoint for ClickHouse (Account B)
resource "aws_vpc_endpoint" "clickhouse" {
  provider              = aws.account_b
  vpc_id                = data.aws_vpc.account_b.id
  service_name          = var.clickhouse_privatelink_service_name
  vpc_endpoint_type     = "Interface"
  subnet_ids            = [data.aws_subnet.account_b_private.id]
  security_group_ids    = [aws_security_group.clickhouse_endpoint.id]
  private_dns_enabled   = true

  tags = {
    Name = "${var.environment}-clickhouse-endpoint"
  }
}

# Security Group for ClickHouse VPC Endpoint (Account B)
resource "aws_security_group" "clickhouse_endpoint" {
  provider    = aws.account_b
  name        = "${var.environment}-clickhouse-endpoint-sg"
  description = "Security group for ClickHouse VPC Endpoint"
  vpc_id      = data.aws_vpc.account_b.id

  tags = {
    Name = "${var.environment}-clickhouse-endpoint-sg"
  }
}

# Security Group for Kafka Connect EC2 (Account B)
resource "aws_security_group" "kafka_connect_ec2" {
  provider    = aws.account_b
  name        = "${var.environment}-kafka-connect-ec2-sg"
  description = "Security group for Kafka Connect EC2"
  vpc_id      = data.aws_vpc.account_b.id

  tags = {
    Name = "${var.environment}-kafka-connect-ec2-sg"
  }
}

# Security Group for MSK Cross-Account (Account A)
resource "aws_security_group" "msk_cross_account" {
  provider    = aws.account_a
  name        = "${var.environment}-msk-cross-account-sg"
  description = "Allow cross-account access from Account B via TGW"
  vpc_id      = var.account_a_vpc_id

  tags = {
    Name = "${var.environment}-msk-cross-account-sg"
  }
}

# OUTBOUND: Kafka Connect → MSK (via TGW)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_msk_tgw" {
  provider          = aws.account_b
  security_group_id = aws_security_group.kafka_connect_ec2.id
  cidr_ipv4         = var.account_a_vpc_cidr
  from_port         = 9094
  to_port           = 9094
  ip_protocol       = "tcp"
  description       = "Pull from MSK in Account A via TGW"
}

# INBOUND: MSK ← Kafka Connect (from Account B)
resource "aws_vpc_security_group_ingress_rule" "msk_from_account_b_tgw" {
  provider          = aws.account_a
  security_group_id = aws_security_group.msk_cross_account.id
  cidr_ipv4         = var.account_b_vpc_cidr
  from_port         = 9094
  to_port           = 9094
  ip_protocol       = "tcp"
  description       = "Allow Kafka Connect from Account B via TGW"
}

# OUTBOUND: Kafka Connect → ClickHouse VPC Endpoint
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_https" {
  provider                     = aws.account_b
  security_group_id            = aws_security_group.kafka_connect_ec2.id
  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Push to ClickHouse HTTPS"
}

# INBOUND: ClickHouse VPC Endpoint ← Kafka Connect
resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_https" {
  provider                     = aws.account_b
  security_group_id            = aws_security_group.clickhouse_endpoint.id
  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect HTTPS"
}

# EC2 Instance for Kafka Connect
resource "aws_instance" "kafka_connect" {
  provider             = aws.account_b
  ami                  = data.aws_ami.amazon_linux_2.id
  instance_type        = "t3.large"
  subnet_id            = data.aws_subnet.account_b_private.id
  vpc_security_group_ids = [aws_security_group.kafka_connect_ec2.id]
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
  }

  tags = {
    Name = "${var.environment}-kafka-connect-ec2"
  }
}
```

> **📝 Note:** See full Terraform file in the repository with complete IAM roles, data sources, and outputs.

### 2. Variables

**File:** `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Account A (MSK)
variable "account_a_role_arn" {
  description = "IAM role ARN in Account A to assume"
  type        = string
}

variable "account_a_vpc_id" {
  description = "VPC ID in Account A where MSK is deployed"
  type        = string
}

variable "account_a_vpc_cidr" {
  description = "CIDR block of Account A VPC"
  type        = string
}

variable "msk_cluster_name" {
  description = "Name of the MSK cluster in Account A"
  type        = string
}

variable "msk_bootstrap_servers" {
  description = "MSK bootstrap servers (TLS endpoint)"
  type        = string
}

# Account B (Kafka Connect)
variable "account_b_vpc_cidr" {
  description = "CIDR block of Account B VPC"
  type        = string
}

# ClickHouse
variable "clickhouse_privatelink_service_name" {
  description = "ClickHouse PrivateLink service name"
  type        = string
}

variable "clickhouse_host" {
  description = "ClickHouse Cloud hostname"
  type        = string
}

variable "clickhouse_database" {
  description = "ClickHouse database name"
  type        = string
  default     = "default"
}

variable "clickhouse_password" {
  description = "ClickHouse password"
  type        = string
  sensitive   = true
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID"
  type        = string
}
```

### 3. Terraform Values

**File:** `terraform.tfvars`

```hcl
# General
aws_region  = "us-east-1"
environment = "prod"

# Account A (MSK)
account_a_role_arn     = "arn:aws:iam::111111111111:role/TerraformCrossAccountRole"
account_a_vpc_id       = "vpc-0123456789abcdef0"
account_a_vpc_cidr     = "10.0.0.0/16"
msk_cluster_name       = "my-msk-cluster"
msk_bootstrap_servers  = "b-1.cluster.xxxxx.kafka.us-east-1.amazonaws.com:9094"

# Account B (Kafka Connect)
account_b_vpc_cidr = "10.16.0.0/16"

# ClickHouse
clickhouse_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxxxxx"
clickhouse_host                     = "abc123.us-east-1.aws.clickhouse.cloud"
clickhouse_database                 = "default"
clickhouse_password                 = "your-secure-password"

# Transit Gateway
transit_gateway_id = "tgw-0123456789abcdef0"
```

### 4. User Data Script

**File:** `kafka_connect_userdata.sh`

```bash
#!/bin/bash
set -e

# Install dependencies
yum update -y
yum install -y java-11-amazon-corretto-headless wget tar unzip

# Create kafka user
useradd -r -s /bin/false kafka

# Install Kafka
cd /opt
wget https://archive.apache.org/dist/kafka/3.5.1/kafka_2.13-3.5.1.tgz
tar -xzf kafka_2.13-3.5.1.tgz
ln -s kafka_2.13-3.5.1 kafka
chown -R kafka:kafka /opt/kafka*

# Create directories
mkdir -p /var/log/kafka-connect
mkdir -p /opt/kafka-connect/plugins
mkdir -p /opt/kafka-connect/config

# Download ClickHouse connector
cd /opt/kafka-connect/plugins
mkdir -p clickhouse-kafka-connect
cd clickhouse-kafka-connect
wget https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.0.6/clickhouse-kafka-connect-v1.0.6.zip
unzip clickhouse-kafka-connect-v1.0.6.zip
chown -R kafka:kafka /opt/kafka-connect

# Create Kafka Connect configuration
cat > /opt/kafka-connect/config/connect-standalone.properties <<EOF
bootstrap.servers=${msk_bootstrap_servers}
security.protocol=SSL
plugin.path=/opt/kafka-connect/plugins
offset.storage.file.filename=/tmp/connect.offsets
EOF

# Create ClickHouse connector configuration
cat > /opt/kafka-connect/config/clickhouse-sink.properties <<EOF
name=clickhouse-sink-connector
connector.class=com.clickhouse.kafka.connect.ClickHouseSinkConnector
tasks.max=1
topics=your_kafka_topic
clickhouse.server.url=https://${clickhouse_host}:8443
clickhouse.server.database=${clickhouse_database}
clickhouse.server.user=default
clickhouse.server.password=YOUR_PASSWORD
clickhouse.table.name=your_table_name
EOF

# Create systemd service
cat > /etc/systemd/system/kafka-connect.service <<EOF
[Unit]
Description=Apache Kafka Connect
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="KAFKA_HEAP_OPTS=-Xms1G -Xmx1G"
ExecStart=/opt/kafka/bin/connect-standalone.sh \
  /opt/kafka-connect/config/connect-standalone.properties \
  /opt/kafka-connect/config/clickhouse-sink.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kafka-connect
```

> **📝 Note:** See complete user data script with helper scripts and monitoring in the repository.

---

## 🚀 Deployment Steps

### Step 1: Configure AWS Credentials

```bash
# ~/.aws/credentials
[account-a]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[account-b]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Plan Deployment

```bash
terraform plan
```

Review that it will create:
- ✅ 3 Security Groups (2 in Account B, 1 in Account A)
- ✅ Security Group Rules
- ✅ VPC Endpoint in Account B
- ✅ EC2 Instance in Account B
- ✅ IAM Role and Instance Profile

### Step 4: Apply Configuration

```bash
terraform apply
```

### Step 5: Attach MSK Security Group (MANUAL STEP)

**⚠️ IMPORTANT:** Terraform creates the security group in Account A, but you must manually attach it to your MSK cluster.

```bash
# Get the security group ID
terraform output msk_cross_account_sg_id

# In AWS Console (Account A):
# MSK → Clusters → Your Cluster → Edit Security Groups
# Add the new security group

# Or via CLI:
aws kafka update-security \
  --cluster-arn <msk-cluster-arn> \
  --current-version <version> \
  --security-group-ids <existing-sgs> <new-cross-account-sg> \
  --profile account-a
```

### Step 6: Verify Connectivity

#### Test TGW Connection

```bash
# Connect to Kafka Connect EC2
aws ssm start-session --target <instance-id> --profile account-b

# Test MSK connectivity
telnet <msk-broker-private-ip> 9094
# Should connect successfully
```

#### Test ClickHouse Endpoint

```bash
# On EC2
sudo su - ec2-user
./test-clickhouse.sh

# Expected: DNS resolves to private IP (10.16.y.y)
```

### Step 7: Configure Connector

```bash
./update-connector.sh my_kafka_topic my_clickhouse_table my_password
```

### Step 8: Monitor

```bash
sudo systemctl status kafka-connect
sudo tail -f /var/log/kafka-connect/kafka-connect.log
```

---

## 🔧 Troubleshooting

### Issue 1: Can't Connect to MSK from Account B

**Symptoms:**
```bash
telnet: Connection timed out
```

**Debug Checklist:**

1. ✅ **TGW Attachments Active**
```bash
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=vpc-id,Values=<vpc-id>"

# State should be: available
```

2. ✅ **Route Tables Configured**
```bash
# Account A: Route 10.16.0.0/16 → TGW
# Account B: Route 10.0.0.0/16 → TGW

aws ec2 describe-route-tables --vpc-id <vpc-id>
```

3. ✅ **Security Groups Correct**
```bash
# Account A MSK SG: Allow 9094 from 10.16.0.0/16
# Account B EC2 SG: Allow egress to 10.0.0.0/16:9094

aws ec2 describe-security-groups --group-ids <sg-id>
```

4. ✅ **MSK Has Cross-Account SG Attached**
```bash
aws kafka describe-cluster --cluster-arn <arn> \
  --query 'ClusterInfo.BrokerNodeGroupInfo.SecurityGroups'
```

### Issue 2: DNS Not Resolving to Private IP

**Problem:** ClickHouse hostname resolves to public IP

**Solution:**
```bash
# Check VPC Endpoint status
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <id>

# Should show:
# - State: available
# - PrivateDnsEnabled: true

# Wait 5-10 minutes, then restart EC2
sudo reboot
```

### Issue 3: Cross-Account Permissions Error

**Problem:** Terraform can't create resources in Account A

**Solution:**

1. Verify IAM role exists in Account A
2. Check trust policy allows Account B
3. Ensure role has proper permissions
4. Test assume role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT_A_ID:role/TerraformRole \
  --role-session-name test
```

---

## 📚 Quick Reference

### Connect to Kafka Connect EC2
```bash
aws ssm start-session --target <instance-id> --profile account-b
```

### Test MSK Connectivity
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

### Restart Kafka Connect
```bash
sudo systemctl restart kafka-connect
```

---

## 💰 Cost Estimate

| Component | Account | Monthly Cost |
|-----------|---------|--------------|
| Transit Gateway (data processed) | Both | ~$0.02/GB |
| Transit Gateway attachments | Both | ~$36 |
| VPC Endpoint | B | ~$7-10 |
| Data Transfer (PrivateLink) | B | $0.01/GB |
| EC2 t3.large | B | ~$60 |
| EBS 50GB GP3 | B | ~$5 |
| **Total** | | **~$108-118/month** |

---

## 🎯 Key Points

1. **Cross-Account Security Groups:** Must use CIDR blocks, not SG references
2. **Transit Gateway:** Requires proper routing in both accounts
3. **Manual Step:** MSK security group must be manually attached
4. **All Private:** No internet traffic for data transfer
5. **Kafka Connect:** PULLS from MSK, PUSHES to ClickHouse

---

## 📖 Resources

- [AWS Transit Gateway](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [ClickHouse Kafka Connect](https://github.com/ClickHouse/clickhouse-kafka-connect)
- [Cross-Account IAM Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)

---

**Version:** 1.0.0  
**Last Updated:** December 2024  
**Author:** Infrastructure Team
