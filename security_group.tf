resource "aws_security_group" "mfx_aggre_msk" {
  name        = "${var.environment}-mfx-aggre-msk"
  description = "Security group for MSK brokers"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id
}

resource "aws_security_group" "kafka_connect" {
  name        = "${var.environment}-kafka-connect"
  description = "Security group for Kafka Connect EC2"
  vpc_id      = data.aws_vpc.mfx_aggre_data_platform.id
}
