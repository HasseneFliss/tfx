resource "aws_msk_cluster" "mfx_aggre" {
  cluster_name           = "${var.environment}-mfx-aggre-msk"
  kafka_version          = var.msk_kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = aws_subnet.mfx_aggre_data_platform_private[*].id
    security_groups = [aws_security_group.mfx_aggre_msk.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }
}
