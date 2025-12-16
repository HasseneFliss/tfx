# ==============================================================================
# Kafka Connect EC2 Instance to ClickHouse Cloud via PrivateLink
# ==============================================================================
# This configuration creates:
# - EC2 instance with Kafka Connect
# - VPC Endpoint for ClickHouse PrivateLink
# - All necessary security groups and rules
# ==============================================================================

# --- Data Sources ---

data "aws_vpc" "mfx_aggre_data_platform" {
  filter {
    name   = "tag:Name"
    values = ["mfx-aggre-data-platform"]
  }
}

data "aws_ami" "amazon_linux_2" {
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

# --- ClickHouse VPC Endpoint (PrivateLink) ---

resource "aws_vpc_endpoint" "clickhouse" {
  vpc_id            = data.aws_vpc.mfx_aggre_data_platform.id
  service_name      = var.clickhouse_privatelink_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    aws_subnet.mfx_aggre_data_platform_private[0].id
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

# --- Security Groups ---

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
  description = "Security group for Kafka Connect EC2 instance"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-sg"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# --- Security Group Rules ---

# OUTBOUND from Kafka Connect to MSK (EC2 pulls data from MSK)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_msk" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  referenced_security_group_id = aws_security_group.msk_cluster.id
  from_port                    = 9094
  to_port                      = 9094
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to pull data from MSK"
}

# INBOUND to MSK from Kafka Connect
resource "aws_vpc_security_group_ingress_rule" "msk_from_kafka_connect" {
  security_group_id = aws_security_group.msk_cluster.id

  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 9094
  to_port                      = 9094
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to access MSK"
}

# OUTBOUND from Kafka Connect to ClickHouse VPC Endpoint (EC2 pushes data to ClickHouse)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_https" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to push data to ClickHouse HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_native" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  referenced_security_group_id = aws_security_group.clickhouse_endpoint.id
  from_port                    = 9440
  to_port                      = 9440
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to push data to ClickHouse Native"
}

# INBOUND to ClickHouse VPC Endpoint from Kafka Connect
resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_https" {
  security_group_id = aws_security_group.clickhouse_endpoint.id

  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 8443
  to_port                      = 8443
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to ClickHouse HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "clickhouse_from_kafka_connect_native" {
  security_group_id = aws_security_group.clickhouse_endpoint.id

  referenced_security_group_id = aws_security_group.kafka_connect_ec2.id
  from_port                    = 9440
  to_port                      = 9440
  ip_protocol                  = "tcp"
  description                  = "Allow Kafka Connect to ClickHouse Native"
}

# OUTBOUND from Kafka Connect for internet access (downloading plugins)
resource "aws_vpc_security_group_egress_rule" "kafka_connect_https_egress" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  description = "Allow HTTPS outbound for plugins"
}

resource "aws_vpc_security_group_egress_rule" "kafka_connect_http_egress" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  description = "Allow HTTP outbound"
}

resource "aws_vpc_security_group_egress_rule" "kafka_connect_dns" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"
  description = "Allow DNS"
}

# INBOUND to Kafka Connect for SSH
resource "aws_vpc_security_group_ingress_rule" "kafka_connect_ssh" {
  security_group_id = aws_security_group.kafka_connect_ec2.id

  cidr_ipv4   = data.aws_vpc.mfx_aggre_data_platform.cidr_block
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  description = "Allow SSH from VPC"
}

# --- IAM Role for Kafka Connect EC2 ---

resource "aws_iam_role" "kafka_connect_ec2" {
  name = "${var.environment}-kafka-connect-ec2-role"

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
  name = "${var.environment}-kafka-connect-ec2-policy"
  role = aws_iam_role.kafka_connect_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:DescribeCluster",
          "kafka:DescribeClusterV2",
          "kafka:GetBootstrapBrokers"
        ]
        Resource = aws_msk_cluster.mfx_aggre_data_platform.arn
      },
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "kafka_connect_ssm" {
  role       = aws_iam_role.kafka_connect_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "kafka_connect_ec2" {
  name = "${var.environment}-kafka-connect-ec2-profile"
  role = aws_iam_role.kafka_connect_ec2.name

  tags = {
    Name        = "${var.environment}-kafka-connect-ec2-profile"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# --- EC2 Instance for Kafka Connect ---

resource "aws_instance" "kafka_connect" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.large"
  subnet_id     = aws_subnet.mfx_aggre_data_platform_private[0].id

  vpc_security_group_ids = [
    aws_security_group.kafka_connect_ec2.id
  ]

  iam_instance_profile = aws_iam_instance_profile.kafka_connect_ec2.name

  user_data = templatefile("${path.module}/kafka_connect_userdata.sh", {
    msk_bootstrap_servers = aws_msk_cluster.mfx_aggre_data_platform.bootstrap_brokers_tls
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

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "kafka_connect" {
  name              = "/aws/ec2/kafka-connect/${var.environment}"
  retention_in_days = 7

  tags = {
    Name        = "${var.environment}-kafka-connect-logs"
    App         = "mfx-aggre-data-platform"
    Environment = var.environment
  }
}

# --- Outputs ---

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

output "clickhouse_vpc_endpoint_dns" {
  description = "DNS names of the ClickHouse VPC Endpoint"
  value       = aws_vpc_endpoint.clickhouse.dns_entry
}

output "connection_command" {
  description = "Command to connect to the Kafka Connect instance"
  value       = "aws ssm start-session --target ${aws_instance.kafka_connect.id}"
}
