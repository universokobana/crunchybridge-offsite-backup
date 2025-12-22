# CBOB Monitoring Guide

Comprehensive guide to monitoring CBOB operations, performance, and health.

## Table of Contents
- [Monitoring Overview](#monitoring-overview)
- [Metrics Collection](#metrics-collection)
- [Prometheus Integration](#prometheus-integration)
- [Alerting](#alerting)
- [Dashboards](#dashboards)
- [Log Management](#log-management)
- [Health Checks](#health-checks)
- [Performance Monitoring](#performance-monitoring)

## Monitoring Overview

CBOB provides multiple monitoring capabilities:

1. **Metrics** - Operational and performance metrics
2. **Logs** - Structured logging with multiple formats
3. **Alerts** - Notifications via Slack, email, and webhooks
4. **Health Checks** - API and system health endpoints
5. **Dashboards** - Visualization with Grafana

### Monitoring Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    CBOB     │────▶│ Prometheus  │────▶│   Grafana   │
└─────────────┘     └─────────────┘     └─────────────┘
       │                    │                    │
       │            ┌─────────────┐              │
       └───────────▶│    Logs     │              │
                    └─────────────┘              │
                            │                    │
                    ┌─────────────┐              │
                    │ Alertmanager│◀─────────────┘
                    └─────────────┘
```

## Metrics Collection

### Built-in Metrics

CBOB collects these metrics automatically:

**Backup Metrics:**
- `cbob_backup_sync_total` - Total sync operations
- `cbob_backup_sync_duration_seconds` - Sync duration
- `cbob_backup_size_bytes` - Backup size per cluster
- `cbob_backup_files_count` - Number of backup files

**Replication Metrics:**
- `cbob_replication_total` - Total replications
- `cbob_replication_duration_seconds` - Replication duration
- `cbob_replication_bytes` - Bytes replicated
- `cbob_replication_health` - Replica health status

**System Metrics:**
- `cbob_process_cpu_seconds_total` - CPU usage
- `cbob_process_memory_bytes` - Memory usage
- `cbob_disk_free_percent` - Disk space available

### Metrics Storage

Metrics are stored in multiple locations:

```bash
# JSON metrics file
${CBOB_BASE_PATH}/metrics/cbob_metrics.json

# Historical data (JSONL format)
${CBOB_BASE_PATH}/metrics/history/
├── sync_cluster1_202401.jsonl
├── replication_aws-eu_202401.jsonl
└── storage_cluster1_202401.jsonl
```

### Accessing Metrics

**CLI:**
```bash
# View current metrics
cbob config show

# View backup information
cbob info

# Generate metrics report
cbob metrics report

# Export Prometheus format
cbob metrics export --format prometheus
```

**File-based:**
```bash
# JSON metrics file
cat ${CBOB_BASE_PATH}/metrics/cbob_metrics.json

# View recent sync logs
tail -f /var/log/cbob/cbob_sync.log
```

## Prometheus Integration

### Prometheus Configuration

CBOB exports metrics to file which can be scraped by Prometheus using the node_exporter textfile collector:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    # Metrics from CBOB will be available via node_exporter textfile collector
```

Configure node_exporter to read CBOB metrics:
```bash
# Export metrics to textfile collector directory
cbob metrics export --format prometheus > /var/lib/prometheus/node-exporter/cbob.prom
```

### Custom Metrics

Create custom metrics in your scripts:

```bash
# Record custom metric
record_performance_metrics "custom_operation" "processing_time" "150"

# Export to Prometheus format
cbob metrics export --format prometheus
```

### PromQL Queries

Useful Prometheus queries:

```promql
# Backup success rate (last 24h)
rate(cbob_backup_sync_total{status="success"}[24h]) / rate(cbob_backup_sync_total[24h])

# Average sync duration
avg(cbob_backup_sync_duration_seconds) by (cluster)

# Replication lag
time() - cbob_replication_last_sync_timestamp

# Storage growth rate
rate(cbob_backup_size_bytes[7d])

# Failed operations
sum(increase(cbob_backup_sync_total{status="failed"}[1h]))
```

## Alerting

### Alert Configuration

Create `alerts.yml`:

```yaml
groups:
  - name: cbob_alerts
    interval: 30s
    rules:
      # Backup sync failure
      - alert: BackupSyncFailed
        expr: increase(cbob_backup_sync_total{status="failed"}[1h]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Backup sync failed for cluster {{ $labels.cluster }}"
          description: "Backup sync has failed {{ $value }} times in the last hour"
      
      # Replication lag
      - alert: ReplicationLag
        expr: (time() - cbob_replication_last_sync_timestamp) > 86400
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Replication lag for {{ $labels.replica }}"
          description: "Replication is {{ $value }} seconds behind"
      
      # Disk space
      - alert: LowDiskSpace
        expr: cbob_disk_free_percent < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space on backup storage"
          description: "Only {{ $value }}% disk space remaining"
```

### Slack Alerts

Configure Slack notifications:

```bash
# In configuration
CBOB_SLACK_CLI_TOKEN=xoxb-your-token
CBOB_SLACK_CHANNEL=#backup-alerts

# Custom alert
notify_slack() {
  local message="$1"
  local emoji="${2:-:warning:}"
  
  slack chat send \
    --channel "$CBOB_SLACK_CHANNEL" \
    --text "$emoji $message"
}
```

### Email Alerts

Configure email notifications:

```bash
# In configuration
PGBACKREST_AUTO_SMTP_SERVER=smtp.gmail.com:587
PGBACKREST_AUTO_MAIL_FROM=alerts@example.com
PGBACKREST_AUTO_MAIL_TO=ops@example.com

# Send alert
send_email_alert() {
  local subject="$1"
  local body="$2"
  
  sendemail \
    -f "$PGBACKREST_AUTO_MAIL_FROM" \
    -t "$PGBACKREST_AUTO_MAIL_TO" \
    -u "$subject" \
    -m "$body" \
    -s "$PGBACKREST_AUTO_SMTP_SERVER"
}
```

## Dashboards

### Grafana Dashboard

Import the CBOB dashboard:

```json
{
  "dashboard": {
    "title": "CBOB Monitoring",
    "panels": [
      {
        "title": "Backup Success Rate",
        "targets": [{
          "expr": "rate(cbob_backup_sync_total{status=\"success\"}[1h])"
        }]
      },
      {
        "title": "Storage Usage",
        "targets": [{
          "expr": "cbob_backup_size_bytes"
        }]
      },
      {
        "title": "Replication Status",
        "targets": [{
          "expr": "cbob_replication_health"
        }]
      }
    ]
  }
}
```

### CLI Dashboard

Create a monitoring script:

```bash
#!/bin/bash
# cbob-dashboard.sh

while true; do
  clear
  echo "CBOB Dashboard - $(date)"
  echo "=========================="

  # Sync status
  echo -e "\nBackup Sync Status:"
  cbob info --format json | jq -r '.[] |
    "\(.cluster_id): \(.status) - Last: \(.last_backup)"'

  # Replication status
  echo -e "\nReplication Status:"
  cbob replicate status

  # Disk usage
  echo -e "\nDisk Usage:"
  df -h ${CBOB_TARGET_PATH:-/data} | tail -1

  sleep 30
done
```

## Log Management

### Log Configuration

Configure structured logging:

```bash
# JSON logs for parsing
export CBOB_LOG_FORMAT=json
export CBOB_LOG_LEVEL=info

# Log locations
CBOB_LOG_PATH=/var/log/cbob
├── cbob_sync.log          # Sync operations
├── cbob_restore_check.log # Restore checks
├── cbob_replicate.log     # Replication
└── cbob_audit.log         # Security audit
```

### Log Rotation

Configure logrotate (`/etc/logrotate.d/cbob`):

```
/var/log/cbob/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 postgres postgres
    copytruncate
}
```

### Log Analysis

Parse JSON logs with jq:

```bash
# Failed operations
jq 'select(.level == "ERROR")' /var/log/cbob/cbob_sync.log

# Long-running operations
jq 'select(.duration_seconds > 3600)' /var/log/cbob/cbob_sync.log

# Specific cluster
jq 'select(.cluster == "prod-db-1")' /var/log/cbob/cbob_sync.log
```

## Health Checks

### CLI Health Check

```bash
# Validate configuration
cbob config validate

# Check backup status
cbob info

# Check specific stanza
cbob info --stanza cluster-id
```

### Custom Health Checks

Create monitoring script:

```bash
#!/bin/bash
# health-check.sh

check_cbob_health() {
  local status=0

  # Check configuration
  if ! cbob config validate > /dev/null 2>&1; then
    echo "CRITICAL: Configuration invalid"
    status=2
  fi

  # Check disk space
  local disk_usage=$(df -h /data | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ $disk_usage -gt 90 ]; then
    echo "WARNING: Disk usage at ${disk_usage}%"
    status=1
  fi

  # Check recent backups
  local last_sync=$(cbob info --format json | jq -r '.[0].last_backup')
  local sync_age=$(($(date +%s) - $(date -d "$last_sync" +%s)))
  if [ $sync_age -gt 86400 ]; then
    echo "WARNING: Last backup older than 24 hours"
    status=1
  fi

  exit $status
}
```

## Performance Monitoring

### Performance Metrics

Track key performance indicators:

```bash
# Sync performance
cbob metrics show --type performance

# View sync logs with timing
tail -f /var/log/cbob/cbob_sync.log | grep duration

# System resources
cbob system stats
```

### Performance Tuning

Monitor and tune based on metrics:

```bash
# Check slow operations
jq 'select(.duration_seconds > 1800)' /var/log/cbob/cbob_sync.log

# Identify bottlenecks
cbob performance analyze --period 7d

# Resource usage trends
cbob metrics trend --metric cpu_percent --period 30d
```

### Capacity Planning

Use metrics for capacity planning:

```bash
# Storage growth projection
cbob metrics project --metric storage --days 90

# Bandwidth usage
cbob metrics aggregate --metric bandwidth --period month

# Operation counts
cbob metrics count --operation sync --group-by day
```

## Monitoring Best Practices

### 1. Alert Fatigue Prevention
- Set appropriate thresholds
- Use alert grouping
- Implement alert suppression windows
- Regular alert review and tuning

### 2. Metric Retention
- Keep high-resolution data for 7 days
- Downsample to 5-minute resolution for 30 days
- Monthly aggregates for long-term storage

### 3. Dashboard Design
- One dashboard per concern (backups, replication, system)
- Use consistent color coding
- Include context in panel descriptions
- Set appropriate refresh intervals

### 4. Log Management
- Use structured logging (JSON)
- Implement log sampling for high-volume events
- Set up log aggregation (ELK, Splunk)
- Regular log cleanup

### 5. Monitoring as Code
- Version control monitoring configs
- Automate dashboard deployment
- Test alert rules
- Document monitoring setup

## Integration Examples

### Datadog Integration

```bash
#!/bin/bash
# datadog_integration.sh
# Export metrics to Datadog

METRICS_FILE="${CBOB_BASE_PATH}/metrics/cbob_metrics.json"

# Read metrics and send to Datadog
jq -r '.sync_metrics | to_entries[] |
  "cbob.sync.duration \(.value.duration) cluster:\(.key)"' \
  "$METRICS_FILE" | while read metric value tags; do
    echo "PUTVAL cbob/$metric $value $tags"
done
```

### New Relic Integration

```bash
# Send custom events from log data
tail -1 /var/log/cbob/cbob_sync.log | jq -c '{
  eventType: "CBOBBackup",
  cluster: .cluster,
  duration: .duration,
  status: .status,
  size_bytes: .size
}' | curl -X POST https://insights-collector.newrelic.com/v1/accounts/YOUR_ACCOUNT/events \
  -H "X-Insert-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d @-
```

### PagerDuty Integration

```bash
# Send PagerDuty alert
send_pagerduty_alert() {
  local severity="$1"
  local summary="$2"

  curl -X POST https://events.pagerduty.com/v2/enqueue \
    -H "Content-Type: application/json" \
    -d "{
      \"routing_key\": \"YOUR_ROUTING_KEY\",
      \"event_action\": \"trigger\",
      \"payload\": {
        \"summary\": \"$summary\",
        \"severity\": \"$severity\",
        \"source\": \"cbob\",
        \"component\": \"backup\"
      }
    }"
}
```