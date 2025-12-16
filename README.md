# Kafka Connect: Cross-Account MSK to ClickHouse via Transit Gateway

Integration for connecting MSK (Account A) → Kafka Connect EC2 (Account B) → ClickHouse Cloud

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                       AWS ACCOUNT A (MSK)                             │
│                       VPC: 10.0.0.0/16                                │
│                                                                        │
│   ┌────────────────────────────────────────────┐                     │
│   │  MSK Cluster (Existing)                    │                     │
│   │  - Kafka Topics                            │                     │
│   │  - Port: 9094 (TLS)                        │                     │
│   │                                             │                     │
│   │  Security Group:                           │                     │
│   │  INBOUND: 9094 from 10.16.0.0/16          │                     │
│   └────────────────┬───────────────────────────┘                     │
│                    │                                                  │
│              Transit Gateway                                          │
└────────────────────┼──────────────────────────────────────────────────┘
                     │
                     │ TGW Connection
                     │
┌────────────────────▼──────────────────────────────────────────────────┐
│                  AWS ACCOUNT B (Kafka Connect)                         │
│                  VPC: mfx-aggre-data-platform (10.16.0.0/16)          │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │  Private Subnet                                           │        │
│  │                                                            │        │
│  │  ┌───────────────────────────────────────────┐           │        │
│  │  │  EC2: Kafka Connect                        │           │        │
│  │  │  - t3.large                                │           │        │
│  │  │  - Pulls from MSK via TGW (9094)          │           │        │
│  │  │  - Pushes to ClickHouse (8443)            │           │        │
│  │  │                                            │           │        │
│  │  │  SG: kafka_connect_ec2                    │           │        │
│  │  │  OUT: 9094 → 10.0.0.0/16 (MSK)           │           │        │
│  │  │  OUT: 8443 → VPC Endpoint SG              │           │        │
│  │  └─────────────────────┬──────────────────────┘           │        │
│  │                        │                                   │        │
│  │                        ▼                                   │        │
│  │  ┌───────────────────────────────────────────┐           │        │
│  │  │  VPC Endpoint (PrivateLink)                │           │        │
│  │  │  - Private IP: 10.16.y.y                  │           │        │
│  │  │  - DNS: cluster.clickhouse.cloud          │           │        │
│  │  │                                            │           │        │
│  │  │  SG: clickhouse_endpoint                  │           │        │
│  │  │  IN: 8443 from kafka_connect_ec2 SG       │           │        │
│  │  └─────────────────────┬──────────────────────┘           │        │
│  └────────────────────────┼────────────────────────────────────┘        │
└───────────────────────────┼────────────────────────────────────────────┘
                            │
                            │ AWS PrivateLink
                            ▼
                 ┌────────────────────────┐
                 │  ClickHouse Cloud      │
                 │  Port: 8443            │
                 └────────────────────────┘
```

---

## 📦 Files to Add to Your Project

Based on your existing structure, add these files:

```
mfx-aggre-data-platform/
├── security_group.tf               (ADD RULES HERE)
├── network.tf                       (ADD VPC ENDPOINT & ROUTE HERE)
├── ec2_kafka_connect.tf            (NEW FILE)
├── iam_additions.tf                (NEW FILE)
├── variable.tf                      (ADD VARIABLES HERE)
└── kafka_connect_userdata.sh       (NEW FILE)
```

---

## 🔐 Security Group Rules to Add

### In Your Existing `security_group.tf`

Add these rules to connect Kafka Connect with MSK and ClickHouse:

```hcl
# ==============================================================================
# Security Groups for Kafka Connect
# ==============================================================================

# Security Group for ClickHouse VPC Endpoint
resource "aws_security_group" "clickhouse_endpoint" {
  name        = "${var.environment}-clickhouse-endpoint-sg"
  description = "Security group for ClickHouse VPC Endpoint"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id

  tags = {
    Name        = "${var.environment}-clickhouse-endpoint-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# Security Group for Kafka Connect EC2
resource "aws_security_group" "kafka_connect_ec2" {
  name        = "${var.environment}-kafka-connect-ec2-sg"
  description = "Security group for Kafka Connect EC2"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# --- Kafka Connect to MSK (Account A via TGW) ---

resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_msk_account_a" {
  security_group_id = aws_security_group.kafka_connect_ec2.id
  cidr_ipv4         = var.account_a_vpc_cidr
  from_port         = 9094
  to_port           = 9094
  ip_protocol       = "tcp"
  description       = "Pull from MSK in Account A via TGW"
}

# --- Kafka Connect to ClickHouse ---

resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_https" {
  security_group_id            = aws_security_group.kafka_connect_ec2.id
  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Push to ClickHouse HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_https" {
  security_group_id            = aws_security_group.clickhouse_endpoint.id
  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow from Kafka Connect"
}

# --- Internet for plugins ---

resource "aws_vpc_security_group_egress_rule" "kafka_connect_https_egress" {
  security_group_id = aws_security_group.kafka_connect_ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS for plugins"
}
```

---

## 🌐 Network Changes

### In Your Existing `network.tf`

Add VPC Endpoint for ClickHouse and route to Account A:

```hcl
# --- VPC Endpoint for ClickHouse ---

resource "aws_vpc_endpoint" "clickhouse" {
  vpc_id              = data.aws_vpc.mfx_aggre_data_platform.id
  service_name        = var.clickhouse_privatelink_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.mfx_aggre_data_platform_private[0].id]
  security_group_ids  = [aws_security_group.clickhouse_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.environment}-clickhouse-endpoint"
  }
}

# --- Route to Account A MSK via TGW ---

resource "aws_route" "private_to_account_a_msk" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.account_a_vpc_cidr
  transit_gateway_id     = local.central_transit_gateway_ids[var.environment]
}
```

---

## 📝 Variables to Add

### In Your Existing `variable.tf`

```hcl
# --- Account A (MSK) ---

variable "account_a_vpc_cidr" {
  description = "CIDR of Account A VPC"
  type        = string
}

variable "msk_bootstrap_servers_account_a" {
  description = "MSK bootstrap servers"
  type        = string
}

# --- ClickHouse ---

variable "clickhouse_privatelink_service_name" {
  description = "ClickHouse PrivateLink service name"
  type        = string
}

variable "clickhouse_host" {
  description = "ClickHouse hostname"
  type        = string
}

variable "clickhouse_database" {
  type    = string
  default = "default"
}

variable "clickhouse_password" {
  type      = string
  sensitive = true
}
```

---

## 🚀 New Files to Create

### 1. `ec2_kafka_connect.tf`

```hcl
resource "aws_instance" "kafka_connect" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.mfx_aggre_data_platform_private[0].id
  vpc_security_group_ids = [aws_security_group.kafka_connect_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.kafka_connect_ec2.name

  user_data = templatefile("${path.module}/kafka_connect_userdata.sh", {
    msk_bootstrap_servers = var.msk_bootstrap_servers_account_a
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

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

### 2. `iam_additions.tf`

```hcl
resource "aws_iam_role" "kafka_connect_ec2" {
  name = "${var.environment}-kafka-connect-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "kafka_connect_ssm" {
  role       = aws_iam_role.kafka_connect_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "kafka_connect_ec2" {
  name = "${var.environment}-kafka-connect-ec2-profile"
  role = aws_iam_role.kafka_connect_ec2.name
}
```

### 3. `kafka_connect_userdata.sh`

```bash
#!/bin/bash
set -e

# Install Java and tools
yum update -y
yum install -y java-11-amazon-corretto-headless wget unzip

# Install Kafka
cd /opt
wget https://archive.apache.org/dist/kafka/3.5.1/kafka_2.13-3.5.1.tgz
tar -xzf kafka_2.13-3.5.1.tgz
ln -s kafka_2.13-3.5.1 kafka

# Download ClickHouse connector
mkdir -p /opt/kafka-connect/plugins/clickhouse
cd /opt/kafka-connect/plugins/clickhouse
wget https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.0.6/clickhouse-kafka-connect-v1.0.6.zip
unzip clickhouse-kafka-connect-v1.0.6.zip

# Create configs
cat > /opt/kafka-connect/config/connect-standalone.properties <<EOF
bootstrap.servers=${msk_bootstrap_servers}
security.protocol=SSL
plugin.path=/opt/kafka-connect/plugins
EOF

cat > /opt/kafka-connect/config/clickhouse-sink.properties <<EOF
name=clickhouse-sink
connector.class=com.clickhouse.kafka.connect.ClickHouseSinkConnector
topics=your_kafka_topic
clickhouse.server.url=https://${clickhouse_host}:8443
clickhouse.server.database=${clickhouse_database}
clickhouse.table.name=your_table
EOF

# Create systemd service
cat > /etc/systemd/system/kafka-connect.service <<EOF
[Unit]
Description=Kafka Connect
[Service]
ExecStart=/opt/kafka/bin/connect-standalone.sh \
  /opt/kafka-connect/config/connect-standalone.properties \
  /opt/kafka-connect/config/clickhouse-sink.properties
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl enable kafka-connect
```

---

## ⚙️ Configuration Steps

### 1. Update `terraform.tfvars`

```hcl
# Account A (MSK)
account_a_vpc_cidr              = "10.0.0.0/16"
msk_bootstrap_servers_account_a = "b-1.xxx.kafka.us-east-1.amazonaws.com:9094"

# ClickHouse
clickhouse_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx"
clickhouse_host                     = "cluster.clickhouse.cloud"
clickhouse_database                 = "default"
clickhouse_password                 = "your-password"
```

### 2. Apply Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 3. Configure MSK in Account A

**⚠️ MANUAL STEP:** Add security group rule in Account A MSK:

```hcl
# In Account A MSK security group
INBOUND: Port 9094, Source: 10.16.0.0/16
```

### 4. Verify

```bash
# Connect to EC2
aws ssm start-session --target <instance-id>

# Test MSK
telnet <msk-broker-ip> 9094

# Test ClickHouse
nslookup cluster.clickhouse.cloud
# Should resolve to 10.16.y.y (private IP)
```

---

## 🔄 Data Flow

1. **MSK (Account A)** → stores data in topics
2. **Kafka Connect** pulls via TGW (port 9094)
3. **ClickHouse Connector** transforms data
4. **VPC Endpoint** routes to ClickHouse (port 8443)
5. **ClickHouse Cloud** receives via PrivateLink

**All private - no internet!**

---

## 📊 Summary Table

| Component | Location | Purpose |
|-----------|----------|---------|
| MSK | Account A | Source of data |
| Transit Gateway | Both | Cross-account routing |
| Kafka Connect EC2 | Account B | Data pipeline |
| VPC Endpoint | Account B | ClickHouse connection |
| ClickHouse | Cloud | Destination |

---

## 🔧 Troubleshooting

### Can't connect to MSK

```bash
# Check route exists
aws ec2 describe-route-tables --vpc-id <vpc-id>

# Check TGW attachment
aws ec2 describe-transit-gateway-vpc-attachments

# Test from EC2
telnet <msk-private-ip> 9094
```

### ClickHouse DNS not resolving to private IP

```bash
# Check VPC Endpoint status
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <id>

# Should show State: available, PrivateDnsEnabled: true
# Wait 5-10 minutes, then restart EC2
```

---

**Version:** 1.0.0  
**Compatible with:** Your existing mfx-aggre-data-platform structure
