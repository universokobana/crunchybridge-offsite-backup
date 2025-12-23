# CBOB Quick Start Guide

Get up and running with CBOB in 5 minutes.

## Prerequisites

- CBOB installed ([Installation Guide](INSTALLATION.md))
- Crunchy Bridge API key
- At least one Crunchy Bridge cluster
- PostgreSQL 18

## Step 1: Configure CBOB

Create your configuration:

```bash
# Option 1: Interactive configuration
cbob config init

# Option 2: Manual configuration
sudo nano /usr/local/etc/cb_offsite_backup
```

### Local Storage (Default)

```bash
CBOB_CRUNCHY_API_KEY=your-api-key-here
CBOB_CRUNCHY_CLUSTERS=cluster-id-1,cluster-id-2
CBOB_TARGET_PATH=/mnt/backups
```

### S3-Compatible Storage

```bash
CBOB_CRUNCHY_API_KEY=your-api-key-here
CBOB_CRUNCHY_CLUSTERS=cluster-id-1,cluster-id-2
CBOB_DEST_TYPE=s3
CBOB_DEST_ENDPOINT=https://fra1.digitaloceanspaces.com
CBOB_DEST_BUCKET=my-cbob-backups
CBOB_DEST_ACCESS_KEY=your-access-key
CBOB_DEST_SECRET_KEY=your-secret-key
CBOB_DEST_REGION=fra1
```

## Step 2: Validate Configuration

```bash
cbob config validate
```

Expected output:
```
✓ CBOB_CRUNCHY_API_KEY: ***key
✓ CBOB_CRUNCHY_CLUSTERS: cluster-id-1,cluster-id-2
✓ CBOB_DEST_TYPE: s3
✓ CBOB_DEST_BUCKET: my-cbob-backups
✓ Configuration is valid
```

## Step 3: Test Connectivity

```bash
# Test API access
cbob info

# Test with dry run
sudo -u postgres cbob sync --dry-run
```

## Step 4: Run Your First Sync

```bash
# Run as postgres user
sudo -u postgres cbob sync

# Or with specific options
sudo -u postgres cbob sync --parallel 2 --cluster cluster-id-1
```

## Step 5: Check Results

```bash
# View sync status
cbob info

# Check logs
tail -f /var/log/cbob/cbob_sync.log

# Check configuration
cbob config show
```

## Step 6: Set Up Automation (Optional)

The installation already sets up daily syncs. To customize:

```bash
# Edit cron schedule
sudo nano /etc/cron.d/cbob_sync

# Default schedule:
# 0 6 * * * postgres /usr/local/bin/cbob sync
```

## Step 7: Enable Notifications (Optional)

### Slack Notifications

```bash
# Add to configuration
CBOB_SLACK_CLI_TOKEN=xoxb-your-token
CBOB_SLACK_CHANNEL=#backup-alerts
```

### Heartbeat Monitoring

```bash
# Add to configuration
CBOB_SYNC_HEARTBEAT_URL=https://cronitor.link/p/your-key/sync
CBOB_RESTORE_HEARTBEAT_URL=https://cronitor.link/p/your-key/restore
```

## Common Operations

### View Backup Information
```bash
cbob info
```

### Check Specific Cluster
```bash
cbob info --stanza cluster-id-1
```

### Expire Old Backups
```bash
cbob expire --retention-full 7
```

### Restore Check
```bash
sudo -u postgres cbob restore-check
```

## Quick Docker Setup

```bash
# Using docker-compose
cp .env.example .env
nano .env  # Add your configuration
docker-compose up -d

# Check status
docker-compose ps
docker logs cbob
```

## Troubleshooting Quick Fixes

### Permission Denied
```bash
# Run sync as postgres user
sudo -u postgres cbob sync
```

### Configuration Not Found
```bash
# Check config location
cbob config validate

# Set config path
export CBOB_CONFIG_FILE=/path/to/config
```

### Crunchy Bridge API Connection Failed
```bash
# Check API key
echo $CBOB_CRUNCHY_API_KEY

# Test API directly
curl -H "Authorization: Bearer $CBOB_CRUNCHY_API_KEY" \
  https://api.crunchybridge.com/clusters
```

### S3 Connection Failed
```bash
# Test S3 connectivity
aws --endpoint-url $CBOB_DEST_ENDPOINT s3 ls s3://$CBOB_DEST_BUCKET/
```

## Next Steps

- [CLI Reference](CLI.md) - Learn all commands
- [Configuration Guide](CONFIGURATION.md) - Advanced configuration
- [Docker Guide](DOCKER.md) - Container deployment
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
