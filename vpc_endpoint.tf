resource "aws_security_group" "clickhouse_pl" {
  name   = "${var.environment}-clickhouse-pl"
  vpc_id = data.aws_vpc.mfx_aggre_data_platform.id
}

resource "aws_vpc_endpoint" "clickhouse" {
  vpc_id              = data.aws_vpc.mfx_aggre_data_platform.id
  service_name        = var.clickhouse_privatelink_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.mfx_aggre_data_platform_private[*].id
  security_group_ids  = [aws_security_group.clickhouse_pl.id]
  private_dns_enabled = true
}
