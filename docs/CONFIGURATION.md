# CBOB Configuration Guide

Comprehensive guide to configuring CBOB for your environment.

## Table of Contents
- [Configuration Files](#configuration-files)
- [Configuration Priority](#configuration-priority)
- [Core Configuration](#core-configuration)
- [Advanced Configuration](#advanced-configuration)
- [Replication Configuration](#replication-configuration)
- [Security Configuration](#security-configuration)
- [Performance Tuning](#performance-tuning)
- [Environment-Specific Configs](#environment-specific-configs)

## Configuration Files

CBOB uses multiple configuration files:

| File | Purpose | Format |
|------|---------|--------|
| `/etc/cb_offsite_backup` | Main configuration | Shell variables |
| `/usr/local/etc/cb_offsite_backup` | Alternative location | Shell variables |
| `~/.cb_offsite_backup` | User-specific config | Shell variables |
| `${CBOB_BASE_PATH}/config/replication.yaml` | Replication config | YAML |
| `/etc/pgbackrest/pgbackrest.conf` | pgBackRest config | INI |

## Configuration Priority

Configuration is loaded in this order (later overrides earlier):

1. Default values (built-in)
2. System configuration (`/etc/cb_offsite_backup`)
3. Local configuration (`/usr/local/etc/cb_offsite_backup`)
4. User configuration (`~/.cb_offsite_backup`)
5. Environment variables
6. Command-line options

## Core Configuration

### Required Settings

```bash
# Crunchy Bridge API key (required)
CBOB_CRUNCHY_API_KEY=your-api-key-here

# Comma-separated list of cluster IDs (required)
CBOB_CRUNCHY_CLUSTERS=cluster-1,cluster-2,cluster-3

# Target path for backups (required)
CBOB_TARGET_PATH=/mnt/backups
```

### Basic Settings

```bash
# Base path for all CBOB data
CBOB_BASE_PATH=/mnt/volume_cbob

# Log directory
CBOB_LOG_PATH=/var/log/cbob

# PostgreSQL version
CBOB_PG_VERSION=18

# Number of full backups to retain
CBOB_RETENTION_FULL=7

# Enable dry-run mode
CBOB_DRY_RUN=false

# Non-interactive mode for automated deployments (Docker/CI)
CBOB_NONINTERACTIVE=false
```

### Volume/Storage Paths

When using a separate volume for temporary files and cache (recommended for large backups):

```bash
# Temporary directory for AWS CLI operations (useful for large volumes)
CBOB_TMPDIR=/mnt/volume/cbob/tmp

# Repository cache for restore-check (downloads from S3 for validation)
CBOB_REPO_CACHE=/mnt/volume/cbob/repo_cache

# Temporary restore directory for validation
CBOB_RESTORES_PATH=/mnt/volume/cbob/restores
```

### S3-Compatible Storage Destination

Configure CBOB to sync backups to S3-compatible storage (DigitalOcean Spaces, Hetzner, MinIO, etc.):

```bash
# Destination type: local or s3
CBOB_DEST_TYPE=s3

# S3 endpoint URL (required for s3)
CBOB_DEST_ENDPOINT=https://ams3.digitaloceanspaces.com

# S3 bucket name (required for s3)
CBOB_DEST_BUCKET=my-cbob-backups

# S3 access credentials (required for s3)
CBOB_DEST_ACCESS_KEY=your-access-key
CBOB_DEST_SECRET_KEY=your-secret-key

# S3 region (default: us-east-1)
CBOB_DEST_REGION=ams3

# Path prefix within the bucket
CBOB_DEST_PREFIX=/backup-replica
```

**Common S3-Compatible Endpoints:**

| Provider | Endpoint Example |
|----------|-----------------|
| DigitalOcean Spaces | `https://ams3.digitaloceanspaces.com` |
| Hetzner Object Storage | `https://fsn1.your-objectstorage.com` |
| MinIO | `https://minio.example.com:9000` |
| AWS S3 | `https://s3.us-east-1.amazonaws.com` |
| Backblaze B2 | `https://s3.us-west-000.backblazeb2.com` |

### Notification Settings

```bash
# Slack notifications
CBOB_SLACK_CLI_TOKEN=xoxb-your-slack-token
CBOB_SLACK_CHANNEL=#backup-alerts

# Email notifications (requires sendemail)
PGBACKREST_AUTO_SMTP_SERVER=smtp.gmail.com:587
PGBACKREST_AUTO_MAIL_FROM=backups@example.com
PGBACKREST_AUTO_MAIL_TO=alerts@example.com
PGBACKREST_AUTO_ATTACH_REPORT=true
```

### Monitoring Settings

```bash
# Heartbeat URLs for monitoring services
CBOB_SYNC_HEARTBEAT_URL=https://heartbeat.uptimerobot.com/sync
CBOB_RESTORE_HEARTBEAT_URL=https://heartbeat.uptimerobot.com/restore

# Metrics configuration
CBOB_METRICS_FILE=${CBOB_BASE_PATH}/metrics/cbob_metrics.json
CBOB_METRICS_HISTORY=${CBOB_BASE_PATH}/metrics/history
```

## Advanced Configuration

### Logging Configuration

```bash
# Log level: debug, info, warning, error
CBOB_LOG_LEVEL=info

# Log format: text, json
CBOB_LOG_FORMAT=text

# Log rotation (via logrotate)
# Edit /etc/logrotate.d/cb_offsite_backup
```

### Performance Settings

```bash
# Parallel operations
CBOB_SYNC_PARALLEL=4
CBOB_RESTORE_PARALLEL=2

# Bandwidth limiting
CBOB_SYNC_BANDWIDTH=10MB/s
CBOB_REPLICATION_BANDWIDTH=5MB/s

# Retry configuration
CBOB_RETRY_COUNT=3
CBOB_RETRY_DELAY=10
CBOB_RETRY_MAX_DELAY=300

# S3-to-S3 Sync Performance (when CBOB_DEST_TYPE=s3)
# Batch size for include-pattern sync (smaller = faster pattern matching)
CBOB_SYNC_BATCH_SIZE=100

# Threshold for switching to chunked sync by subdirectory
# For datasets larger than this, syncs entire subdirectories instead of individual files
# This avoids AWS CLI pattern matching overhead for large WAL archives
CBOB_SYNC_LARGE_THRESHOLD=5000
```

### Security Settings

```bash
# Audit logging
CBOB_AUDIT_LOG=${CBOB_LOG_PATH}/cbob_audit.log

# Secure credential storage
CBOB_USE_KEYRING=true
CBOB_KEYRING_SERVICE=cbob

# File permissions
CBOB_FILE_PERMISSIONS=600
CBOB_DIR_PERMISSIONS=700
```

## Replication Configuration

Create `${CBOB_BASE_PATH}/config/replication.yaml`:

```yaml
replication:
  # Primary backup location
  primary:
    provider: aws
    region: us-east-1
    bucket: primary-backups
    
  # Replica destinations
  replicas:
    # AWS replica in another region
    - name: aws-eu
      provider: aws
      region: eu-west-1
      bucket: eu-backups
      prefix: cbob/
      sync_interval: 1h
      retention_days: 30
      options:
        storage_class: STANDARD_IA
        sse: AES256
        
    # Azure replica for compliance
    - name: azure-compliance
      provider: azure
      region: westus2
      storage_account: backupscompliance
      container: cbob-backups
      sync_interval: 6h
      retention_days: 90
      options:
        tier: Cool
        
    # GCP replica for disaster recovery
    - name: gcp-dr
      provider: gcp
      project: my-project-123
      region: us-central1
      bucket: dr-backups
      sync_interval: 12h
      retention_days: 60
      options:
        storage_class: NEARLINE
        
  # Global replication settings
  settings:
    bandwidth_limit: 10MB/s
    parallel_transfers: 4
    verify_after_sync: true
    alert_on_failure: true
    retry_attempts: 3
    retry_delay: 300
```

## Security Configuration

### API Key Management

```bash
# Option 1: Environment variable
export CBOB_CRUNCHY_API_KEY=your-key

# Option 2: Secure file (chmod 600)
echo "CBOB_CRUNCHY_API_KEY=your-key" > ~/.cb_offsite_backup
chmod 600 ~/.cb_offsite_backup

# Option 3: System keyring (recommended)
cbob config set --secure CBOB_CRUNCHY_API_KEY
```

### File Permissions

```bash
# Set secure permissions on configuration
sudo chmod 600 /etc/cb_offsite_backup
sudo chown postgres:postgres /etc/cb_offsite_backup

# Restrict log access
sudo chmod 750 /var/log/cbob
sudo chown postgres:postgres /var/log/cbob
```

### Network Security

```bash
# Use HTTPS proxy
export HTTPS_PROXY=http://proxy.company.com:8080

# Certificate verification
export AWS_CA_BUNDLE=/path/to/ca-certificates.crt
export CURL_CA_BUNDLE=/path/to/ca-certificates.crt
```

## Performance Tuning

### Memory Settings

```bash
# pgBackRest settings (in pgbackrest.conf)
[global]
process-max=4
buffer-size=1024K
```

### AWS S3 Performance

```bash
# Increase S3 transfer performance
export AWS_MAX_BANDWIDTH=100MB/s
export AWS_MAX_CONCURRENT_REQUESTS=10
export AWS_MAX_QUEUE_SIZE=1000
```

### System Tuning

```bash
# Increase file descriptors
ulimit -n 65536

# Kernel parameters (add to /etc/sysctl.conf)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
```

## Environment-Specific Configs

### Development

```bash
# dev.env
CBOB_LOG_LEVEL=debug
CBOB_DRY_RUN=true
CBOB_RETENTION_FULL=1
CBOB_SYNC_PARALLEL=1
```

### Staging

```bash
# staging.env
CBOB_LOG_LEVEL=info
CBOB_DRY_RUN=false
CBOB_RETENTION_FULL=3
CBOB_SYNC_PARALLEL=2
CBOB_SLACK_CHANNEL=#staging-backups
```

### Production

```bash
# prod.env
CBOB_LOG_LEVEL=warning
CBOB_DRY_RUN=false
CBOB_RETENTION_FULL=7
CBOB_SYNC_PARALLEL=4
CBOB_SLACK_CHANNEL=#prod-alerts
CBOB_SYNC_HEARTBEAT_URL=https://monitoring.company.com/heartbeat/prod-backup
```

### Docker Configuration

```yaml
# docker-compose.override.yml
version: '3.8'

services:
  cbob:
    environment:
      - CBOB_CONFIG_FILE=/etc/cbob/prod.env
    volumes:
      - ./config/prod.env:/etc/cbob/prod.env:ro
```

## Configuration Examples

### Minimal Configuration

```bash
# Absolute minimum required
CBOB_CRUNCHY_API_KEY=abc123
CBOB_CRUNCHY_CLUSTERS=prod-db
CBOB_TARGET_PATH=/backups
```

### Full-Featured Configuration

```bash
# Complete configuration with all features
# API Configuration
CBOB_CRUNCHY_API_KEY=your-secure-api-key
CBOB_CRUNCHY_CLUSTERS=prod-db-1,prod-db-2,staging-db

# Storage Configuration
CBOB_BASE_PATH=/mnt/cbob
CBOB_TARGET_PATH=/mnt/cbob/backups
CBOB_LOG_PATH=/var/log/cbob

# Backup Configuration
CBOB_PG_VERSION=18
CBOB_RETENTION_FULL=7
CBOB_DRY_RUN=false

# Performance Configuration
CBOB_SYNC_PARALLEL=4
CBOB_RESTORE_PARALLEL=2
CBOB_SYNC_BANDWIDTH=20MB/s

# Notification Configuration
CBOB_SLACK_CLI_TOKEN=xoxb-slack-token
CBOB_SLACK_CHANNEL=#database-backups

# Monitoring Configuration
CBOB_SYNC_HEARTBEAT_URL=https://uptime.company.com/ping/backup-sync
CBOB_RESTORE_HEARTBEAT_URL=https://uptime.company.com/ping/backup-check

# Logging Configuration
CBOB_LOG_LEVEL=info
CBOB_LOG_FORMAT=json

# Security Configuration
CBOB_AUDIT_LOG=/var/log/cbob/audit.log
CBOB_USE_KEYRING=true
```

### Multi-Cluster Configuration

```bash
# Different settings per cluster
CBOB_CRUNCHY_CLUSTERS=prod-primary,prod-replica,analytics

# Cluster-specific settings (custom implementation)
CBOB_prod_primary_RETENTION=30
CBOB_prod_replica_RETENTION=7
CBOB_analytics_RETENTION=3
```

## Configuration Validation

### Validate Configuration

```bash
# Check current configuration
cbob config validate

# Test specific configuration file
CBOB_CONFIG_FILE=/path/to/test.conf cbob config validate
```

### Common Validation Errors

| Error | Solution |
|-------|----------|
| Missing API key | Set `CBOB_CRUNCHY_API_KEY` |
| Invalid cluster ID | Check cluster IDs match Crunchy Bridge |
| Path not writable | Check permissions on `CBOB_TARGET_PATH` |
| Invalid retention | Ensure `CBOB_RETENTION_FULL` is a number |

## Configuration Management

### Backup Configuration

```bash
# Backup current configuration
cp /etc/cb_offsite_backup /etc/cb_offsite_backup.$(date +%Y%m%d)
```

### Version Control

```bash
# Track configuration in git
cd /etc
git init
git add cb_offsite_backup
git commit -m "Initial CBOB configuration"
```

### Configuration Templates

Create templates for different environments:

```bash
# /etc/cbob/templates/
├── base.conf       # Common settings
├── dev.conf        # Development overrides
├── staging.conf    # Staging overrides
└── prod.conf       # Production overrides
```

## Best Practices

1. **Use Environment Variables** for sensitive data
2. **Version Control** your configuration files
3. **Regular Validation** with `cbob config validate`
4. **Separate Configs** for different environments
5. **Document Changes** in configuration
6. **Test Changes** in non-production first
7. **Monitor Config** for unauthorized changes
8. **Rotate Credentials** regularly