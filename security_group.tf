###############################################
# MSK Security Group
###############################################
resource "aws_security_group" "mfx_aggre_msk" {
  name        = "${var.environment}-mfx-aggre-msk"
  description = "Security group for MSK brokers"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id
}

# MSK ingress: Allow Kafka Connect to reach MSK brokers (TLS 9098)
resource "aws_vpc_security_group_ingress_rule" "kafka_connect_to_msk_ingress" {
  security_group_id            = aws_security_group.mfx_aggre_msk.id
  referenced_security_group_id = aws_security_group.kafka_connect.id

  ip_protocol = "tcp"
  from_port   = 9098
  to_port     = 9098
}

# MSK egress: Allow response traffic back to Kafka Connect
resource "aws_vpc_security_group_egress_rule" "msk_to_kafka_connect_egress" {
  security_group_id            = aws_security_group.mfx_aggre_msk.id
  referenced_security_group_id = aws_security_group.kafka_connect.id

  ip_protocol = "tcp"
  from_port   = 9098
  to_port     = 9098
}


###############################################
# Kafka Connect Security Group
###############################################
resource "aws_security_group" "kafka_connect" {
  name        = "${var.environment}-kafka-connect"
  description = "Security group for Kafka Connect EC2 instances"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id
}

# Kafka Connect egress: Allow connection to MSK brokers
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_msk_egress" {
  security_group_id            = aws_security_group.kafka_connect.id
  referenced_security_group_id = aws_security_group.mfx_aggre_msk.id

  ip_protocol = "tcp"
  from_port   = 9098
  to_port     = 9098
}

# Kafka Connect ingress (optional): Allow REST API if needed (8083)
# Uncomment if you need REST access
# resource "aws_vpc_security_group_ingress_rule" "admin_to_kafka_connect_rest" {
#   security_group_id            = aws_security_group.kafka_connect.id
#   referenced_security_group_id = aws_security_group.admin.id
#
#   ip_protocol = "tcp"
#   from_port   = 8083
#   to_port     = 8083
# }


###############################################
# ClickHouse PrivateLink Security Group
###############################################
resource "aws_security_group" "clickhouse_pl" {
  name        = "${var.environment}-clickhouse-pl"
  description = "Security group for ClickHouse PrivateLink endpoint"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id
}

# ClickHouse PL ingress: Allow Kafka Connect to reach ClickHouse (port 9440)
resource "aws_vpc_security_group_ingress_rule" "kafka_connect_to_clickhouse_ingress" {
  security_group_id            = aws_security_group.clickhouse_pl.id
  referenced_security_group_id = aws_security_group.kafka_connect.id

  ip_protocol = "tcp"
  from_port   = 9440
  to_port     = 9440
}

# Kafka Connect egress: Allow traffic to ClickHouse PL endpoint
resource "aws_vpc_security_group_egress_rule" "kafka_connect_to_clickhouse_egress" {
  security_group_id            = aws_security_group.kafka_connect.id
  referenced_security_group_id = aws_security_group.clickhouse_pl.id

  ip_protocol = "tcp"
  from_port   = 9440
  to_port     = 9440
}
