# Architecture Diagram: MSK to ClickHouse via Kafka Connect

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         AWS VPC (Private Network)                         │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                    Private Subnet (10.16.x.x/24)                      ││
│  │                                                                        ││
│  │                                                                        ││
│  │  ┌─────────────────────┐                                              ││
│  │  │   MSK Cluster       │                                              ││
│  │  │   (Your Existing)   │                                              ││
│  │  │                     │                                              ││
│  │  │   ┌─────────────┐   │                                              ││
│  │  │   │ Kafka Topic │   │                                              ││
│  │  │   │   (Data)    │   │                                              ││
│  │  │   └──────┬──────┘   │                                              ││
│  │  └──────────┼──────────┘                                              ││
│  │             │                                                          ││
│  │             │ OUTBOUND (Port 9094 TLS)                                ││
│  │             │ ⚡ Kafka Connect PULLS data from MSK                     ││
│  │             │                                                          ││
│  │             ▼                                                          ││
│  │  ┌──────────────────────┐                                             ││
│  │  │   EC2 Instance       │                                             ││
│  │  │   Kafka Connect      │                                             ││
│  │  │   t3.large           │                                             ││
│  │  │                      │                                             ││
│  │  │  ┌────────────────┐  │                                             ││
│  │  │  │ Kafka Connect  │  │                                             ││
│  │  │  │  Consumer      │  │ ← Reads from MSK topics                    ││
│  │  │  └────────┬───────┘  │                                             ││
│  │  │           │          │                                             ││
│  │  │  ┌────────▼───────┐  │                                             ││
│  │  │  │  ClickHouse    │  │                                             ││
│  │  │  │ Sink Connector │  │ ← Processes & transforms data              ││
│  │  │  └────────┬───────┘  │                                             ││
│  │  └───────────┼──────────┘                                             ││
│  │              │                                                         ││
│  │              │ OUTBOUND (Port 8443 HTTPS)                             ││
│  │              │ ⚡ Kafka Connect PUSHES data to ClickHouse              ││
│  │              │                                                         ││
│  │              ▼                                                         ││
│  │  ┌──────────────────────────────────┐                                 ││
│  │  │   VPC Endpoint                   │                                 ││
│  │  │   (PrivateLink Interface)        │                                 ││
│  │  │                                  │                                 ││
│  │  │   Private IP: 10.16.x.x          │                                 ││
│  │  │   DNS: your-cluster.clickhouse   │                                 ││
│  │  │        .cloud → 10.16.x.x        │                                 ││
│  │  └────────────┬─────────────────────┘                                 ││
│  │               │                                                        ││
│  └───────────────┼────────────────────────────────────────────────────────┘│
│                  │                                                         │
└──────────────────┼─────────────────────────────────────────────────────────┘
                   │
                   │ AWS PrivateLink
                   │ (Private AWS Backbone - NOT Internet)
                   │
                   ▼
        ┌────────────────────────────┐
        │   ClickHouse Cloud         │
        │   (Fully Managed)          │
        │                            │
        │   Port: 8443 (HTTPS)       │
        │   Your Tables              │
        └────────────────────────────┘
```

## Data Flow Explanation

### Step 1: MSK → Kafka Connect (PULL - Inbound to MSK)
```
MSK Cluster (existing)
    │
    │ Security Group Rule: INBOUND
    │ Allow port 9094 from Kafka Connect SG
    │
    ▼
Kafka Connect EC2 (OUTBOUND to MSK)
    │
    │ Security Group Rule: OUTBOUND  
    │ Allow port 9094 to MSK SG
    │
    └─► Kafka Connect CONSUMER reads from Kafka topics
```

**What happens:**
- Kafka Connect acts as a **Kafka Consumer**
- It **pulls** messages from MSK topics
- Uses port **9094** with **TLS encryption**
- This is **OUTBOUND** from EC2 perspective (EC2 initiates connection)
- This is **INBOUND** to MSK (MSK receives connection)

### Step 2: Kafka Connect → ClickHouse (PUSH - Outbound to ClickHouse)
```
Kafka Connect EC2
    │
    │ ClickHouse Sink Connector processes data
    │
    ▼ OUTBOUND to VPC Endpoint
    │ Security Group Rule: OUTBOUND
    │ Allow port 8443 to VPC Endpoint SG
    │
    ▼
VPC Endpoint (INBOUND from Kafka Connect)
    │ Security Group Rule: INBOUND
    │ Allow port 8443 from Kafka Connect SG
    │
    ▼ AWS PrivateLink
    │
    ▼
ClickHouse Cloud
    │
    └─► Data inserted into tables
```

**What happens:**
- Kafka Connect acts as a **ClickHouse Client**
- It **pushes** data to ClickHouse via HTTPS
- Uses port **8443** (HTTPS)
- This is **OUTBOUND** from EC2 perspective (EC2 initiates connection)
- Goes through **VPC Endpoint** (private IP in your VPC)
- Traffic travels via **AWS PrivateLink** (never touches internet)

## Security Group Rules Summary

### MSK Security Group
```hcl
# INBOUND - Allow Kafka Connect to pull data
Port: 9094 (TLS)
Source: kafka_connect_ec2 Security Group
Direction: INBOUND (receiving connection from Kafka Connect)
```

### Kafka Connect EC2 Security Group
```hcl
# OUTBOUND - Allow pulling from MSK
Port: 9094 (TLS)
Destination: msk_cluster Security Group
Direction: OUTBOUND (initiating connection to MSK)

# OUTBOUND - Allow pushing to ClickHouse
Port: 8443 (HTTPS)
Destination: clickhouse_endpoint Security Group  
Direction: OUTBOUND (initiating connection to ClickHouse)

# OUTBOUND - Internet for plugins
Port: 443, 80
Destination: 0.0.0.0/0
Direction: OUTBOUND (downloading Kafka Connect plugins)
```

### ClickHouse VPC Endpoint Security Group
```hcl
# INBOUND - Allow Kafka Connect to push data
Port: 8443 (HTTPS)
Source: kafka_connect_ec2 Security Group
Direction: INBOUND (receiving connection from Kafka Connect)
```

## Answer to "Inbound or Outbound?"

**From EC2 Kafka Connect perspective:**

1. **To MSK:** 
   - ✅ **OUTBOUND** (EC2 Security Group egress rule)
   - EC2 initiates connection
   - Kafka Connect **PULLS** data from MSK

2. **To ClickHouse:**
   - ✅ **OUTBOUND** (EC2 Security Group egress rule)  
   - EC2 initiates connection
   - Kafka Connect **PUSHES** data to ClickHouse

**From MSK perspective:**
- ✅ **INBOUND** (MSK Security Group ingress rule)
- MSK receives connection from Kafka Connect

**From ClickHouse VPC Endpoint perspective:**
- ✅ **INBOUND** (VPC Endpoint Security Group ingress rule)
- VPC Endpoint receives connection from Kafka Connect

## Why This Works Privately

1. **No Public IPs:** Everything is in private subnets
2. **VPC Endpoint:** Creates network interface with private IP (10.16.x.x)
3. **Private DNS:** ClickHouse hostname resolves to VPC Endpoint private IP
4. **PrivateLink:** AWS routes traffic through AWS backbone, not internet
5. **Security Groups:** Control exactly which traffic is allowed

## Traffic Never Touches Internet

```
✅ MSK ←→ EC2: Private subnet communication
✅ EC2 ←→ VPC Endpoint: Private subnet communication  
✅ VPC Endpoint ←→ ClickHouse: AWS PrivateLink (AWS backbone)
❌ No public internet involved in data transfer
```

Only internet access needed: EC2 downloads Kafka Connect plugins once during setup.
