# PowerPoint Presentation - Slide-by-Slide Content

## Instructions
Use this content to create your PowerPoint presentation. Each slide is numbered and includes:
- Title
- Content/Bullet points
- Visual suggestions

Recommended design: Professional fintech theme with navy blue (#1a365d) and gold (#d4af37) accents.

---

## SLIDE 1: Title Slide
**Title:** ClickHouse BYOC on Amazon EKS  
**Subtitle:** Private Infrastructure Implementation for Fintech  
**Footer:** Platform Engineering | December 2024

**Design:** Dark navy background, gold accent line on left side

---

## SLIDE 2: Project Overview
**Title:** What Are We Building?

**Content:**
• **Objective**: Deploy ClickHouse database on Amazon EKS in our AWS account
• **Architecture**: 100% private network - no public internet access
• **Deployment Model**: ClickHouse team creates and manages EKS cluster
• **Our Role**: Provide VPC, security, and supporting AWS infrastructure

**Key Facts:**
- Timeline: 7-8 weeks from planning to production
- Cost: $6,500-10,000/month (infrastructure + service)
- Security: Fintech-grade with full encryption and compliance

---

## SLIDE 3: Architecture Diagram
**Title:** Network Architecture - Fully Private

**Visual:** Include this diagram (create in PowerPoint using shapes):

```
┌─────────────────────────────────────────┐
│         YOUR AWS ACCOUNT                │
│                                         │
│  ┌────────────────────────────────────┐│
│  │  VPC (Private Subnets Only)       ││
│  │                                    ││
│  │  ┌─────────────┐ ┌─────────────┐ ││
│  │  │   API 1     │ │   API 2     │ ││
│  │  │ (JDBC)      │ │ (JDBC)      │ ││
│  │  └──────┬──────┘ └──────┬──────┘ ││
│  │         │                │        ││
│  │         └────────┬───────┘        ││
│  │                  │                ││
│  │         ┌────────▼────────┐       ││
│  │         │  Internal NLB   │       ││
│  │         └────────┬────────┘       ││
│  │                  │                ││
│  │    ┌─────────────┼──────────┐    ││
│  │    │  EKS Cluster (Private) │    ││
│  │    │  ClickHouse Pods       │    ││
│  │    │  (6 pods across 3 AZs) │    ││
│  │    └────────────────────────┘    ││
│  │                                    ││
│  │  • VPC Endpoints (S3, ECR, etc.)  ││
│  │  • No Internet Gateway            ││
│  │  • No NAT Gateway                 ││
│  └────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

**Key Points:**
- All traffic stays within private network
- Access via VPN/Direct Connect only
- ClickHouse team manages EKS via cross-account IAM role

---

## SLIDE 4: JDBC Connection Architecture
**Title:** How Applications Connect

**Visual:** Flow diagram

```
Multiple APIs (Java/Spring Boot)
         ↓
    JDBC Driver
 (clickhouse-jdbc)
         ↓
  Connection Pool
   (HikariCP)
         ↓
  Internal NLB
  (Port 8123/9000)
         ↓
  ClickHouse Pods
(Load Balanced)
```

**Connection String Example:**
```
jdbc:clickhouse://clickhouse.internal:8123/production_db
```

**Best Practices:**
• Use connection pooling (10-50 connections per API)
• Enable compression for better performance
• Set appropriate timeouts (10-30 seconds)
• Use HTTP interface (8123) for most cases

---

## SLIDE 5: Responsibility Matrix
**Title:** Who Does What?

**Two-Column Layout:**

**YOUR TEAM**
✓ VPC and networking
✓ Security groups
✓ IAM roles and policies
✓ KMS encryption keys
✓ S3 buckets
✓ CloudWatch logs/alarms
✓ VPN/Direct Connect
✓ Application integration (JDBC)
✓ Cost management

**CLICKHOUSE TEAM**
✓ Create EKS cluster
✓ Manage worker nodes
✓ Deploy ClickHouse
✓ Database configuration
✓ Performance tuning
✓ Backups and recovery
✓ Monitoring dashboards
✓ 24/7 support
✓ Software updates

---

## SLIDE 6: Shared Responsibilities
**Title:** Collaboration Areas

| Activity | Your Team | ClickHouse Team |
|----------|-----------|-----------------|
| **Capacity Planning** | Provide growth forecasts | Analyze and recommend sizing |
| **Security** | Network & IAM security | Database security |
| **Monitoring** | Infrastructure metrics | Database metrics |
| **Incidents** | Network troubleshooting | Database troubleshooting |
| **Performance** | Query patterns from apps | Database tuning |

**Key Principle:** Clear communication and well-defined handoff points

---

## SLIDE 7: Your Team's Infrastructure (Terraform)
**Title:** What We Need to Build

**Resources to Create:**

**1. Network (Private Only)**
• VPC with private subnets (3 AZs)
• VPC endpoints (S3, ECR, EKS, CloudWatch)
• Route tables
• VPC Flow Logs

**2. Security**
• 3 Security groups (EKS nodes, ClickHouse pods, NLB)
• 3 KMS keys (EBS, S3, EKS secrets)

**3. IAM**
• EKS node role
• IRSA role for ClickHouse pods
• Cross-account role for ClickHouse team

**4. Storage**
• S3 bucket for backups
• S3 bucket for logs
• CloudWatch log groups

**5. DNS**
• Route53 private hosted zone
• DNS record for ClickHouse

✅ **All defined in Terraform - Infrastructure as Code**

---

## SLIDE 8: Critical Questions for ClickHouse
**Title:** Questions We Must Ask

**EKS & Infrastructure (Top Priority)**
1. What exact IAM permissions do you need in the cross-account role?
2. Can you work with a fully private VPC (no public subnets)?
3. Which VPC endpoints are required?
4. Will the EKS control plane be private-only?
5. What are the subnet size requirements?

**Storage & Performance**
6. What storage class (gp3 vs io2) do you recommend?
7. How do you size PersistentVolumes?
8. What backup frequency and retention?
9. What are expected query latencies?

**Security & Compliance**
10. Do you support customer-managed KMS keys?
11. Are you SOC 2 Type II and PCI-DSS certified?
12. What is the security patching SLA?

**JDBC & Integration**
13. What JDBC driver version is recommended?
14. What connection pool settings?
15. How many concurrent connections supported?

**See full list of 20+ questions in documentation**

---

## SLIDE 9: Data Plane Deep Dive
**Title:** How ClickHouse Works on EKS

**StatefulSet Architecture:**

```
┌──────────────────────────────────┐
│  Kubernetes StatefulSet          │
│                                  │
│  Pod: clickhouse-0 ──► PV (1TB)  │
│  Pod: clickhouse-1 ──► PV (1TB)  │
│  Pod: clickhouse-2 ──► PV (1TB)  │
│  Pod: clickhouse-3 ──► PV (1TB)  │
│  Pod: clickhouse-4 ──► PV (1TB)  │
│  Pod: clickhouse-5 ──► PV (1TB)  │
│                                  │
│  (2 shards × 3 replicas = 6 pods)│
└──────────────────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│                    YOUR DATA: 10 TB Total                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Split horizontally
                              │ (Sharding)
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
    ┌─────────────────┐            ┌─────────────────┐
    │   SHARD 1       │            │   SHARD 2       │
    │   5 TB data     │            │   5 TB data     │
    │   (Rows 1-50M)  │            │   (Rows 50M+)   │
    └─────────────────┘            └─────────────────┘
              │                               │
              │ Copy vertically               │ Copy vertically
              │ (Replication)                 │ (Replication)
              │                               │
    ┌─────────┼─────────┐         ┌─────────┼─────────┐
    │         │         │         │         │         │
    ▼         ▼         ▼         ▼         ▼         ▼
┌───────┐┌───────┐┌───────┐  ┌───────┐┌───────┐┌───────┐
│Pod 0  ││Pod 1  ││Pod 2  │  │Pod 3  ││Pod 4  ││Pod 5  │
│5TB    ││5TB    ││5TB    │  │5TB    ││5TB    ││5TB    │
│AZ-A   ││AZ-B   ││AZ-C   │  │AZ-A   ││AZ-B   ││AZ-C   │
│       ││       ││       │  │       ││       ││       │
│Shard 1││Shard 1││Shard 1│  │Shard 2││Shard 2││Shard 2│
│Rep 1  ││Rep 2  ││Rep 3  │  │Rep 1  ││Rep 2  ││Rep 3  │
└───────┘└───────┘└───────┘  └───────┘└───────┘└───────┘


Shard 1 (has 3 copies of the same data)
├── Replica 1 (Pod 0) - in AZ-A
├── Replica 2 (Pod 1) - in AZ-B
└── Replica 3 (Pod 2) - in AZ-C

Shard 2 (has 3 copies of DIFFERENT data)
├── Replica 1 (Pod 3) - in AZ-A
├── Replica 2 (Pod 4) - in AZ-B
└── Replica 3 (Pod 5) - in AZ-C

Total: 6 pods

```

**Why StatefulSet?**
• Stable pod identities (clickhouse-0, clickhouse-1, etc.)
• Persistent storage binding
• Ordered deployment
• Automatic pod rescheduling

**Why Persistent Volumes?**
• Store table data files
• Store metadata and schemas
• Write-ahead logs
• Query temporary files
• **Data survives pod restarts!**

---

## SLIDE 10: Storage: gp3 vs io2
**Title:** Choosing the Right Storage Class

**Comparison Table:**

| Factor | gp3 (Recommended) | io2 (High Performance) |
|--------|-------------------|------------------------|
| **IOPS** | 3,000 baseline | Up to 64,000 |
| **Throughput** | 125 MB/s | Up to 1,000 MB/s |
| **Cost (1TB)** | $80/month | $775/month |
| **Best For** | 95% of workloads | Mission-critical only |
| **QPS** | < 1,000 queries/sec | > 5,000 queries/sec |
| **Latency** | 100-500ms OK | Need < 100ms |

**Recommendation:**
✅ Start with gp3 for cost efficiency  
✅ Monitor actual IOPS usage in CloudWatch  
✅ Upgrade to io2 only if performance metrics justify the 10x cost

---

## SLIDE 11: Storage Sizing Example
**Title:** How We Calculate Storage Needs

**Example Scenario:**
- Total data: 5 TB (compressed)
- ClickHouse compression: ~7x
- Shards: 2
- Replicas per shard: 3
- Working space needed: 25% of data

**Calculation:**
```
Data per shard:  5 TB ÷ 2 = 2.5 TB
Working space:   2.5 TB × 0.25 = 625 GB
Per-shard total: 2.5 TB + 625 GB = 3.125 TB
With buffer 20%: 3.125 TB × 1.2 = 3.75 TB
Provision:       4 TB per shard

Total pods:      2 shards × 3 replicas = 6 pods
Storage/pod:     4 TB
Total storage:   6 × 4 TB = 24 TB (with replication)
```

**Why working space?**
- Merge operations
- Sort operations
- Query temporary files

---

## SLIDE 12: Implementation Timeline
**Title:** 7-Week Deployment Plan

**Gantt-style timeline:**

| Week | Phase | Your Team | ClickHouse Team |
|------|-------|-----------|-----------------|
| 1-2 | **Planning** | Complete questions<br>Deploy Terraform infra | Review requirements<br>Size cluster |
| 3 | **Handoff** | Provide VPC/IAM/S3 info | Assume cross-account role |
| 4 | **EKS Deploy** | Monitor CloudTrail<br>Verify private network | Create EKS cluster<br>Deploy ClickHouse |
| 5 | **Testing** | JDBC connectivity<br>Security validation | Performance tuning<br>Backup testing |
| 6 | **Integration** | Deploy applications<br>Load testing | Monitor and optimize |
| 7 | **Production** | Cutover traffic<br>Monitor closely | 24/7 support active |

**Critical Path:** VPC/Security setup must be complete before Week 3

---

## SLIDE 13: Security & Compliance
**Title:** Fintech-Grade Security

**Network Security**
🔒 100% private network
🔒 No public internet access
🔒 All traffic via VPC endpoints
🔒 VPC Flow Logs enabled
🔒 Security groups enforce least privilege

**Data Encryption**
🔒 EBS volumes: KMS encrypted
🔒 S3 buckets: SSE-KMS
🔒 In-transit: TLS 1.3
🔒 Customer-managed keys
🔒 Automatic key rotation

**Access Control**
🔒 IRSA for pod-level IAM
🔒 Kubernetes RBAC
🔒 MFA for AWS console
🔒 Cross-account role with External ID
🔒 kubectl access via VPN only

**Compliance**
🔒 CloudTrail (7-year retention)
🔒 SOC 2 Type II ready
🔒 PCI-DSS compliant architecture
🔒 GDPR data residency controls

---

## SLIDE 14: Cost Breakdown
**Title:** Monthly Cost Estimate

**Visual: Stacked bar chart**

| Component | Monthly Cost |
|-----------|--------------|
| **Infrastructure (Your AWS Account)** | |
| EKS Control Plane | $73 |
| Worker Nodes (6× m6i.4xlarge) | $3,366 |
| EBS Storage (24 TB gp3) | $1,920 |
| S3 Backups & Logs | $200 |
| VPC Endpoints (8 × 3 AZs) | $525 |
| CloudWatch | $400 |
| Data Transfer | $250 |
| Other (ECR, KMS, Route53) | $50 |
| **Infrastructure Subtotal** | **$6,784** |
| | |
| **ClickHouse Service Fee** | $2,000-3,000 |
| | |
| **Total Monthly Cost** | **$8,784-9,784** |

**Cost Optimizations Available:**
- Compute Savings Plan: -$500/month
- Spot instances (50%): -$1,000/month  
- **Potential savings: $1,500/month (17%)**

---

## SLIDE 15: Terraform Example
**Title:** Infrastructure as Code

**Code block (formatted):**

```hcl
# VPC - Private Only
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "clickhouse-vpc"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 3
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]
  
  # NO public IPs!
  map_public_ip_on_launch = false
}

# S3 Gateway Endpoint (Free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.s3"
}
```

**Benefits:**
✓ Version controlled  
✓ Repeatable deployments  
✓ Disaster recovery ready  
✓ Multi-environment support

---

## SLIDE 16: JDBC Best Practices
**Title:** Application Integration Guidelines

**Connection Pool Configuration (HikariCP):**

```java
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:clickhouse://clickhouse.internal:8123/prod");
config.setUsername("app_user");
config.setPassword("secure_password");

// Pool sizing
config.setMaximumPoolSize(50);      // Max connections
config.setMinimumIdle(10);          // Min idle
config.setConnectionTimeout(10000);  // 10 sec
config.setIdleTimeout(600000);      // 10 min
config.setMaxLifetime(1800000);     // 30 min

// Enable SSL
properties.setProperty("ssl", "true");
properties.setProperty("sslmode", "strict");
```

**Performance Tips:**
• Use batch inserts (1,000-10,000 rows)
• Enable compression
• Use async inserts for high throughput
• Implement retry logic with exponential backoff

---

## SLIDE 17: Monitoring Strategy
**Title:** What We'll Monitor

**Infrastructure Metrics (CloudWatch)**
• Worker node CPU, memory, disk
• VPC Flow Logs
• EBS IOPS and throughput
• S3 request rates
• Cost and usage

**Database Metrics (ClickHouse/Prometheus)**
• Queries per second (QPS)
• Query latency (P50, P95, P99)
• Disk usage per pod
• Replication lag
• Failed queries
• Merge operations

**Application Metrics**
• JDBC connection pool utilization
• Query execution time
• Error rates
• Slow queries (> 5 seconds)

**Alerting:**
• PagerDuty for critical issues
• Slack for warnings
• Weekly cost reports

---

## SLIDE 18: Pre-Launch Checklist
**Title:** Ready for Production?

**Infrastructure** ✅
- [ ] VPC and subnets created
- [ ] VPC endpoints configured
- [ ] Security groups tested
- [ ] IAM roles validated
- [ ] S3 buckets created
- [ ] CloudWatch alarms set
- [ ] VPN access working

**ClickHouse** ✅
- [ ] EKS cluster running
- [ ] ClickHouse pods healthy
- [ ] Backups configured
- [ ] Monitoring dashboards live
- [ ] DNS records updated

**Integration** ✅
- [ ] JDBC connectivity tested
- [ ] Connection pooling configured
- [ ] Load testing completed
- [ ] Failover tested
- [ ] Security audit passed

**Operations** ✅
- [ ] Runbooks documented
- [ ] Team trained
- [ ] On-call rotation set
- [ ] Escalation paths defined

---

## SLIDE 19: Risk Mitigation
**Title:** How We Handle Risks

| Risk | Mitigation Strategy |
|------|---------------------|
| **Data Loss** | • 3× replication across AZs<br>• Daily backups to S3<br>• Backup retention: 90 days<br>• Tested restore procedures |
| **Downtime** | • Multi-AZ deployment<br>• Pod anti-affinity<br>• Auto-healing<br>• 99.9% uptime SLA |
| **Performance Issues** | • Right-sized instances<br>• io2 available if needed<br>• Query caching<br>• Connection pooling |
| **Security Breach** | • Private network only<br>• All data encrypted<br>• CloudTrail audit logs<br>• Regular security scans |
| **Cost Overruns** | • Budget alerts<br>• Weekly cost reviews<br>• Savings Plans<br>• Auto-scaling |

---

## SLIDE 20: Success Criteria
**Title:** How We Measure Success

**Week 1:**
✓ Infrastructure deployed
✓ ClickHouse team has access
✓ All security validations passed

**Week 4:**
✓ EKS cluster operational
✓ ClickHouse pods running
✓ Test queries successful

**Week 7 (Production Launch):**
✓ All applications connected via JDBC
✓ Query latency < 100ms (P95)
✓ Zero security incidents
✓ Uptime > 99.9%

**Ongoing:**
✓ Cost within budget ±10%
✓ Query performance meeting SLAs
✓ < 2 support escalations per month
✓ Compliance audits passed

---

## SLIDE 21: Next Steps
**Title:** Getting Started

**This Week:**
1. Review this presentation with leadership team
2. Schedule kickoff with ClickHouse team
3. Get budget approval ($6.5-10K/month)
4. Assign project team members

**Next 2 Weeks:**
1. Ask ClickHouse all critical questions (see slide 8)
2. Get ClickHouse account ID and external ID
3. Begin Terraform development
4. Verify VPN/Direct Connect is ready

**Next 30 Days:**
1. Deploy VPC and all infrastructure
2. Provide details to ClickHouse team
3. ClickHouse creates EKS cluster
4. Begin JDBC integration testing

**Resources Provided:**
📄 Complete implementation guide (50+ pages)
💻 Terraform code (ready to deploy)
❓ 20+ critical questions for ClickHouse
📊 Architecture diagrams

---

## SLIDE 22: Q&A
**Title:** Questions?

**Contact Information:**
📧 Platform Engineering: platform@yourcompany.com
📞 On-Call: PagerDuty integration
💬 Slack: #clickhouse-project

**Project Resources:**
📁 Documentation: /docs/clickhouse-byoc/
💻 Terraform Code: /terraform-your-team/
📋 Questions for ClickHouse: See implementation guide
🎯 Project Tracker: JIRA/Project Board

**Next Meeting:**
Kickoff with ClickHouse Team
Date: TBD
Duration: 90 minutes
Agenda: Review questions, finalize timeline, discuss architecture

---

## Appendix Slides (Optional)

### A1: Detailed Security Group Rules
(Include exact ingress/egress rules from Terraform)

### A2: IAM Policy Examples
(Show sample policies for IRSA and cross-account role)

### A3: JDBC Code Examples
(More detailed Java code samples)

### A4: Monitoring Dashboard Screenshots
(Once available after deployment)

### A5: Cost Optimization Strategies
(Detailed breakdown of savings opportunities)

---

**END OF PRESENTATION**

**Total Slides:** 22 main slides + 5 appendix = 27 slides
**Presentation Duration:** 
- Executive summary (15 min): Slides 1-7, 14, 19-21
- Technical deep dive (45 min): All slides
- Workshop format (90 min): All slides + hands-on Terraform demo

**Design Notes:**
- Use navy blue (#1a365d) as primary color
- Gold (#d4af37) for accents and highlights
- White backgrounds with subtle gray for cards
- Courier New for code blocks
- Arial for body text, Arial Black for titles
- Include your company logo on every slide
- Page numbers in footer
