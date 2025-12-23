# CBOB Multi-Region Replication Guide

This guide covers the multi-region replication feature that allows you to automatically replicate your Crunchy Bridge backups across multiple geographic regions and cloud providers.

## Overview

Multi-region replication provides:

- **Geographic redundancy**: Protect against regional outages
- **Cross-cloud backup**: Avoid vendor lock-in by replicating to multiple cloud providers
- **Compliance**: Meet data residency requirements
- **Disaster recovery**: Fast recovery from the nearest replica
- **Cost optimization**: Use different storage classes based on retention needs

## Supported Storage Providers

- **AWS S3**: All regions, including GovCloud
- **Azure Blob Storage**: All regions
- **Google Cloud Storage**: All regions
- **DigitalOcean Spaces**: All regions
- **MinIO**: Self-hosted S3-compatible storage

## Quick Start

### 1. Initialize Replication Configuration

```bash
cbob replicate init
```

This creates a template configuration file at `${CBOB_BASE_PATH}/config/replication.yaml`.

### 2. Configure Destinations

Edit the configuration file to add your replication destinations:

```yaml
replication:
  primary:
    provider: aws
    region: us-east-1
    bucket: my-primary-backups
    
  replicas:
    # AWS Europe replica
    - name: eu-replica
      provider: aws
      region: eu-west-1
      bucket: my-eu-backups
      sync_interval: 1h
      retention_days: 30
      
    # Azure replica
    - name: azure-dr
      provider: azure
      region: westus2
      storage_account: mybackupaccount
      container: cbob-replicas
      sync_interval: 6h
      retention_days: 90
```

### 3. Set Credentials

Configure credentials for each provider:

**AWS**:
```bash
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
# Or use IAM roles
```

**Azure**:
```bash
export AZURE_STORAGE_CONNECTION_STRING=your-connection-string
# Or use managed identity
```

**Google Cloud**:
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
# Or use workload identity
```

**DigitalOcean**:
```bash
# Configure in replication.yaml with access keys
```

### 4. Test Connectivity

```bash
cbob replicate test
```

### 5. Start Replication

```bash
# Replicate to all configured destinations
cbob replicate sync

# Replicate to specific destination
cbob replicate sync --replica eu-replica
```

## Configuration Reference

### Primary Storage

The source location for replication (usually your main backup location):

```yaml
primary:
  provider: aws              # Storage provider
  region: us-east-1         # Region
  bucket: primary-backups   # Bucket/container name
```

### Replica Configuration

Each replica supports these options:

```yaml
replicas:
  - name: unique-name       # Unique identifier
    provider: aws           # Provider: aws, azure, gcp, digitalocean
    region: eu-west-1       # Region/location
    bucket: replica-bucket  # Bucket/container/space name
    prefix: backups/        # Optional path prefix
    sync_interval: 1h       # How often to sync (not enforced by CBOB)
    retention_days: 30      # Retention period (for documentation)
    
    # Provider-specific options
    storage_account: name   # Azure: storage account name
    project: project-id     # GCP: project ID
    access_key: key        # DO: access key
    secret_key: secret     # DO: secret key
```

### Global Settings

```yaml
settings:
  bandwidth_limit: 10MB/s    # Limit replication bandwidth
  parallel_transfers: 4      # Number of parallel operations
  verify_after_sync: true    # Verify checksums after sync
  alert_on_failure: true     # Send alerts on failure
  retry_attempts: 3          # Retry failed operations
  retry_delay: 300          # Delay between retries (seconds)
```

## CLI Commands

### Sync Operations

```bash
# Sync to all replicas
cbob replicate sync

# Sync to specific replica
cbob replicate sync --replica eu-replica

# Sync with parallel operations
cbob replicate sync --parallel 4

# Dry run to see what would be synced
cbob replicate sync --dry-run

# Sync and verify
cbob replicate sync --verify
```

### Status and Monitoring

```bash
# Show replication status
cbob replicate status

# Show specific replica status
cbob replicate status --replica eu-replica

# Check replication health
cbob replicate health

# Show configuration
cbob replicate config
```

### Verification

```bash
# Verify replica integrity
cbob replicate verify --replica eu-replica
```

## Monitoring

### Metrics

Replication metrics are exposed via Prometheus:

- `cbob_replication_total`: Total replications by status
- `cbob_replication_duration_seconds`: Replication duration
- `cbob_replication_bytes`: Bytes replicated

### Health Checks

Replicas are considered:
- **Healthy**: Last sync < 24 hours ago
- **Warning**: Last sync 24-48 hours ago
- **Critical**: Last sync > 48 hours ago
- **Unknown**: Never synced

### Logs

Replication operations are logged to:
- CLI: `${CBOB_LOG_PATH}/cbob_replicate.log`
- Metrics: `${CBOB_BASE_PATH}/metrics/replication_*.jsonl`

## Scheduling

While CBOB doesn't enforce sync intervals, you can schedule replication using cron:

```bash
# Add to crontab
# Hourly replication to EU
0 * * * * /usr/local/bin/cbob replicate sync --replica eu-replica

# Daily replication to Azure
0 2 * * * /usr/local/bin/cbob replicate sync --replica azure-dr
```

## Best Practices

### 1. Security

- Use IAM roles/managed identities instead of keys where possible
- Encrypt credentials at rest
- Enable encryption in transit and at rest for all replicas
- Use separate credentials with minimal permissions

### 2. Cost Optimization

- Use lifecycle policies to transition to cheaper storage classes
- Set appropriate retention periods per replica
- Use bandwidth limiting during business hours
- Consider regional data transfer costs

### 3. Reliability

- Test restore from each replica regularly
- Monitor replication lag and health
- Set up alerts for failed replications
- Document recovery procedures

### 4. Performance

- Use parallel transfers for large datasets
- Schedule intensive replications during off-peak hours
- Consider using storage acceleration features
- Monitor bandwidth usage

## Disaster Recovery Scenarios

### Regional Outage

If your primary region fails:

1. Identify the most recent replica:
   ```bash
   cbob replicate status
   ```

2. Update configuration to use replica as primary
3. Restore from replica to new primary region

### Provider Outage

If a cloud provider fails:

1. Use cross-cloud replicas for recovery
2. Update DNS/endpoints to point to alternate provider
3. Restore services using alternate provider's replica

### Compliance Scenarios

For data residency requirements:

1. Configure region-specific replicas
2. Set retention policies per region
3. Use `prefix` to organize by compliance zone

## Troubleshooting

### Replication Fails

1. Check connectivity:
   ```bash
   cbob replicate test --replica problem-replica
   ```

2. Verify credentials:
   - Check environment variables
   - Verify IAM permissions
   - Test with provider CLIs

3. Check logs:
   ```bash
   tail -f ${CBOB_LOG_PATH}/cbob_replicate.log
   ```

### Slow Replication

1. Check bandwidth limits in configuration
2. Monitor network usage
3. Consider parallel transfers
4. Check for large files that need segmentation

### Verification Failures

1. Check for incomplete transfers
2. Verify source hasn't changed during transfer
3. Check for provider-specific limitations
4. Try re-syncing specific files

## Advanced Configuration

### Cross-Account Replication (AWS)

```yaml
replicas:
  - name: cross-account
    provider: aws
    region: us-west-2
    bucket: other-account-bucket
    # Use assume role for cross-account access
    role_arn: arn:aws:iam::123456789012:role/ReplicationRole
```

### Storage Classes

```yaml
replicas:
  - name: archive-replica
    provider: aws
    region: us-east-1
    bucket: archive-bucket
    storage_class: GLACIER  # Use cheaper storage
```

### Encryption

```yaml
replicas:
  - name: encrypted-replica
    provider: aws
    region: eu-west-1
    bucket: encrypted-bucket
    sse: AES256  # Server-side encryption
    kms_key_id: alias/backup-key  # KMS encryption
```

## Migration from Single Region

To migrate from single-region to multi-region:

1. Set up replication configuration
2. Run initial sync (may take time):
   ```bash
   cbob replicate sync
   ```
3. Monitor progress:
   ```bash
   watch cbob replicate status
   ```
4. Update disaster recovery procedures
5. Test restore from each replica