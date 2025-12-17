# MSK Connect Terraform Deployment Guide

Complete Terraform configuration for AWS MSK Connect with ClickHouse sink connector.

---

## 📦 What Gets Created

This Terraform configuration creates:

1. ✅ **S3 Bucket** - Stores the ClickHouse connector plugin
2. ✅ **Download Script** - Automatically downloads ClickHouse connector JAR
3. ✅ **Custom Plugin** - MSK Connect custom plugin with ClickHouse connector
4. ✅ **IAM Role** - Service execution role for MSK Connect with all permissions
5. ✅ **Security Groups** - MSK Connect SG with rules to MSK (Account A) and ClickHouse
6. ✅ **CloudWatch Log Group** - For MSK Connect worker logs
7. ✅ **MSK Connect Connector** - Fully configured with autoscaling

---

## 🏗️ Architecture

```
Account A (MSK)          TGW          Account B (mfx-aggre-data-platform)
┌─────────────┐          │           ┌──────────────────────────────────┐
│             │          │           │                                  │
│  MSK Cluster│◄─────────┼───────────┤  MSK Connect Cluster             │
│  Port 9094  │          │           │  - Auto-scaling (1-4 workers)    │
│             │          │           │  - Custom Plugin from S3          │
└─────────────┘          │           │  - IAM Role: msk-connect-role    │
                         │           │  - SG: msk-connect-sg             │
                         │           │                                  │
                         │           │  Security Group Rules:           │
                         │           │  OUT: 9094 → 10.0.0.0/16 (MSK)  │
                         │           │  OUT: 8443 → clickhouse-endpoint │
                         │           └──────────┬───────────────────────┘
                         │                      │
                         │                      │
                         │           ┌──────────▼───────────────┐
                         │           │  VPC Endpoint            │
                         │           │  clickhouse-endpoint-sg  │
                         │           │  (PrivateLink)           │
                         │           └──────────────────────────┘
                                                 │
                                                 │
                                      ┌──────────▼────────────┐
                                      │  ClickHouse Cloud     │
                                      └───────────────────────┘
```

---

## 📁 Files Structure

```
mfx-aggre-data-platform/
├── msk_connect.tf              # MSK Connect resources (NEW)
├── msk_connect_variables.tf    # Variables for MSK Connect (NEW)
├── terraform.tfvars            # Your variable values (UPDATE)
├── security_group.tf           # Update with ClickHouse endpoint SG
├── network.tf                  # Update with VPC endpoint
└── versions.tf                 # Add required providers
```

---

## 🚀 Deployment Steps

### Step 1: Add Provider Requirements

Add to your `versions.tf` or `aws.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
```

### Step 2: Add New Files

Copy these files to your project:

1. **`msk_connect.tf`** - Main MSK Connect configuration
2. **`msk_connect_variables.tf`** - Variables for MSK Connect

### Step 3: Update `terraform.tfvars`

Add these variables to your existing `terraform.tfvars`:

```hcl
# Account A (MSK)
account_a_id                    = "111111111111"
account_a_vpc_cidr              = "10.0.0.0/16"
msk_cluster_name_account_a      = "my-msk-cluster"
msk_bootstrap_servers_account_a = "b-1.msk.kafka.us-east-1.amazonaws.com:9094,b-2.msk.kafka.us-east-1.amazonaws.com:9094"

# Kafka Topics
kafka_topics_to_sink = "events,logs,metrics"

# ClickHouse
clickhouse_privatelink_service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-xxxxx"
clickhouse_host                     = "cluster.us-east-1.aws.clickhouse.cloud"
clickhouse_database                 = "default"
clickhouse_username                 = "default"
clickhouse_password                 = "your-password"
clickhouse_table_name               = "events_table"

# AWS Region
aws_region = "us-east-1"
```

### Step 4: Ensure ClickHouse VPC Endpoint Exists

In your `network.tf`, make sure you have:

```hcl
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

resource "aws_security_group" "clickhouse_endpoint" {
  name   = "${var.environment}-clickhouse-endpoint-sg"
  vpc_id = data.aws_vpc.mfx_aggre_data_platform.id

  tags = {
    Name = "${var.environment}-clickhouse-endpoint-sg"
  }
}
```

### Step 5: Initialize and Apply

```bash
# Initialize Terraform (downloads required providers)
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Apply (creates all resources)
terraform apply
```

**Deployment time:** ~15-20 minutes
- S3 bucket: ~1 min
- Custom plugin: ~2-3 min
- Connector: ~10-15 min

---

## 📊 What Happens During Deployment

### Phase 1: S3 and Plugin (1-3 minutes)
```
1. Creates S3 bucket: prod-mfx-aggre-msk-connect-plugins
2. Downloads ClickHouse connector (local-exec)
3. Uploads to S3: plugins/clickhouse-kafka-connect-v1.0.6.zip
4. Creates custom plugin in AWS MSK Connect
```

### Phase 2: IAM and Networking (1-2 minutes)
```
5. Creates IAM role: prod-msk-connect-role
6. Attaches policies (MSK, S3, CloudWatch, VPC, Secrets Manager)
7. Creates security group: prod-msk-connect-sg
8. Creates security group rules (to MSK and ClickHouse)
9. Creates CloudWatch log group
```

### Phase 3: MSK Connect Connector (10-15 minutes)
```
10. Creates MSK Connect connector
11. Provisions workers (ENIs in your VPC)
12. Downloads plugin from S3
13. Starts Kafka Connect workers
14. Connects to MSK in Account A
15. Starts consuming from topics
16. Starts pushing to ClickHouse
```

---

## 🔍 Monitoring

### Check Connector Status

```bash
# Get connector ARN
terraform output msk_connect_connector_arn

# Check status
aws kafkaconnect describe-connector \
  --connector-arn <connector-arn>

# Should show: State: RUNNING
```

### View Logs

```bash
# Get log group name
terraform output msk_connect_log_group

# Tail logs
aws logs tail /aws/msk-connect/prod-clickhouse-sink --follow

# Or in AWS Console
# CloudWatch → Logs → /aws/msk-connect/prod-clickhouse-sink
```

### Monitor in AWS Console

1. Go to **MSK** → **MSK Connect** → **Connectors**
2. Click on `prod-clickhouse-sink`
3. Check **Monitoring** tab:
   - Worker count (should auto-scale 1-4)
   - CPU utilization
   - Network throughput
   - Task status

---

## ✅ Verification

### Step 1: Check Connector is Running

```bash
aws kafkaconnect describe-connector \
  --connector-arn $(terraform output -raw msk_connect_connector_arn) \
  --query 'ConnectorState' \
  --output text

# Expected: RUNNING
```

### Step 2: Check Data in ClickHouse

```sql
-- In ClickHouse Cloud console
SELECT COUNT(*) FROM your_table_name;

SELECT * FROM your_table_name 
ORDER BY timestamp DESC 
LIMIT 10;
```

### Step 3: Check CloudWatch Metrics

```bash
# View metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/KafkaConnect \
  --metric-name ConnectorStatus \
  --dimensions Name=ConnectorName,Value=prod-clickhouse-sink \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Average
```

---

## 🔧 Configuration Details

### Autoscaling Configuration

The connector is configured to autoscale:

```hcl
capacity {
  autoscaling {
    mcu_count        = 1      # 1 MCU per worker
    min_worker_count = 1      # Minimum 1 worker
    max_worker_count = 4      # Maximum 4 workers
    
    scale_in_policy {
      cpu_utilization_percentage = 20   # Scale down at 20% CPU
    }
    
    scale_out_policy {
      cpu_utilization_percentage = 80   # Scale up at 80% CPU
    }
  }
}
```

**What this means:**
- Starts with 1 worker (1 MCU)
- Scales up to 4 workers when CPU > 80%
- Scales down to 1 worker when CPU < 20%
- Each worker can handle ~10-20 MB/s throughput

### Connector Configuration

Key settings in the connector:

```properties
tasks.max=2                    # 2 tasks per worker
batch.size=1000                # 1000 records per batch
buffer.count.records=10000     # Buffer up to 10k records
offset.flush.interval.ms=60000 # Flush offsets every 60s
errors.tolerance=all           # Continue on errors
errors.deadletterqueue=dlq-clickhouse-sink-prod  # Send errors to DLQ
```

### Security Configuration

All communication is encrypted:

```
MSK → MSK Connect: TLS (port 9094)
MSK Connect → ClickHouse: HTTPS (port 8443) via PrivateLink
MSK Connect → AWS APIs: HTTPS (port 443)
```

---

## 💰 Cost Estimate

### MSK Connect Costs

| Workers | MCU Hours/Month | Cost/Month (us-east-1) |
|---------|-----------------|------------------------|
| 1 worker | 730 MCU-hours | ~$80 |
| 2 workers | 1,460 MCU-hours | ~$160 |
| 4 workers | 2,920 MCU-hours | ~$320 |

**With autoscaling (1-4 workers):**
- Low traffic: ~$80/month
- Medium traffic: ~$120-160/month
- High traffic: ~$240-320/month

**Additional costs:**
- S3 storage: ~$0.50/month
- CloudWatch logs: ~$2-5/month
- Data transfer (PrivateLink): $0.01/GB

**Total estimated: $85-330/month depending on load**

---

## 🔄 Updates and Changes

### Update Connector Configuration

To change topics, ClickHouse settings, etc:

1. Edit `terraform.tfvars`
2. Run `terraform apply`
3. MSK Connect will update the connector (takes ~5-10 minutes)

**Example - Add new topic:**
```hcl
kafka_topics_to_sink = "events,logs,metrics,new_topic"
```

### Update Plugin Version

1. Download new plugin version
2. Upload to S3
3. Update custom plugin
4. Update connector to use new plugin revision

```bash
# Download new version
wget https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.0.7/clickhouse-kafka-connect-v1.0.7.zip

# Upload to S3
aws s3 cp clickhouse-kafka-connect-v1.0.7.zip \
  s3://prod-mfx-aggre-msk-connect-plugins/plugins/

# Update will happen automatically on next terraform apply
```

---

## 🐛 Troubleshooting

### Issue 1: Connector Stuck in "Creating"

**Check:**
```bash
aws kafkaconnect describe-connector \
  --connector-arn <arn> \
  --query 'ConnectorState'
```

**Common causes:**
- Security group doesn't allow outbound to MSK
- No route to Account A via TGW
- IAM role doesn't have MSK permissions

**Solution:**
```bash
# Check security group
aws ec2 describe-security-groups \
  --group-ids $(terraform output -raw msk_connect_sg_id)

# Check routes
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-id>"
```

### Issue 2: Can't Connect to MSK

**Error in logs:**
```
Failed to connect to MSK broker
```

**Debug:**
```bash
# Test from a VM in Account B
telnet b-1.msk.kafka.us-east-1.amazonaws.com 9094

# Check TGW attachment
aws ec2 describe-transit-gateway-vpc-attachments

# Check MSK security group in Account A
aws ec2 describe-security-groups \
  --group-ids <msk-sg-id> \
  --profile account-a
```

### Issue 3: Can't Connect to ClickHouse

**Error in logs:**
```
Failed to connect to ClickHouse
```

**Debug:**
```bash
# Check VPC Endpoint status
terraform output clickhouse_vpc_endpoint_id
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids <id>

# Should be: State: available, PrivateDnsEnabled: true

# Check DNS resolution (from EC2 in same VPC)
nslookup your-cluster.clickhouse.cloud
# Should resolve to 10.16.x.x
```

### Issue 4: Data Not Appearing in ClickHouse

**Check:**
1. Kafka topic has data
2. Table exists in ClickHouse
3. Table schema matches data format
4. Check connector logs for errors

```bash
# View last 100 log events
aws logs tail /aws/msk-connect/prod-clickhouse-sink \
  --since 1h \
  | grep ERROR

# Check connector tasks
aws kafkaconnect describe-connector \
  --connector-arn <arn> \
  --query 'ConnectorState'
```

---

## 🗑️ Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Resources that will be deleted:**
- MSK Connect connector
- Custom plugin
- S3 bucket (and objects)
- Security groups
- IAM role
- CloudWatch log group

**Time to destroy:** ~5-10 minutes

---

## 📚 Additional Resources

- [AWS MSK Connect Documentation](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect.html)
- [ClickHouse Kafka Connect](https://github.com/ClickHouse/clickhouse-kafka-connect)
- [Terraform MSK Connect Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mskconnect_connector)

---

## 🎯 Key Points

✅ **Fully automated** - Downloads plugin, creates all resources
✅ **Uses your existing VPC** - `mfx-aggre-data-platform`
✅ **Cross-account** - Connects to MSK in Account A via TGW
✅ **Private connectivity** - All traffic via TGW and PrivateLink
✅ **Auto-scaling** - Scales 1-4 workers based on load
✅ **Managed by AWS** - No servers to patch or maintain
✅ **Full monitoring** - CloudWatch logs and metrics

---

**Version:** 1.0.0  
**Compatible with:** mfx-aggre-data-platform infrastructure
