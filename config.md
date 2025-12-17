connector.class=com.clickhouse.kafka.connect.ClickHouseSinkConnector
tasks.max=2

# Kafka topics to consume
topics=events,logs,metrics

# Kafka connection with SASL/SCRAM authentication
bootstrap.servers=b-1.your-msk-cluster.xxxxx.kafka.us-east-1.amazonaws.com:9096,b-2.your-msk-cluster.xxxxx.kafka.us-east-1.amazonaws.com:9096
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="YOUR_MSK_USERNAME" password="YOUR_MSK_PASSWORD";

# ClickHouse connection
clickhouse.server.url=https://abc123.us-east-1.aws.clickhouse.cloud:8443
clickhouse.server.database=default
clickhouse.server.user=default
clickhouse.server.password=YOUR_CLICKHOUSE_PASSWORD
clickhouse.table.name=events_table

# Data format converters
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

# Error handling
errors.tolerance=all
errors.log.enable=true
errors.log.include.messages=true
errors.deadletterqueue.topic.name=dlq-clickhouse-sink-prod
errors.deadletterqueue.topic.replication.factor=3

# Performance tuning
batch.size=1000
buffer.count.records=10000
offset.flush.interval.ms=60000
