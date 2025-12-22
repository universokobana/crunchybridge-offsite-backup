# CBOB v2 Migration Guide

This guide helps you migrate from the original CBOB scripts to the new unified CLI.

## Overview of Changes

### New Features in v2

1. **Unified CLI**: Single `cbob` command with subcommands
2. **Enhanced Error Handling**: Retry logic with exponential backoff
3. **Configuration Management**: Validation and secure storage
4. **Structured Logging**: JSON output option for log aggregation
5. **Parallel Operations**: Sync and check multiple clusters simultaneously
6. **Security Improvements**: Input validation and audit logging
7. **Progress Indicators**: Visual feedback for long operations
8. **Improved Testing**: Unit tests for core functionality

### Breaking Changes

- Individual scripts (`cbob_sync`, `cbob_info`, etc.) are replaced by subcommands
- Configuration validation is now mandatory
- Some environment variables have been renamed for consistency

## Migration Steps

### 1. Backup Current Configuration

```bash
# Backup your configuration
sudo cp /usr/local/etc/cb_offsite_backup /usr/local/etc/cb_offsite_backup.v1

# Backup any custom scripts
sudo cp -r /usr/local/bin/cbob_* /usr/local/backup/
```

### 2. Install New Version

```bash
# Clone the new version
git clone https://github.com/UniversoKobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup

# Run installation
sudo ./install.sh
```

### 3. Update Configuration

The configuration format remains mostly the same, but you should validate it:

```bash
# Validate existing configuration
cbob config validate

# If validation fails, update configuration interactively
cbob config init
```

### 4. Update Cron Jobs

Replace old cron entries with new commands:

**Old cron entries:**
```cron
00 06 * * * root /usr/local/bin/cbob_sync_and_expire
00 18 * * * root /usr/local/bin/cbob_restore_check
```

**New cron entries:**
```cron
00 06 * * * root /usr/local/bin/cbob sync && /usr/local/bin/cbob expire
00 18 * * * root /usr/local/bin/cbob restore-check
```

Update your crontab:
```bash
# Edit system crontab
sudo nano /etc/cron.d/cbob_sync_and_expire
sudo nano /etc/cron.d/cbob_restore_check
```

### 5. Update Custom Scripts

If you have custom scripts using CBOB commands, update them:

| Old Command | New Command |
|-------------|-------------|
| `cbob_sync` | `cbob sync` |
| `cbob_info` | `cbob info` |
| `cbob_expire` | `cbob expire` |
| `cbob_restore_check` | `cbob restore-check` |
| `cbob_postgres_start` | `cbob postgres start` |
| `cbob_postgres_stop` | `cbob postgres stop` |
| `cbob_postgres_restart` | `cbob postgres restart` |

### 6. Test the Migration

Run these commands to verify everything works:

```bash
# Test configuration
cbob config validate
cbob config show

# Test sync (dry run)
cbob sync --dry-run

# Check PostgreSQL status
cbob postgres status

# Show backup information
cbob info
```

## New Features Usage

### Parallel Sync

Sync multiple clusters in parallel:
```bash
cbob sync --parallel 4
```

### JSON Logging

Enable structured logging for log aggregation:
```bash
export CBOB_LOG_FORMAT=json
cbob sync
```

### Configuration Management

```bash
# Show current configuration (masked)
cbob config show

# Show configuration with secrets
cbob config show --unmask

# Get specific value
cbob config get CBOB_TARGET_PATH

# Set specific value
cbob config set CBOB_LOG_PATH /var/log/cbob
```

### Progress Monitoring

The new sync command shows progress and supports bandwidth limiting:
```bash
# Sync with bandwidth limit
cbob sync --bandwidth 10MB/s

# Estimate backup sizes before syncing
cbob sync --estimate-only
```

## Rollback Procedure

If you need to rollback to v1:

```bash
# Restore old configuration
sudo cp /usr/local/etc/cb_offsite_backup.v1 /usr/local/etc/cb_offsite_backup

# Restore old scripts
sudo cp /usr/local/backup/cbob_* /usr/local/bin/

# Restore old cron jobs
# Edit /etc/cron.d/cbob_* files to use old commands
```

## Troubleshooting

### Issue: Command not found

If `cbob` command is not found:
```bash
# Check if installed correctly
ls -la /usr/local/bin/cbob

# Add to PATH if needed
export PATH=/usr/local/bin:$PATH
```

### Issue: Permission denied

The new commands maintain the same permission requirements:
```bash
# Sync must run as postgres user
sudo -u postgres cbob sync

# Other commands may need sudo
sudo cbob config validate
```

### Issue: Lock file errors

The new system uses improved lock management:
```bash
# If you get lock errors, check for stale locks
ls -la /tmp/cbob*.lock

# Remove stale locks if needed
sudo rm /tmp/cbob*.lock
```

## Getting Help

- Use `cbob help` for general help
- Use `cbob <command> --help` for command-specific help
- Check logs in your configured log directory
- Report issues at: https://github.com/UniversoKobana/crunchybridge-offsite-backup/issues

## Summary

The migration to CBOB v2 provides many improvements while maintaining compatibility with existing configurations. The main changes are:

1. Unified CLI interface
2. Better error handling and recovery
3. Enhanced security and validation
4. Improved performance with parallel operations
5. Better observability with structured logging

Take time to test the new features in a non-production environment before fully migrating your production backup system.