# CBOB Troubleshooting Guide

Common issues and solutions for CBOB operations.

## Table of Contents
- [Common Issues](#common-issues)
- [Sync Problems](#sync-problems)
- [Restore Check Issues](#restore-check-issues)
- [Replication Problems](#replication-problems)
- [API Issues](#api-issues)
- [Performance Issues](#performance-issues)
- [Docker Issues](#docker-issues)
- [Debug Commands](#debug-commands)
- [Getting Help](#getting-help)

## Common Issues

### Configuration Not Found

**Problem:** CBOB can't find configuration file

**Symptoms:**
```
ERROR: Configuration file not found
```

**Solutions:**

1. Check file locations:
```bash
# Check default locations
ls -la /etc/cb_offsite_backup
ls -la /usr/local/etc/cb_offsite_backup
ls -la ~/.cb_offsite_backup
```

2. Set config path explicitly:
```bash
export CBOB_CONFIG_FILE=/path/to/config
cbob config validate
```

3. Create new config:
```bash
cbob config init
```

### Permission Denied

**Problem:** Permission errors during operations

**Symptoms:**
```
ERROR: Permission denied: /mnt/backups
```

**Solutions:**

1. Run as postgres user:
```bash
sudo -u postgres cbob sync
```

2. Fix directory permissions:
```bash
sudo chown -R postgres:postgres /mnt/backups
sudo chmod 750 /mnt/backups
```

3. Check sudo configuration:
```bash
sudo -l -U postgres
```

### Missing Dependencies

**Problem:** Required tools not installed

**Symptoms:**
```
ERROR: Command not found: pgbackrest
```

**Solutions:**

1. Install missing packages:
```bash
# Ubuntu/Debian
sudo apt-get install pgbackrest postgresql-client-18 awscli

# RHEL/CentOS
sudo yum install pgbackrest postgresql18 awscli
```

2. Check PATH:
```bash
which pgbackrest
echo $PATH
```

## Sync Problems

### AWS S3 Access Denied

**Problem:** Can't access Crunchy Bridge S3 buckets

**Symptoms:**
```
fatal error: An error occurred (403) when calling the ListObjectsV2 operation: Access Denied
```

**Solutions:**

1. Check API key:
```bash
cbob config get CBOB_CRUNCHY_API_KEY
```

2. Test API access:
```bash
curl -H "Authorization: Bearer $CBOB_CRUNCHY_API_KEY" \
  https://api.crunchybridge.com/clusters
```

3. Refresh credentials:
```bash
# Force credential refresh
rm -f /tmp/cbob_creds_*.json
cbob sync --cluster your-cluster-id
```

### S3-Compatible Storage Upload Failures (DigitalOcean Spaces, Hetzner, MinIO)

**Problem:** Files fail to upload to S3-compatible storage destinations

**Symptoms:**
```
DEBUG: Failed to upload: 18-1/0000000100000049/000000010000004900000073.lz4
WARNING: Failed to upload 232 of 232 files
ERROR: Command failed after 3 attempts: sync_to_dest
```

**Root Causes and Solutions:**

#### 1. AWS_SESSION_TOKEN Conflict

When syncing from Crunchy Bridge (source) to S3-compatible storage (destination), the temporary `AWS_SESSION_TOKEN` from Crunchy Bridge credentials interferes with destination uploads.

**Fix:** CBOB v2 automatically unsets `AWS_SESSION_TOKEN` before destination uploads. If you're using a custom script, add:
```bash
unset AWS_SESSION_TOKEN
```

#### 2. CRC32 Checksum Not Supported

AWS CLI v2 sends `x-amz-checksum-crc32` headers by default, which some S3-compatible services don't support.

**Symptoms:**
```
An error occurred (InvalidRequest) when calling the PutObject operation
```

**Fix:** Set the environment variable:
```bash
export AWS_S3_REQUEST_CHECKSUM_CALCULATION="when_required"
```

Or in configuration:
```bash
AWS_S3_REQUEST_CHECKSUM_CALCULATION=when_required
```

#### 3. Region Configuration

Some S3-compatible services require specific region settings.

**Fix:** Always set the region explicitly:
```bash
CBOB_DEST_REGION=ams3  # For DigitalOcean Amsterdam
CBOB_DEST_REGION=fsn1  # For Hetzner Falkenstein
```

### Testing S3-Compatible Storage

```bash
# Test destination connectivity
. /usr/local/etc/cb_offsite_backup
export AWS_ACCESS_KEY_ID="$CBOB_DEST_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$CBOB_DEST_SECRET_KEY"
export AWS_S3_REQUEST_CHECKSUM_CALCULATION="when_required"

# List bucket contents
aws --endpoint-url "$CBOB_DEST_ENDPOINT" s3 ls "s3://$CBOB_DEST_BUCKET/"

# Test upload
echo "test" | aws --endpoint-url "$CBOB_DEST_ENDPOINT" s3 cp - "s3://$CBOB_DEST_BUCKET/test.txt"
```

### Sync Hanging

**Problem:** Sync process doesn't complete

**Symptoms:**
- No output for extended period
- Process seems stuck

**Solutions:**

1. Check lock file:
```bash
ls -la /tmp/cbob_sync.lock
# Remove stale lock
rm -f /tmp/cbob_sync.lock
```

2. Enable debug mode:
```bash
cbob sync --log-level debug
```

3. Check network:
```bash
# Test S3 connectivity
aws s3 ls s3://crunchy-backups-us-east-1/
```

### S3-to-S3 Sync Stuck at High CPU (Large Datasets)

**Problem:** When `CBOB_DEST_TYPE=s3`, sync appears stuck with high CPU usage but no files being downloaded

**Symptoms:**
- AWS CLI process at 90-100% CPU
- Log shows "Completed X GiB/~Y GiB ... calculating..." repeating forever
- No network activity despite CPU usage
- Typically affects clusters with large WAL archives (100k+ files)

**Root Cause:**

For S3-to-S3 sync, CBOB uses `aws s3 sync --exclude * --include file1 --include file2...` to download files in batches. With many include patterns (1000+), AWS CLI spends all CPU time on regex pattern matching instead of actual file transfer.

**Solutions:**

1. **Use CBOB v2.1.1+** (automatic fix):
   - Detects large datasets (>5000 files)
   - Switches to chunked sync by subdirectory
   - Much faster: ~63 MiB/s vs stuck at 0 MiB/s

2. **Adjust thresholds** (if needed):
```bash
# Lower threshold triggers chunked sync earlier
export CBOB_SYNC_LARGE_THRESHOLD=2000

# Smaller batch size for pattern-based sync
export CBOB_SYNC_BATCH_SIZE=50
```

3. **Manual recovery** (kill stuck process):
```bash
# Find and kill stuck AWS process
pkill -9 -f 'aws s3 sync'

# Remove lock and restart
rm -f /tmp/cbob_sync.lock
sudo -u postgres cbob sync
```

**Monitoring Progress:**

With chunked sync, you'll see progress like:
```
INFO: Large dataset detected (385131 files > 5000 threshold)
INFO: Using chunked sync by subdirectory for better performance...
INFO: Found 1509 subdirectories to sync
INFO:   [1/1509] Syncing subdirectory: 18-1/00000001000097C1
INFO:   [2/1509] Syncing subdirectory: 18-1/00000001000097C2
```

### Bandwidth Issues

**Problem:** Sync too slow or consuming too much bandwidth

**Solutions:**

1. Limit bandwidth:
```bash
cbob sync --bandwidth 5MB/s
```

2. Adjust parallelism:
```bash
# Reduce parallel operations
cbob sync --parallel 1
```

3. Use off-peak hours:
```bash
# Schedule for night
0 2 * * * postgres /usr/local/bin/cbob sync --bandwidth 20MB/s
```

## Restore Check Issues

### pgbackrest_auto Not Found

**Problem:** Can't find pgbackrest_auto script

**Symptoms:**
```
ERROR: pgbackrest_auto not found in PATH
```

**Solutions:**

1. Check installation:
```bash
ls -la /usr/local/bin/pgbackrest_auto
```

2. Update PATH:
```bash
export PATH=$PATH:/usr/local/bin
```

3. Reinstall:
```bash
cd /tmp
wget https://github.com/CrunchyData/pgbackrest_auto/raw/main/pgbackrest_auto
chmod +x pgbackrest_auto
sudo mv pgbackrest_auto /usr/local/bin/
```

### Restore Check Fails

**Problem:** Restore check reports errors

**Solutions:**

1. Check stanza:
```bash
pgbackrest --stanza=your-stanza info
```

2. Verify backup files:
```bash
pgbackrest --stanza=your-stanza verify
```

3. Check disk space:
```bash
df -h /tmp
df -h $CBOB_TARGET_PATH
```

## Replication Problems

### Provider Authentication Failed

**Problem:** Can't authenticate to cloud provider

**Solutions:**

**AWS:**
```bash
# Check credentials
aws sts get-caller-identity

# Configure credentials
aws configure
```

**Azure:**
```bash
# Login
az login

# Check account
az account show
```

**GCP:**
```bash
# Authenticate
gcloud auth login

# Check project
gcloud config get-value project
```

### Replication Sync Failures

**Problem:** Replication sync not completing

**Solutions:**

1. Check configuration:
```bash
cbob replicate config
```

2. Test connectivity:
```bash
cbob replicate test
```

3. Check specific replica:
```bash
cbob replicate status --replica aws-eu
```

4. Enable debug logging:
```bash
cbob replicate sync --log-level debug
```

## Performance Issues

### High Memory Usage

**Problem:** CBOB consuming too much memory

**Solutions:**

1. Reduce parallelism:
```bash
cbob sync --parallel 1
```

2. Adjust pgBackRest settings:
```bash
# In pgbackrest.conf
[global]
process-max=2
buffer-size=512K
```

3. Monitor memory:
```bash
top -u postgres
```

### Slow Operations

**Problem:** Operations taking too long

**Solutions:**

1. Check metrics:
```bash
cbob metrics show --type performance
```

2. Analyze bottlenecks:
```bash
# IO stats
iostat -x 1

# Network stats
iftop -i eth0
```

3. Optimize configuration:
```bash
# Increase parallelism
CBOB_SYNC_PARALLEL=4

# Adjust buffer sizes
export AWS_MAX_BANDWIDTH=50MB/s
```

## Docker Issues

### Container Restart Loop

**Problem:** Container keeps restarting

**Solutions:**

1. Check logs:
```bash
docker logs --tail 50 cbob
```

2. Verify volumes:
```bash
docker volume ls
docker volume inspect cbob_data
```

3. Reset container:
```bash
docker-compose down
docker-compose up -d
```

### Volume Mount Issues

**Problem:** Can't access files in container

**Solutions:**

1. Check permissions:
```bash
ls -la /mnt/cbob
```

2. Fix ownership:
```bash
sudo chown -R 999:999 /mnt/cbob
```

3. Verify mounts:
```bash
docker exec cbob df -h
```

## Debug Commands

### Enable Debug Logging

```bash
# Command line
cbob sync --log-level debug

# Environment
export CBOB_LOG_LEVEL=debug

# Configuration
CBOB_LOG_LEVEL=debug
```

### Trace Execution

```bash
# Bash trace
bash -x /usr/local/bin/cbob sync

# Strace
strace -f cbob sync 2>&1 | tee strace.log
```

### Check System Resources

```bash
# Overall system
vmstat 1

# Disk I/O
iotop -o

# Network
nethogs

# Process details
ps aux | grep cbob
```

### Analyze Logs

```bash
# Recent errors
grep ERROR /var/log/cbob/*.log | tail -20

# Specific time range
journalctl -u cbob --since "1 hour ago"

# JSON logs
jq 'select(.level == "ERROR")' /var/log/cbob/cbob_sync.log
```

## Getting Help

### Collect Diagnostic Information

```bash
#!/bin/bash
# diagnostic.sh

echo "=== System Information ==="
uname -a
cat /etc/os-release

echo -e "\n=== CBOB Version ==="
cbob version

echo -e "\n=== Configuration ==="
cbob config show

echo -e "\n=== Recent Logs ==="
tail -50 /var/log/cbob/cbob_sync.log

echo -e "\n=== Disk Usage ==="
df -h

echo -e "\n=== Process Status ==="
ps aux | grep -E '(cbob|postgres|pgbackrest)'

echo -e "\n=== Network Status ==="
netstat -tlnp | grep -E '5432'
```

### Report Issues

1. **GitHub Issues:**
   - https://github.com/CrunchyData/cbob/issues
   - Include diagnostic output
   - Describe steps to reproduce

2. **Slack Community:**
   - Join #cbob-users channel
   - Share logs and configuration

3. **Email Support:**
   - support@crunchybridge.com
   - Include cluster ID and logs

### Common Log Locations

| Component | Log Location |
|-----------|--------------|
| Sync | `/var/log/cbob/cbob_sync.log` |
| Restore | `/var/log/cbob/cbob_restore_check.log` |
| Replication | `/var/log/cbob/cbob_replicate.log` |
| Audit | `/var/log/cbob/cbob_audit.log` |
| pgBackRest | `/var/log/pgbackrest/*.log` |

### Emergency Recovery

If all else fails:

1. **Backup current state:**
```bash
tar -czf cbob-backup-$(date +%Y%m%d).tar.gz \
  /etc/cb_offsite_backup \
  $CBOB_BASE_PATH/config \
  /var/log/cbob
```

2. **Reset to defaults:**
```bash
# Stop all processes
docker-compose down
pkill -f cbob

# Clear locks
rm -f /var/lock/cbob_*.lock

# Reinitialize
cbob config init
```

3. **Test minimal operation:**
```bash
# Single cluster, no options
cbob sync --cluster single-cluster-id --dry-run
```

Remember: Always test changes in a non-production environment first!