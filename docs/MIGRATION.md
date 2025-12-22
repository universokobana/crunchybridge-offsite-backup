# CBOB Migration Guide

Guide for migrating from CBOB v1 to v2.

## Table of Contents
- [Overview](#overview)
- [What's Changed](#whats-changed)
- [Migration Planning](#migration-planning)
- [Step-by-Step Migration](#step-by-step-migration)
- [Configuration Migration](#configuration-migration)
- [Script Migration](#script-migration)
- [Validation](#validation)
- [Rollback Plan](#rollback-plan)
- [FAQ](#faq)

## Overview

CBOB v2 introduces significant improvements while maintaining backward compatibility where possible. This guide helps you migrate from v1 scripts to the v2 unified CLI.

### Key Benefits of v2

- **Unified CLI** - Single entry point for all operations
- **Better Error Handling** - Retry logic and comprehensive error messages
- **Enhanced Monitoring** - Built-in metrics and health checks
- **Multi-Region Replication** - Cross-cloud backup replication
- **S3 Destination Support** - Sync directly to S3-compatible storage
- **Docker Support** - Container deployment options
- **PostgreSQL 18 Support** - Full compatibility with PostgreSQL 18

## What's Changed

### Directory Structure

**v1 Structure:**
```
/usr/local/bin/
├── cbob_sync
├── cbob_restore_check
├── cbob_stanza_info
├── cbob_stanza_expire
└── cbob_postgres
```

**v2 Structure:**
```
/usr/local/bin/
├── cbob                    # Main CLI
├── cbob-sync              # Sync subcommand
├── cbob-restore-check     # Restore check subcommand
├── cbob-info              # Info subcommand (renamed)
├── cbob-expire            # Expire subcommand (renamed)
├── cbob-postgres          # PostgreSQL management
├── cbob-replicate         # New: Replication
└── cbob-config            # New: Configuration management
```

### Configuration

**v1:** Single configuration file
**v2:** Multiple configuration sources with priority ordering

### Command Syntax

**v1:**
```bash
cbob_sync
cbob_restore_check
```

**v2:**
```bash
cbob sync
cbob restore-check
```

## Migration Planning

### Pre-Migration Checklist

- [ ] Backup current configuration
- [ ] Document custom scripts using CBOB
- [ ] Identify cron jobs
- [ ] Note any integrations
- [ ] Plan migration window
- [ ] Test in non-production

### Compatibility Mode

During migration, both v1 and v2 can coexist:

```bash
# Create symlinks for compatibility
sudo ln -s /usr/local/bin/cbob-sync /usr/local/bin/cbob_sync
sudo ln -s /usr/local/bin/cbob-restore-check /usr/local/bin/cbob_restore_check
```

## Step-by-Step Migration

### Step 1: Backup Current Setup

```bash
# Backup configuration
sudo cp /etc/cb_offsite_backup /etc/cb_offsite_backup.v1

# Backup scripts
sudo tar -czf cbob-v1-backup.tar.gz /usr/local/bin/cbob_*

# Export current metrics
cbob_stanza_info > cbob-v1-state.txt
```

### Step 2: Install CBOB v2

```bash
# Download and run installer
curl -fsSL https://github.com/CrunchyData/cbob/raw/main/install.sh | sudo bash
```

### Step 3: Migrate Configuration

```bash
# v2 reads v1 config automatically
# Validate existing config works
cbob config validate

# Or migrate manually
cbob config init
```

### Step 4: Update Cron Jobs

**v1 crontab:**
```cron
0 6 * * * postgres /usr/local/bin/cbob_sync
0 18 * * * postgres /usr/local/bin/cbob_restore_check
```

**v2 crontab:**
```cron
0 6 * * * postgres /usr/local/bin/cbob sync
0 18 * * * postgres /usr/local/bin/cbob restore-check
```

Update:
```bash
sudo crontab -e -u postgres
# Or edit directly
sudo nano /etc/cron.d/cbob_sync
```

### Step 5: Update Custom Scripts

**v1 script example:**
```bash
#!/bin/bash
/usr/local/bin/cbob_sync
if [ $? -eq 0 ]; then
    /usr/local/bin/cbob_stanza_info
fi
```

**v2 script update:**
```bash
#!/bin/bash
cbob sync
if [ $? -eq 0 ]; then
    cbob info
fi
```

### Step 6: Enable New Features (Optional)

```bash
# Configure S3 destination
cbob config set CBOB_DEST_TYPE s3
cbob config set CBOB_DEST_ENDPOINT https://fra1.digitaloceanspaces.com
cbob config set CBOB_DEST_BUCKET my-backups

# Configure replication
cbob replicate init

# Set up Docker-based cron
docker-compose up -d
```

## Configuration Migration

### Environment Variables

v1 and v2 use the same environment variables. No changes needed.

### New Configuration Options

v2 adds optional configuration:

```bash
# Logging enhancements
CBOB_LOG_FORMAT=json
CBOB_LOG_LEVEL=info

# Performance tuning
CBOB_SYNC_PARALLEL=4
CBOB_SYNC_BANDWIDTH=10MB/s

# Monitoring
CBOB_METRICS_FILE=/var/lib/cbob/metrics.json
```

### Multi-Environment Setup

Create environment-specific configs:

```bash
# Production
cp /etc/cb_offsite_backup /etc/cb_offsite_backup.prod

# Staging
cp /etc/cb_offsite_backup /etc/cb_offsite_backup.staging
sed -i 's/CBOB_DRY_RUN=false/CBOB_DRY_RUN=true/' /etc/cb_offsite_backup.staging
```

## Script Migration

### Command Mapping

| v1 Command | v2 Command | Notes |
|------------|------------|-------|
| `cbob_sync` | `cbob sync` | Added parallel support |
| `cbob_restore_check` | `cbob restore-check` | Enhanced reporting |
| `cbob_stanza_info` | `cbob info` | JSON output available |
| `cbob_stanza_expire` | `cbob expire` | Safer defaults |
| `cbob_postgres` | `cbob postgres` | Subcommands added |

### Script Updates

**Find and update scripts:**
```bash
# Find scripts using v1 commands
grep -r "cbob_" /usr/local/bin/ /etc/cron* ~/

# Update with sed (careful!)
sed -i 's/cbob_sync/cbob sync/g' /path/to/script
sed -i 's/cbob_restore_check/cbob restore-check/g' /path/to/script
```

### Output Format Migration

If using scripts to parse output:

**v1 parsing:**
```bash
cbob_stanza_info | grep "Last backup:"
```

**v2 with JSON:**
```bash
cbob info --format json | jq -r '.[].last_backup'
```

## Validation

### Verify Migration

```bash
#!/bin/bash
# migration-verify.sh

echo "=== Configuration Check ==="
cbob config validate

echo -e "\n=== Command Availability ==="
for cmd in sync restore-check info expire postgres replicate config; do
    if cbob $cmd --help >/dev/null 2>&1; then
        echo "✓ cbob $cmd"
    else
        echo "✗ cbob $cmd"
    fi
done

echo -e "\n=== Dry Run Test ==="
cbob sync --dry-run

echo -e "\n=== Backup Status ==="
cbob info
```

### Compare Operations

```bash
# Run parallel test
echo "=== v1 Test ==="
time cbob_sync

echo -e "\n=== v2 Test ==="
time cbob sync --parallel 4

# Compare results
cbob info
```

## Rollback Plan

If issues arise, rollback to v1:

### Quick Rollback

```bash
# Stop v2 services
docker-compose down

# Restore v1 configuration
sudo cp /etc/cb_offsite_backup.v1 /etc/cb_offsite_backup

# Restore cron jobs
sudo cp /etc/cron.d/cbob_sync.v1 /etc/cron.d/cbob_sync

# Use v1 commands
/usr/local/bin/cbob_sync
```

### Full Rollback

```bash
# Restore v1 binaries
cd /
sudo tar -xzf /path/to/cbob-v1-backup.tar.gz

# Remove v2
sudo rm -f /usr/local/bin/cbob*

# Restore configuration
sudo cp /etc/cb_offsite_backup.v1 /etc/cb_offsite_backup
```

## FAQ

### Q: Can I run v1 and v2 simultaneously?

A: Yes, but avoid running sync operations concurrently. Use lock files or different schedules.

### Q: Will v2 work with my existing backups?

A: Yes, v2 uses the same pgBackRest format and directory structure.

### Q: Do I need to change pgBackRest configuration?

A: No, v2 uses the same pgBackRest configuration.

### Q: Can I migrate gradually?

A: Yes, migrate one operation at a time:
1. Start with `cbob info` (read-only)
2. Then `cbob sync`
3. Finally `cbob restore-check`

### Q: What about custom integrations?

A: v2 provides better integration options:
- Use JSON format for structured data (`cbob info --format json`)
- Use structured JSON logging for log parsing
- Use heartbeat URLs for external monitoring

### Q: How do I migrate Slack notifications?

A: Slack configuration remains the same:
```bash
CBOB_SLACK_CLI_TOKEN=xoxb-your-token
CBOB_SLACK_CHANNEL=#backups
```

### Q: What if I have problems?

A: 
1. Check [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Enable debug logging: `CBOB_LOG_LEVEL=debug`
3. Report issues: https://github.com/CrunchyData/cbob/issues

## Post-Migration

### Optimize v2 Features

After successful migration:

1. **Enable parallel sync:**
   ```bash
   cbob config set CBOB_SYNC_PARALLEL 4
   ```

2. **Configure S3 destination:**
   ```bash
   cbob config set CBOB_DEST_TYPE s3
   cbob config set CBOB_DEST_BUCKET my-backups
   ```

3. **Set up replication:**
   ```bash
   cbob replicate init
   ```

4. **Remove v1 compatibility:**
   ```bash
   sudo rm -f /usr/local/bin/cbob_*
   ```

### Monitor Migration Success

```bash
# Check metrics
cbob metrics show

# Monitor logs
tail -f /var/log/cbob/cbob_sync.log

# Verify backups
cbob info --detailed
```

Congratulations on migrating to CBOB v2! 🎉