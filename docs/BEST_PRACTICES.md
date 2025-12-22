# CBOB Best Practices

Recommended practices for operating CBOB in production.

## Table of Contents
- [Deployment Best Practices](#deployment-best-practices)
- [Security Best Practices](#security-best-practices)
- [Operational Best Practices](#operational-best-practices)
- [Performance Best Practices](#performance-best-practices)
- [Monitoring Best Practices](#monitoring-best-practices)
- [Disaster Recovery Best Practices](#disaster-recovery-best-practices)
- [Cost Optimization](#cost-optimization)
- [Troubleshooting Best Practices](#troubleshooting-best-practices)

## Deployment Best Practices

### 1. Infrastructure Setup

**Dedicated Backup Server**
- Use a dedicated server for CBOB operations
- Separate from production database servers
- Adequate CPU, memory, and network bandwidth

**Storage Configuration**
```bash
# Use dedicated mount point
/mnt/cbob/
├── backups/        # Primary backup storage
├── temp/           # Temporary restore space
├── logs/           # Application logs
├── metrics/        # Metrics data
└── config/         # Configuration files
```

**Filesystem Choice**
- Use XFS or ext4 for backup storage
- Enable compression at filesystem level if supported
- Consider ZFS for snapshots and deduplication

### 2. High Availability Setup

**Active-Passive Configuration**
```bash
# Primary server
CBOB_ROLE=primary
CBOB_PEER_HOST=backup2.example.com

# Secondary server (standby)
CBOB_ROLE=standby
CBOB_PEER_HOST=backup1.example.com
```

**Shared Storage**
- Use NFS, GlusterFS, or cloud storage
- Ensure proper locking mechanisms
- Test failover procedures

### 3. Container Deployment

**Docker Best Practices**
```yaml
# docker-compose.yml
version: '3.8'

services:
  cbob:
    image: crunchybridge/cbob:latest
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
    healthcheck:
      test: ["CMD", "cbob", "health"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
        reservations:
          cpus: '2'
          memory: 4G
```

## Security Best Practices

### 1. Credential Management

**Never Store Credentials in Plain Text**
```bash
# Bad
CBOB_CRUNCHY_API_KEY=abc123

# Good - Use environment variable
export CBOB_CRUNCHY_API_KEY

# Better - Use secrets management
CBOB_USE_KEYRING=true
cbob config set --secure CBOB_CRUNCHY_API_KEY
```

**Rotate Credentials Regularly**
```bash
# Quarterly rotation schedule
0 0 1 */3 * /usr/local/bin/rotate-cbob-credentials.sh
```

### 2. Access Control

**File Permissions**
```bash
# Configuration files
chmod 600 /etc/cb_offsite_backup
chown postgres:postgres /etc/cb_offsite_backup

# Backup directory
chmod 750 /mnt/cbob/backups
chown postgres:postgres /mnt/cbob/backups

# Log directory
chmod 750 /var/log/cbob
chown postgres:adm /var/log/cbob
```

**User Isolation**
```bash
# Create dedicated user
useradd -r -s /bin/bash -d /var/lib/cbob cbob

# Grant minimal permissions
usermod -aG postgres cbob
```

### 3. Network Security

**Firewall Rules**
```bash
# Restrict outbound connections to required services only
# Allow S3 endpoints
# Allow Crunchy Bridge API
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
```

**Network Isolation**
```bash
# Use dedicated backup network if possible
# Limit access to backup storage
```

### 4. Audit Logging

**Enable Comprehensive Audit Logging**
```bash
# Configuration
CBOB_AUDIT_LOG=/var/log/cbob/audit.log
CBOB_AUDIT_LEVEL=all

# Monitor audit logs
tail -f /var/log/cbob/audit.log | grep -E "(MODIFY|DELETE|AUTH)"
```

## Operational Best Practices

### 1. Scheduling

**Stagger Backup Operations**
```cron
# Spread load across time
0 2 * * * postgres cbob sync --cluster prod-db-1
0 3 * * * postgres cbob sync --cluster prod-db-2
0 4 * * * postgres cbob sync --cluster prod-db-3

# Weekly verification
0 6 * * 0 postgres cbob restore-check --parallel 2
```

**Avoid Peak Hours**
- Schedule during off-peak hours
- Consider time zones for global deployments
- Monitor bandwidth usage

### 2. Retention Policies

**Tiered Retention**
```bash
# Production: 30 days
CBOB_prod_RETENTION_FULL=30
CBOB_prod_RETENTION_DIFF=7

# Development: 7 days
CBOB_dev_RETENTION_FULL=7
CBOB_dev_RETENTION_DIFF=2

# Archives: 365 days (cold storage)
CBOB_archive_RETENTION_FULL=365
```

**Automated Cleanup**
```bash
# Daily cleanup job
0 1 * * * postgres cbob expire --force

# Monthly deep clean
0 2 1 * * postgres find /mnt/cbob/temp -mtime +7 -delete
```

### 3. Change Management

**Test Before Production**
```bash
# Test in staging
CBOB_CONFIG_FILE=/etc/cb_offsite_backup.staging cbob sync --dry-run

# Validate changes
cbob config validate

# Apply to production
sudo cp /etc/cb_offsite_backup.staging /etc/cb_offsite_backup
```

**Version Control Configuration**
```bash
cd /etc
git init
git add cb_offsite_backup
git commit -m "Initial CBOB configuration"
```

## Performance Best Practices

### 1. Parallel Operations

**Optimize Parallelism**
```bash
# Based on available resources
# CPU cores: 8, Memory: 32GB
CBOB_SYNC_PARALLEL=4
CBOB_RESTORE_PARALLEL=2
CBOB_REPLICATION_PARALLEL=3
```

**Resource Limits**
```bash
# Prevent resource exhaustion
ulimit -n 65536  # File descriptors
ulimit -u 32768  # Processes
```

### 2. Bandwidth Management

**Time-Based Bandwidth**
```bash
# Business hours: limited
if [[ $(date +%H) -ge 8 && $(date +%H) -lt 18 ]]; then
    BANDWIDTH="5MB/s"
else
    BANDWIDTH="50MB/s"
fi

cbob sync --bandwidth "$BANDWIDTH"
```

**Network Optimization**
```bash
# Kernel tuning
echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
sysctl -p
```

### 3. Storage Optimization

**Compression**
```bash
# Enable S3 compression
export AWS_CLI_FILE_ENCODING=gzip

# pgBackRest compression
[global]
compress-type=lz4
compress-level=3
```

**Deduplication**
- Use filesystem-level deduplication
- Consider storage appliances with dedup
- Monitor deduplication ratios

## Monitoring Best Practices

### 1. Metrics Collection

**Key Metrics to Monitor**
```bash
# Backup metrics
- Backup success rate
- Backup duration
- Backup size growth
- Time since last backup

# System metrics
- CPU usage
- Memory usage
- Disk I/O
- Network throughput

# Application metrics
- Sync completion time
- Error rates
- Replication lag
```

**Alerting Thresholds**
```yaml
alerts:
  - name: BackupFailed
    threshold: 1 failure
    severity: critical
    
  - name: BackupDelayed
    threshold: 24 hours
    severity: warning
    
  - name: DiskSpaceLow
    threshold: 90%
    severity: critical
    
  - name: HighErrorRate
    threshold: 5%
    severity: warning
```

### 2. Dashboard Setup

**Executive Dashboard**
- Backup status overview
- Compliance status
- Storage utilization
- Cost trends

**Operations Dashboard**
- Real-time sync status
- Error logs
- Performance metrics
- Queue status

### 3. Log Management

**Centralized Logging**
```bash
# Ship logs to central system
CBOB_LOG_FORMAT=json
CBOB_LOG_DESTINATION=syslog://logserver:514
```

**Log Retention**
```bash
# /etc/logrotate.d/cbob
/var/log/cbob/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    sharedscripts
}
```

## Disaster Recovery Best Practices

### 1. Multi-Region Strategy

**Geographic Distribution**
```yaml
replication:
  replicas:
    - name: primary-region
      provider: aws
      region: us-east-1
      
    - name: dr-region
      provider: aws
      region: us-west-2
      
    - name: compliance-region
      provider: azure
      region: europe-west1
```

**Cross-Cloud Backup**
- Primary: AWS S3
- Secondary: Azure Blob
- Tertiary: On-premises

### 2. Recovery Testing

**Monthly DR Drills**
```bash
#!/bin/bash
# dr-test.sh

# Select random backup
STANZA=$(cbob info --format json | jq -r '.[].stanza' | shuf -n 1)

# Test restore
cbob restore-check --stanza "$STANZA"

# Verify application
pg_isready -h localhost -p 5432
```

**Recovery Time Objectives**
- RTO: 4 hours
- RPO: 1 hour
- Document and test procedures

### 3. Backup Verification

**Automated Verification**
```bash
# Daily sample verification
0 3 * * * postgres cbob restore-check --sample 10%

# Weekly full verification
0 2 * * 0 postgres cbob restore-check --all
```

## Cost Optimization

### 1. Storage Classes

**Lifecycle Policies**
```bash
# Recent backups: Standard
# Older backups: Infrequent Access
# Archives: Glacier

cbob replicate sync --storage-class STANDARD_IA
```

### 2. Data Transfer

**Minimize Transfer Costs**
- Use VPC endpoints
- Schedule during free tier hours
- Compress before transfer

### 3. Resource Right-Sizing

**Monitor and Adjust**
```bash
# Analyze usage
cbob metrics analyze --period 30d

# Adjust resources
CBOB_SYNC_PARALLEL=2  # Reduced from 4
```

## Troubleshooting Best Practices

### 1. Proactive Monitoring

**Health Checks**
```bash
# Automated health checks
*/5 * * * * /usr/local/bin/cbob-health-check.sh
```

### 2. Debug Information

**Capture Debug Data**
```bash
# Enable debug on failure
cbob sync || cbob sync --log-level debug
```

### 3. Support Information

**Collect Diagnostics**
```bash
# Support bundle
cbob support bundle --output /tmp/cbob-support.tar.gz
```

## Summary Checklist

### Daily Operations
- [ ] Monitor backup success
- [ ] Check available disk space
- [ ] Review error logs
- [ ] Verify replication status

### Weekly Operations
- [ ] Run restore verification
- [ ] Review metrics trends
- [ ] Update documentation
- [ ] Clean temporary files

### Monthly Operations
- [ ] DR drill execution
- [ ] Security audit
- [ ] Performance review
- [ ] Cost optimization

### Quarterly Operations
- [ ] Credential rotation
- [ ] Capacity planning
- [ ] Policy review
- [ ] Training updates