variable "environment" {
  type        = string
  description = "Target environment"
}

variable "msk_kafka_version" {
  type    = string
  default = "3.5.1"
}

variable "msk_instance_type" {
  type    = string
  default = "kafka.m5.large"
}

variable "kafka_connect_ami" {
  type = string
}

variable "clickhouse_privatelink_service_name" {
  type = string
}
