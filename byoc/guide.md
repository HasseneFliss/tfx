# ClickHouse BYOC on EKS - Fintech Implementation Guide
## Your Team's Responsibilities + JDBC Architecture

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [JDBC Connection Architecture](#jdbc-connection-architecture)
3. [Responsibility Matrix](#responsibility-matrix)
4. [Your Team's Infrastructure Setup](#your-teams-infrastructure-setup)
5. [Questions to Ask ClickHouse Team](#questions-to-ask-clickhouse-team)
6. [Implementation Checklist](#implementation-checklist)

---

## Architecture Overview

### High-Level Architecture (Fully Private)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           YOUR AWS ACCOUNT (Fintech)                         │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         YOUR VPC (10.0.0.0/16)                         │ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │  Private Subnet AZ-A (10.0.1.0/24)                               │ │ │
│  │  │                                                                   │ │ │
│  │  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │ │ │
│  │  │  │ API Service 1   │  │ API Service 2   │  │ API Service 3   │ │ │ │
│  │  │  │ (JDBC Client)   │  │ (JDBC Client)   │  │ (JDBC Client)   │ │ │ │
│  │  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │ │ │
│  │  │           │                     │                     │          │ │ │
│  │  │           └─────────────────────┼─────────────────────┘          │ │ │
│  │  │                                 │                                │ │ │
│  │  │                        ┌────────▼────────┐                       │ │ │
│  │  │                        │ Internal NLB    │                       │ │ │
│  │  │                        │ (Private only)  │                       │ │ │
│  │  │                        │ Port: 8123,9000 │                       │ │ │
│  │  │                        └────────┬────────┘                       │ │ │
│  │  └─────────────────────────────────┼───────────────────────────────┘ │ │
│  │                                    │                                  │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │  EKS Worker Nodes (MANAGED BY CLICKHOUSE TEAM)                   │ │ │
│  │  │                                                                   │ │ │
│  │  │  AZ-A:              AZ-B:              AZ-C:                     │ │ │
│  │  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │ │ │
│  │  │  │ Worker      │   │ Worker      │   │ Worker      │           │ │ │
│  │  │  │ Node 1      │   │ Node 3      │   │ Node 5      │           │ │ │
│  │  │  │             │   │             │   │             │           │ │ │
│  │  │  │ ┌─────────┐ │   │ ┌─────────┐ │   │ ┌─────────┐ │           │ │ │
│  │  │  │ │CH Pod 0 │ │   │ │CH Pod 2 │ │   │ │CH Pod 4 │ │           │ │ │
│  │  │  │ └────┬────┘ │   │ └────┬────┘ │   │ └────┬────┘ │           │ │ │
│  │  │  │      │      │   │      │      │   │      │      │           │ │ │
│  │  │  │ ┌────▼────┐ │   │ ┌────▼────┐ │   │ ┌────▼────┐ │           │ │ │
│  │  │  │ │EBS Vol  │ │   │ │EBS Vol  │ │   │ │EBS Vol  │ │           │ │ │
│  │  │  │ │1TB gp3  │ │   │ │1TB gp3  │ │   │ │1TB gp3  │ │           │ │ │
│  │  │  │ └─────────┘ │   │ └─────────┘ │   │ └─────────┘ │           │ │ │
│  │  │  └─────────────┘   └─────────────┘   └─────────────┘           │ │ │
│  │  └──────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │  VPC Endpoints (YOUR RESPONSIBILITY)                             │ │ │
│  │  │  • com.amazonaws.region.s3 (Gateway - Free)                      │ │ │
│  │  │  • com.amazonaws.region.ecr.api                                  │ │ │
│  │  │  • com.amazonaws.region.ecr.dkr                                  │ │ │
│  │  │  • com.amazonaws.region.ec2                                      │ │ │
│  │  │  • com.amazonaws.region.eks                                      │ │ │
│  │  │  • com.amazonaws.region.sts                                      │ │ │
│  │  │  • com.amazonaws.region.logs                                     │ │ │
│  │  │  • com.amazonaws.region.elasticloadbalancing                     │ │ │
│  │  └──────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │  Your Managed Services                                           │ │ │
│  │  │  • S3 Buckets (Backups, Logs)                                    │ │ │
│  │  │  • CloudWatch (Logs, Metrics, Alarms)                            │ │ │
│  │  │  • KMS Keys (Encryption)                                         │ │ │
│  │  │  • Route53 Private Hosted Zone                                   │ │ │
│  │  │  • Security Groups                                               │ │ │
│  │  │  • IAM Roles (IRSA)                                              │ │ │
│  │  └──────────────────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  Direct Connect / VPN                                                  │ │
│  │  • Connection to On-Premises                                           │ │
│  │  • Developer Access (kubectl)                                          │ │
│  │  • CI/CD Pipeline Access                                               │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘

                                    ▲
                                    │
                       Cross-Account IAM Role
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │  ClickHouse Cloud Account     │
                    │  • EKS Cluster Creation       │
                    │  • ClickHouse Operator        │
                    │  • Cluster Management         │
                    │  • Monitoring & Support       │
                    └───────────────────────────────┘
```

---

## JDBC Connection Architecture

### Multiple APIs Connecting to ClickHouse

```
┌────────────────────────────────────────────────────────────────────┐
│                    Application Layer (Your APIs)                   │
│                                                                    │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │
│  │ Trading API     │  │ Analytics API   │  │ Reporting API   │   │
│  │                 │  │                 │  │                 │   │
│  │ JDBC Driver     │  │ JDBC Driver     │  │ JDBC Driver     │   │
│  │ clickhouse-jdbc │  │ clickhouse-jdbc │  │ clickhouse-jdbc │   │
│  │ v0.4.6+         │  │ v0.4.6+         │  │ v0.4.6+         │   │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘   │
│           │                     │                     │            │
│           │  Connection Pool    │  Connection Pool    │            │
│           │  (HikariCP)         │  (HikariCP)         │            │
│           │                     │                     │            │
└───────────┼─────────────────────┼─────────────────────┼────────────┘
            │                     │                     │
            └─────────────────────┼─────────────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  Internal NLB             │
                    │  DNS: clickhouse.internal │
                    │  Port: 8123 (HTTP)        │
                    │  Port: 9000 (Native)      │
                    └─────────────┬─────────────┘
                                  │
                Load Balancing (Round Robin)
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐       ┌───────────────┐
│ ClickHouse    │         │ ClickHouse    │       │ ClickHouse    │
│ Pod 0         │         │ Pod 1         │       │ Pod 2         │
│ Shard 1       │         │ Shard 1       │       │ Shard 1       │
│ Replica 1     │         │ Replica 2     │       │ Replica 3     │
│               │         │               │       │               │
│ Port 8123 ◄───┼─────────┼───────────────┼───────┤               │
│ Port 9000     │         │               │       │               │
└───────────────┘         └───────────────┘       └───────────────┘
```

### JDBC Connection String Examples

**Option 1: HTTP Interface (Recommended for Most Cases)**
```java
// Using HTTP interface (port 8123)
String url = "jdbc:clickhouse://clickhouse.internal.yourcompany.com:8123/production_db";

Properties properties = new Properties();
properties.setProperty("user", "app_user");
properties.setProperty("password", "secure_password");
properties.setProperty("ssl", "true");
properties.setProperty("sslmode", "strict");
properties.setProperty("socket_timeout", "300000");
properties.setProperty("connect_timeout", "10000");

// With connection pooling (HikariCP recommended)
HikariConfig config = new HikariConfig();
config.setJdbcUrl(url);
config.setUsername("app_user");
config.setPassword("secure_password");
config.setMaximumPoolSize(20);
config.setMinimumIdle(5);
config.setConnectionTimeout(10000);
config.setIdleTimeout(600000);
config.setMaxLifetime(1800000);

HikariDataSource dataSource = new HikariDataSource(config);
```

**Option 2: Native Protocol (Better Performance)**
```java
// Using native protocol (port 9000)
String url = "jdbc:ch://clickhouse.internal.yourcompany.com:9000/production_db";

Properties properties = new Properties();
properties.setProperty("user", "app_user");
properties.setProperty("password", "secure_password");
properties.setProperty("ssl", "true");
properties.setProperty("compress", "true"); // Enable compression
properties.setProperty("max_execution_time", "300"); // 5 minutes
```

### Connection Pooling Best Practices

**For High-Traffic APIs:**
```java
// HikariCP Configuration
config.setMaximumPoolSize(50);        // Max connections
config.setMinimumIdle(10);            // Min idle connections
config.setConnectionTimeout(10000);   // 10 seconds
config.setIdleTimeout(600000);        // 10 minutes
config.setMaxLifetime(1800000);       // 30 minutes
config.setLeakDetectionThreshold(60000); // 1 minute

// Connection pool monitoring
config.setMetricRegistry(metricRegistry);
config.setHealthCheckRegistry(healthCheckRegistry);
```

**For Batch Processing:**
```java
// Fewer connections, longer timeout
config.setMaximumPoolSize(10);
config.setConnectionTimeout(30000);   // 30 seconds
config.setIdleTimeout(1800000);       // 30 minutes
```

### Load Balancing Strategies

**1. NLB Round-Robin (Default)**
- Distributes connections evenly across all pods
- No session affinity
- Automatic health checks
- Works for both HTTP and Native protocols

**2. Client-Side Load Balancing**
```java
// Multiple endpoints in JDBC URL
String url = "jdbc:clickhouse://clickhouse-0.internal:8123," +
             "clickhouse-1.internal:8123," +
             "clickhouse-2.internal:8123/production_db";
```

**3. Read Replica Routing**
```java
// Separate endpoints for writes and reads
String writeUrl = "jdbc:clickhouse://clickhouse-write.internal:8123/production_db";
String readUrl = "jdbc:clickhouse://clickhouse-read.internal:8123/production_db";
```

---

## Responsibility Matrix

### Your Team's Responsibilities

| Area | Specific Tasks |
|------|----------------|
| **AWS Account** | • Provide AWS account for deployment<br>• Manage AWS Organizations and SCPs<br>• Pay for all AWS resources<br>• Manage budget and cost allocation |
| **VPC & Networking** | • Create VPC (10.0.0.0/16 or similar)<br>• Create private subnets across 3 AZs<br>• **NO public subnets, NAT Gateway, or IGW**<br>• Create all VPC endpoints (S3, ECR, EKS, etc.)<br>• Configure route tables<br>• Set up Direct Connect or VPN for access<br>• Manage DNS (Route53 private hosted zones) |
| **Security Groups** | • Create security group for EKS worker nodes<br>• Create security group for ClickHouse pods<br>• Create security group for NLB<br>• Create security group for VPC endpoints<br>• Define ingress/egress rules<br>• Provide security group IDs to ClickHouse team |
| **IAM Roles & Policies** | • Create EKS node IAM role<br>• Create IRSA roles for ClickHouse pods<br>• Create S3 access policies<br>• Create CloudWatch logging policies<br>• Create cross-account trust role for ClickHouse<br>• Manage IAM permissions |
| **KMS Encryption** | • Create KMS keys for:<br>&nbsp;&nbsp;- EBS volume encryption<br>&nbsp;&nbsp;- S3 bucket encryption<br>&nbsp;&nbsp;- EKS secrets encryption<br>• Configure key policies<br>• Implement key rotation |
| **S3 Buckets** | • Create S3 bucket for ClickHouse backups<br>• Create S3 bucket for logs<br>• Configure bucket encryption (SSE-KMS)<br>• Set lifecycle policies<br>• Configure bucket policies for IRSA access |
| **CloudWatch** | • Create log groups for ClickHouse logs<br>• Create log groups for EKS control plane<br>• Create CloudWatch alarms<br>• Set up SNS topics for alerts<br>• Configure log retention policies |
| **Network Load Balancer** | • Provide subnet IDs where NLB should be created<br>• Review NLB configuration created by ClickHouse<br>• Update DNS records to point to NLB<br>• Monitor NLB metrics |
| **Application Integration** | • Develop application code with JDBC drivers<br>• Configure connection pooling<br>• Implement retry logic<br>• Handle failover scenarios<br>• Query optimization in application layer |
| **Monitoring & Alerting** | • Set up CloudWatch dashboards<br>• Configure PagerDuty/Slack integrations<br>• Create runbooks for your team<br>• Monitor costs and usage<br>• Track SLA metrics |
| **Access Control** | • Manage kubectl access via IAM/VPN<br>• Provide access to ClickHouse team (cross-account role)<br>• Manage developer access<br>• Implement MFA policies<br>• Audit access logs |
| **Compliance & Audit** | • Ensure CloudTrail is enabled<br>• Enable VPC Flow Logs<br>• Maintain compliance documentation<br>• Conduct security audits<br>• Manage data retention policies |

### ClickHouse Team's Responsibilities

| Area | Specific Tasks |
|------|----------------|
| **EKS Cluster** | • Create EKS cluster in your VPC<br>• Configure EKS control plane<br>• Manage EKS version upgrades<br>• Configure cluster autoscaling<br>• Install EKS add-ons (VPC CNI, CoreDNS, EBS CSI) |
| **Worker Nodes** | • Create and manage node groups<br>• Size worker nodes appropriately<br>• Configure node auto-scaling<br>• Apply security patches to nodes<br>• Handle node failures and replacements |
| **ClickHouse Deployment** | • Install ClickHouse Operator<br>• Deploy ClickHouse cluster<br>• Configure sharding and replication<br>• Set up ClickHouse Keeper<br>• Manage ClickHouse version upgrades |
| **Storage Management** | • Create PersistentVolumeClaims<br>• Configure storage classes<br>• Manage volume expansion<br>• Optimize data placement<br>• Monitor disk usage |
| **Database Configuration** | • Optimize ClickHouse settings<br>• Configure memory limits<br>• Set up query quotas<br>• Configure merge policies<br>• Tune compression settings |
| **Backup & Recovery** | • Configure automated backups to S3<br>• Implement backup retention<br>• Test restore procedures<br>• Provide backup SLAs<br>• Handle disaster recovery |
| **Performance Tuning** | • Optimize query performance<br>• Tune table engines<br>• Configure caching<br>• Analyze slow queries<br>• Provide performance recommendations |
| **Monitoring** | • Deploy Prometheus/Grafana<br>• Create ClickHouse-specific dashboards<br>• Set up database alerts<br>• Monitor replication lag<br>• Track query performance |
| **Support** | • 24/7 technical support (based on SLA)<br>• Incident response<br>• Root cause analysis<br>• Performance troubleshooting<br>• Best practice guidance |

### Shared Responsibilities

| Area | Your Team | ClickHouse Team |
|------|-----------|-----------------|
| **Capacity Planning** | Provide growth projections and budget | Analyze usage patterns and recommend sizing |
| **Security** | Network security, IAM, encryption keys | Database security, user management, query security |
| **Monitoring** | Infrastructure metrics (CPU, network, disk) | Database metrics (queries, replication, performance) |
| **Incident Response** | Provide access during incidents<br>Network troubleshooting | Database troubleshooting<br>Root cause analysis |
| **Performance** | Monitor application query patterns | Optimize database configuration and queries |
| **Cost Optimization** | Review and approve infrastructure changes | Recommend right-sizing and efficiency improvements |

---

## Your Team's Infrastructure Setup

### Terraform Resources You Need to Create

```hcl
# Directory structure
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── modules/
    ├── vpc/              # VPC with private subnets only
    ├── security/         # Security groups and KMS keys
    ├── iam/              # IAM roles and policies
    ├── storage/          # S3 buckets
    ├── monitoring/       # CloudWatch configuration
    └── dns/              # Route53 private zones
```

### 1. VPC and Networking

**What to create:**
- VPC (e.g., 10.0.0.0/16)
- 3 private subnets (one per AZ)
- Route tables for private subnets
- VPC endpoints for:
  - S3 (Gateway - Free)
  - ECR API and DKR
  - EC2, EKS, ELB
  - CloudWatch Logs
  - STS

**Outputs to provide ClickHouse team:**
- VPC ID
- Private subnet IDs (all 3)
- VPC CIDR block
- Availability zones used

### 2. Security Groups

**Create these security groups:**

**a) EKS Worker Nodes Security Group**
```
Ingress:
- Port 443 from EKS control plane (for kubelet)
- Port 1025-65535 from EKS control plane (for node ports)
- All traffic from itself (node-to-node communication)

Egress:
- All traffic to 0.0.0.0/0 (for pulling images, accessing AWS services)
```

**b) ClickHouse Pods Security Group**
```
Ingress:
- Port 9000 (native protocol) from application security groups
- Port 8123 (HTTP interface) from application security groups
- Port 9009 (interserver) from itself
- Port 9234 (ClickHouse Keeper) from itself

Egress:
- Port 443 to VPC CIDR (for S3, ECR via VPC endpoints)
- Port 9009 to itself (interserver communication)
- Port 9181, 9234 to itself (Keeper communication)
```

**c) NLB Security Group**
```
Ingress:
- Port 8123 from application subnets
- Port 9000 from application subnets

Egress:
- Port 8123 to ClickHouse pods security group
- Port 9000 to ClickHouse pods security group
```

**Outputs to provide:**
- Worker node security group ID
- ClickHouse pods security group ID
- NLB security group ID

### 3. IAM Roles

**a) EKS Node IAM Role**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```
Attach policies:
- AmazonEKSWorkerNodePolicy
- AmazonEKS_CNI_Policy
- AmazonEC2ContainerRegistryReadOnly

**b) IRSA Role for ClickHouse Pods**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/XXXXX"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/XXXXX:sub": "system:serviceaccount:clickhouse:clickhouse-sa"
        }
      }
    }
  ]
}
```

Permissions needed:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::clickhouse-backups-*",
        "arn:aws:s3:::clickhouse-backups-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/clickhouse/*"
    }
  ]
}
```

**c) Cross-Account Role for ClickHouse Team**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::CLICKHOUSE_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "unique-external-id-provided-by-clickhouse"
        }
      }
    }
  ]
}
```

Permissions to grant (ask ClickHouse for exact list):
- EKS cluster creation and management
- EC2 instance management (for worker nodes)
- EBS volume creation
- Load balancer creation
- CloudWatch read access

**Outputs to provide:**
- EKS node role ARN
- IRSA role ARN
- Cross-account role ARN

### 4. KMS Keys

**Create 3 KMS keys:**

**a) EBS Encryption Key**
```hcl
resource "aws_kms_key" "ebs" {
  description             = "KMS key for EBS volume encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = {
    Name = "clickhouse-ebs-key"
  }
}
```

**b) S3 Encryption Key**
```hcl
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = {
    Name = "clickhouse-s3-key"
  }
}
```

**c) EKS Secrets Encryption Key**
```hcl
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = {
    Name = "clickhouse-eks-secrets-key"
  }
}
```

**Key policies must allow:**
- Your AWS account root user (for administration)
- EKS service principal (for secrets encryption)
- ClickHouse cross-account role (for EBS/S3 access)

**Outputs to provide:**
- EBS KMS key ARN
- S3 KMS key ARN
- EKS KMS key ARN

### 5. S3 Buckets

**Create 2 S3 buckets:**

**a) Backups Bucket**
```hcl
resource "aws_s3_bucket" "clickhouse_backups" {
  bucket = "clickhouse-backups-prod-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "ClickHouse Backups"
    Environment = "Production"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id
  
  rule {
    id     = "delete-old-backups"
    status = "Enabled"
    
    expiration {
      days = 90
    }
  }
}
```

**b) Logs Bucket**
```hcl
resource "aws_s3_bucket" "clickhouse_logs" {
  bucket = "clickhouse-logs-prod-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "ClickHouse Logs"
    Environment = "Production"
  }
}
```

**Bucket policies** - Must allow ClickHouse IRSA role access

**Outputs to provide:**
- Backup bucket name
- Logs bucket name
- Bucket ARNs

### 6. CloudWatch

**Create log groups:**
```hcl
resource "aws_cloudwatch_log_group" "clickhouse_query_logs" {
  name              = "/aws/clickhouse/query-logs"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.s3.arn
}

resource "aws_cloudwatch_log_group" "clickhouse_error_logs" {
  name              = "/aws/clickhouse/error-logs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.s3.arn
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/clickhouse-cluster/cluster"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.s3.arn
}
```

**Outputs to provide:**
- Log group names
- Log group ARNs

### 7. Route53 Private Hosted Zone

```hcl
resource "aws_route53_zone" "internal" {
  name = "internal.yourcompany.com"
  
  vpc {
    vpc_id = aws_vpc.main.id
  }
  
  tags = {
    Name = "Internal DNS"
  }
}

# Record for ClickHouse (will be updated after NLB creation)
resource "aws_route53_record" "clickhouse" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "clickhouse.internal.yourcompany.com"
  type    = "A"
  
  # This will be updated after ClickHouse team creates NLB
  # Initial placeholder
  ttl     = 300
  records = ["10.0.0.100"]
}
```

**Outputs to provide:**
- Hosted zone ID
- Domain name

---

## Questions to Ask ClickHouse Team

### Critical Questions (Must Ask Before Starting)

#### 1. EKS Cluster Creation
- [ ] **Q:** Will you create the EKS cluster in our AWS account using our cross-account role?
- [ ] **Q:** What specific IAM permissions do you need in the cross-account role?
- [ ] **Q:** Do you need permissions to create VPCs or just use our existing VPC?
- [ ] **Q:** What EKS version will you deploy? (We need 1.28+)
- [ ] **Q:** Will the EKS control plane be private-only or can it have public endpoint?
- [ ] **Q:** How do you handle EKS cluster upgrades? What is the process?
- [ ] **Q:** Do you need access to our AWS console or just API access via IAM role?

#### 2. VPC and Networking
- [ ] **Q:** Can you work with a fully private VPC (no public subnets, no IGW, no NAT)?
- [ ] **Q:** Which VPC endpoints must we create? (Please provide complete list)
- [ ] **Q:** What are the IP address requirements for the EKS cluster?
  - How many IPs do you need per subnet?
  - What subnet size do you recommend? (/24, /23, /22?)
- [ ] **Q:** Do you require specific subnet tags for auto-discovery?
- [ ] **Q:** Will you create the Network Load Balancer or should we?
- [ ] **Q:** Should the NLB be internal-only or internet-facing? (We require internal-only)
- [ ] **Q:** What DNS record should point to the NLB?

#### 3. Security Groups
- [ ] **Q:** Will you create security groups or should we provide them?
- [ ] **Q:** If we create them, what exact rules do you need for:
  - EKS worker nodes
  - ClickHouse pods
  - Load balancer
  - VPC endpoints
- [ ] **Q:** Do you require any specific egress rules?
- [ ] **Q:** How do you handle security group updates?

#### 4. Storage
- [ ] **Q:** Will you create the S3 buckets or should we?
- [ ] **Q:** What S3 bucket permissions does ClickHouse need? (GetObject, PutObject, DeleteObject?)
- [ ] **Q:** Do you support customer-managed KMS keys for S3 encryption?
- [ ] **Q:** What is the default EBS volume type? (gp3, io2?)
- [ ] **Q:** Can we specify custom storage classes?
- [ ] **Q:** How do you handle EBS volume expansion?
- [ ] **Q:** What is the backup strategy? How often? Retention period?
- [ ] **Q:** Where are backups stored? (S3 bucket we provide?)

#### 5. IAM and Authentication
- [ ] **Q:** What IAM policies must we attach to the IRSA role for ClickHouse pods?
- [ ] **Q:** Do you use IAM Roles for Service Accounts (IRSA)?
- [ ] **Q:** What permissions does your cross-account role need? (Please provide exact policy)
- [ ] **Q:** How do you manage ClickHouse database users and passwords?
- [ ] **Q:** Can we integrate with our existing identity provider (LDAP, SAML, OIDC)?
- [ ] **Q:** How are credentials rotated?

#### 6. Worker Nodes
- [ ] **Q:** What EC2 instance types will you use for worker nodes?
- [ ] **Q:** How many worker nodes in the initial deployment?
- [ ] **Q:** Do you use managed node groups or self-managed?
- [ ] **Q:** Do you support spot instances for cost savings?
- [ ] **Q:** What is the node auto-scaling policy?
- [ ] **Q:** How do you handle node maintenance and patches?

#### 7. ClickHouse Configuration
- [ ] **Q:** What is the default cluster topology? (shards, replicas)
- [ ] **Q:** Can we customize the number of shards and replicas?
- [ ] **Q:** What ClickHouse version will be deployed?
- [ ] **Q:** How do you handle ClickHouse version upgrades?
- [ ] **Q:** What is the upgrade frequency and process?
- [ ] **Q:** Do you support custom ClickHouse configurations?

#### 8. Monitoring and Logging
- [ ] **Q:** What metrics do you expose? (Prometheus, CloudWatch?)
- [ ] **Q:** Do you provide Grafana dashboards?
- [ ] **Q:** What logs are sent to CloudWatch?
- [ ] **Q:** Can we access ClickHouse system tables for monitoring?
- [ ] **Q:** What are the key metrics to monitor?
- [ ] **Q:** Do you provide alerting rules or should we create them?

#### 9. Connectivity and Access
- [ ] **Q:** How will our applications connect to ClickHouse?
  - Through NLB only?
  - Direct pod access?
  - Service mesh?
- [ ] **Q:** What ports are exposed? (8123 for HTTP, 9000 for native?)
- [ ] **Q:** Do you support TLS/SSL encryption for client connections?
- [ ] **Q:** What JDBC driver version is recommended?
- [ ] **Q:** Are there connection pooling recommendations?
- [ ] **Q:** How do you handle connection limits?

#### 10. JDBC and Application Integration
- [ ] **Q:** What is the recommended JDBC driver version?
- [ ] **Q:** What is the JDBC connection string format?
- [ ] **Q:** How many concurrent connections can the cluster handle?
- [ ] **Q:** What are the recommended connection pool settings?
  - Min/Max pool size?
  - Connection timeout?
  - Idle timeout?
- [ ] **Q:** Do you support read/write splitting (separate endpoints)?
- [ ] **Q:** How should we handle connection failover?
- [ ] **Q:** Are there query timeout recommendations?
- [ ] **Q:** Can we use HTTP interface (port 8123) or must we use native (port 9000)?

#### 11. Performance and Sizing
- [ ] **Q:** Based on our requirements (X TB data, Y QPS), what cluster size do you recommend?
- [ ] **Q:** What storage class (gp3 vs io2) do you recommend for our workload?
- [ ] **Q:** How do you size PersistentVolumes?
- [ ] **Q:** What is the expected query latency? (P50, P95, P99)
- [ ] **Q:** What is the maximum throughput we can expect?
- [ ] **Q:** How do you handle performance tuning?

#### 12. High Availability and Disaster Recovery
- [ ] **Q:** What is the uptime SLA?
- [ ] **Q:** How do you handle pod failures?
- [ ] **Q:** How do you handle node failures?
- [ ] **Q:** How do you handle AZ failures?
- [ ] **Q:** What is the RTO (Recovery Time Objective)?
- [ ] **Q:** What is the RPO (Recovery Point Objective)?
- [ ] **Q:** Do you support multi-region deployment?
- [ ] **Q:** How do you test disaster recovery?

#### 13. Backup and Recovery
- [ ] **Q:** How often are backups taken?
- [ ] **Q:** How long are backups retained?
- [ ] **Q:** Can we trigger manual backups?
- [ ] **Q:** How long does a restore take?
- [ ] **Q:** Can we do point-in-time recovery?
- [ ] **Q:** Are backups tested regularly?
- [ ] **Q:** What is the backup verification process?

#### 14. Security and Compliance
- [ ] **Q:** Do you support encryption at rest? (EBS, S3)
- [ ] **Q:** Do you support encryption in transit? (TLS 1.3)
- [ ] **Q:** Are you SOC 2 Type II certified?
- [ ] **Q:** Are you PCI-DSS compliant?
- [ ] **Q:** Can you provide a security questionnaire?
- [ ] **Q:** How do you handle security patching?
- [ ] **Q:** What is the patch management SLA?
- [ ] **Q:** Do you support customer-managed KMS keys?

#### 15. Support and SLA
- [ ] **Q:** What support tiers are available?
- [ ] **Q:** What are the support response times for each tier?
- [ ] **Q:** Is support 24/7?
- [ ] **Q:** How do we escalate critical issues?
- [ ] **Q:** Do you provide a dedicated Slack channel?
- [ ] **Q:** Who is our assigned customer success manager?
- [ ] **Q:** What is included in the service fee?

#### 16. Costs
- [ ] **Q:** What is the monthly service fee?
- [ ] **Q:** Is the service fee based on usage or fixed?
- [ ] **Q:** Do we pay for AWS infrastructure costs directly?
- [ ] **Q:** Are there any hidden costs or surprise fees?
- [ ] **Q:** What happens if we exceed our agreed capacity?
- [ ] **Q:** Is there a cost for support incidents?
- [ ] **Q:** What is the minimum contract term?

#### 17. Data Migration
- [ ] **Q:** Do you provide data migration assistance?
- [ ] **Q:** What tools do you recommend for data import?
- [ ] **Q:** Can you help with schema design?
- [ ] **Q:** What is the migration process?
- [ ] **Q:** How do we validate data after migration?

#### 18. Operational Procedures
- [ ] **Q:** How do we request cluster scaling?
- [ ] **Q:** What is the process for configuration changes?
- [ ] **Q:** How do we get kubectl access to the cluster?
- [ ] **Q:** Can we access the ClickHouse CLI directly?
- [ ] **Q:** What operational tasks can we perform vs what requires your team?
- [ ] **Q:** How do we report issues or create support tickets?

#### 19. Timeline
- [ ] **Q:** How long does initial deployment take?
- [ ] **Q:** What is the timeline from contract signing to production?
- [ ] **Q:** Are there any dependencies that could delay deployment?
- [ ] **Q:** When can we start testing?

#### 20. Exit Strategy
- [ ] **Q:** If we need to migrate off ClickHouse Cloud, how do we do it?
- [ ] **Q:** Can we export all our data?
- [ ] **Q:** What is the data export format?
- [ ] **Q:** Is there a contract termination penalty?
- [ ] **Q:** How much notice do we need to provide?

---

## Implementation Checklist

### Phase 1: Pre-Deployment (Week 1-2)

#### Your Team Tasks
- [ ] Schedule kickoff meeting with ClickHouse team
- [ ] Get answers to all critical questions above
- [ ] Review and sign contract with ClickHouse
- [ ] Obtain ClickHouse AWS account ID for cross-account access
- [ ] Obtain external ID for cross-account role
- [ ] Create project in Jira/task management system
- [ ] Assign team members to project

#### Infrastructure Preparation
- [ ] Review current AWS account structure
- [ ] Verify AWS service limits (EC2, EBS, VPC)
- [ ] Request limit increases if needed
- [ ] Confirm Direct Connect or VPN is operational
- [ ] Set up Terraform state backend (S3 + DynamoDB)

### Phase 2: Infrastructure Deployment (Week 2-3)

#### VPC and Networking
- [ ] Deploy VPC with Terraform
- [ ] Create private subnets across 3 AZs
- [ ] Create VPC endpoints (S3, ECR, EKS, CloudWatch, etc.)
- [ ] Verify VPC endpoint connectivity
- [ ] Configure route tables
- [ ] Enable VPC Flow Logs

#### Security
- [ ] Create KMS keys (EBS, S3, EKS secrets)
- [ ] Configure KMS key policies
- [ ] Create security groups (worker nodes, pods, NLB, VPC endpoints)
- [ ] Review security group rules with security team
- [ ] Enable CloudTrail if not already enabled

#### IAM
- [ ] Create EKS node IAM role
- [ ] Create IRSA role for ClickHouse pods
- [ ] Create cross-account role for ClickHouse team
- [ ] Configure role trust relationships
- [ ] Attach necessary policies
- [ ] Test role assumption from ClickHouse account

#### Storage
- [ ] Create S3 bucket for backups
- [ ] Create S3 bucket for logs
- [ ] Enable S3 encryption (SSE-KMS)
- [ ] Configure S3 lifecycle policies
- [ ] Set up S3 bucket policies
- [ ] Enable S3 versioning for backups

#### Monitoring
- [ ] Create CloudWatch log groups
- [ ] Set up CloudWatch alarms
- [ ] Create SNS topics for alerts
- [ ] Configure PagerDuty/Slack integration
- [ ] Set up CloudWatch dashboard

#### DNS
- [ ] Create Route53 private hosted zone
- [ ] Create placeholder DNS record for ClickHouse

#### Handoff to ClickHouse
- [ ] Provide VPC ID
- [ ] Provide private subnet IDs
- [ ] Provide security group IDs
- [ ] Provide IAM role ARNs
- [ ] Provide KMS key ARNs
- [ ] Provide S3 bucket names
- [ ] Provide CloudWatch log group names
- [ ] Provide Route53 hosted zone ID

### Phase 3: ClickHouse Deployment (Week 3-4) - ClickHouse Team

#### Your Monitoring Tasks
- [ ] Monitor cross-account role usage in CloudTrail
- [ ] Review security group changes
- [ ] Monitor EKS cluster creation
- [ ] Monitor EC2 instance launches
- [ ] Monitor EBS volume creation
- [ ] Monitor costs in Cost Explorer

#### Validation Tasks
- [ ] Verify EKS cluster is created in private subnets
- [ ] Verify no public IPs are assigned
- [ ] Verify NLB is internal-only
- [ ] Verify all traffic uses VPC endpoints
- [ ] Test kubectl access via VPN

### Phase 4: Testing (Week 4-5)

#### Connectivity Testing
- [ ] Test JDBC connection from application subnet
- [ ] Test HTTP interface (port 8123)
- [ ] Test native protocol (port 9000)
- [ ] Test TLS/SSL encryption
- [ ] Test connection pooling
- [ ] Test connection failover
- [ ] Verify DNS resolution

#### Application Integration
- [ ] Deploy test application
- [ ] Configure JDBC connection pool
- [ ] Test INSERT statements
- [ ] Test SELECT queries
- [ ] Test batch operations
- [ ] Measure query latency
- [ ] Stress test with expected load

#### Security Testing
- [ ] Verify encryption at rest (EBS, S3)
- [ ] Verify encryption in transit (TLS)
- [ ] Test IAM authentication
- [ ] Verify security group rules
- [ ] Test that public access is blocked
- [ ] Review CloudTrail logs
- [ ] Conduct penetration test (if required)

#### Backup and Recovery
- [ ] Trigger manual backup
- [ ] Verify backup in S3
- [ ] Test restore procedure
- [ ] Measure restore time
- [ ] Verify data integrity after restore

### Phase 5: Production Readiness (Week 5-6)

#### Documentation
- [ ] Document JDBC connection strings
- [ ] Document connection pool configuration
- [ ] Create application integration guide
- [ ] Create troubleshooting runbook
- [ ] Document emergency procedures
- [ ] Create architecture diagrams

#### Training
- [ ] Train development team on JDBC best practices
- [ ] Train operations team on monitoring
- [ ] Train security team on compliance requirements
- [ ] Conduct tabletop exercise for incident response

#### Monitoring
- [ ] Set up application-level monitoring
- [ ] Configure query performance tracking
- [ ] Set up cost monitoring and alerts
- [ ] Create weekly cost reports

#### Security
- [ ] Complete security review
- [ ] Update security documentation
- [ ] Confirm compliance requirements met
- [ ] Schedule security audit

### Phase 6: Production Launch (Week 6-7)

#### Pre-Launch
- [ ] Final security review
- [ ] Load testing completed
- [ ] Backup/restore tested
- [ ] Monitoring verified
- [ ] On-call rotation established
- [ ] Runbooks reviewed
- [ ] Communication plan ready

#### Launch
- [ ] Deploy production applications
- [ ] Cutover DNS to production
- [ ] Monitor closely for 48 hours
- [ ] Validate queries are successful
- [ ] Check error rates
- [ ] Monitor costs

#### Post-Launch
- [ ] Conduct post-launch review
- [ ] Document lessons learned
- [ ] Optimize based on real usage
- [ ] Update documentation
- [ ] Schedule regular reviews

---

## Summary

**Your team is responsible for:**
- AWS account and billing
- VPC and networking (100% private)
- Security groups
- IAM roles (including cross-account role)
- KMS keys
- S3 buckets
- CloudWatch logging and alarms
- Route53 DNS
- Application integration (JDBC)
- Monitoring and alerting
- Cost management

**ClickHouse team is responsible for:**
- EKS cluster creation
- Worker nodes management
- ClickHouse deployment
- Database configuration
- Performance tuning
- Backups
- 24/7 support
- Software updates

**Key integration points:**
- ClickHouse team uses cross-account IAM role to manage EKS in your account
- Applications connect via JDBC through internal NLB
- Backups stored in your S3 buckets
- Logs sent to your CloudWatch
- All resources in your AWS account

**Next Steps:**
1. Review this document with your team
2. Schedule meeting with ClickHouse to ask critical questions
3. Begin Terraform development for your infrastructure
4. Prepare VPN/Direct Connect access
5. Set up monitoring and alerting framework

---

**Document Version:** 2.0  
**Last Updated:** December 2024  
**Status:** Ready for Review
