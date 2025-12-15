resource "aws_instance" "kafka_connect" {
  ami                         = var.kafka_connect_ami
  instance_type               = "m5.large"
  subnet_id                   = aws_subnet.mfx_aggre_data_platform_private[0].id
  vpc_security_group_ids      = [aws_security_group.kafka_connect.id]
  associate_public_ip_address = false

  user_data = file("user_data/kafka_connect.sh")

  tags = {
    Name = "${var.environment}-kafka-connect"
  }
}
