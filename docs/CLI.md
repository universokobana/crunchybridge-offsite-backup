# CBOB CLI Reference

Complete reference for all CBOB command-line interface commands.

## Table of Contents
- [Global Options](#global-options)
- [Commands Overview](#commands-overview)
- [Detailed Command Reference](#detailed-command-reference)
  - [sync](#sync)
  - [restore-check](#restore-check)
  - [info](#info)
  - [expire](#expire)
  - [postgres](#postgres)
  - [replicate](#replicate)
  - [config](#config)
- [Examples](#examples)
- [Environment Variables](#environment-variables)

## Global Options

These options can be used with any command:

```bash
cbob [global-options] <command> [command-options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--config FILE` | Use specific configuration file | Auto-detected |
| `--log-level LEVEL` | Set log level (debug, info, warning, error) | info |
| `--log-format FORMAT` | Set log format (text, json) | text |
| `--dry-run` | Run in dry-run mode (no changes) | false |
| `--no-lock` | Skip lock file creation | false |
| `--help, -h` | Show help message | - |
| `--version, -v` | Show version information | - |

## Commands Overview

| Command | Description |
|---------|-------------|
| `sync` | Sync backups from Crunchy Bridge |
| `restore-check` | Check backup integrity |
| `info` | Show backup information |
| `expire` | Expire old backups |
| `postgres` | Manage PostgreSQL instances |
| `replicate` | Multi-region replication |
| `config` | Configuration management |
| `help` | Show help information |
| `version` | Show version |

## Detailed Command Reference

### sync

Synchronize backups from Crunchy Bridge to local storage.

```bash
cbob sync [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--cluster ID` | Sync specific cluster (repeatable) | All clusters |
| `--parallel N` | Number of parallel sync operations | 1 |
| `--bandwidth LIMIT` | Bandwidth limit (e.g., 10MB/s) | Unlimited |
| `--retry-count N` | Number of retries for failed operations | 3 |
| `--retry-delay N` | Initial retry delay in seconds | 5 |
| `--skip-validation` | Skip post-sync validation | false |
| `--estimate-only` | Show estimated sizes without syncing | false |

**Examples:**

```bash
# Sync all clusters
sudo -u postgres cbob sync

# Sync specific clusters in parallel
sudo -u postgres cbob sync --cluster prod-1 --cluster prod-2 --parallel 2

# Estimate backup sizes
cbob sync --estimate-only

# Sync with bandwidth limit
sudo -u postgres cbob sync --bandwidth 5MB/s

# Dry run
cbob sync --dry-run
```

### restore-check

Check integrity of backups using pgbackrest_auto.

```bash
cbob restore-check [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--stanza NAME` | Check specific stanza only | All stanzas |
| `--parallel N` | Number of parallel checks | 1 |
| `--skip-checkdb` | Skip database consistency check | false |
| `--report-dir DIR` | Directory for reports | Auto-generated |
| `--email` | Send report via email | false |

**Examples:**

```bash
# Check all backups
sudo -u postgres cbob restore-check

# Check specific stanza
sudo -u postgres cbob restore-check --stanza prod-cluster-1

# Parallel checks
sudo -u postgres cbob restore-check --parallel 2

# Generate report
sudo -u postgres cbob restore-check --report-dir /tmp/reports
```

### info

Display information about backups and stanzas.

```bash
cbob info [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--stanza NAME` | Show info for specific stanza | All stanzas |
| `--format FORMAT` | Output format (text, json) | text |
| `--detailed` | Show detailed backup information | false |

**Examples:**

```bash
# Show all backup info
cbob info

# Show specific stanza
cbob info --stanza prod-cluster-1

# JSON output
cbob info --format json

# Detailed information
cbob info --detailed
```

### expire

Expire old backups based on retention policy.

```bash
cbob expire [options]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--stanza NAME` | Expire specific stanza only | All stanzas |
| `--retention-full N` | Override full backup retention | From config |
| `--force` | Skip confirmation prompt | false |

**Examples:**

```bash
# Expire all stanzas
sudo -u postgres cbob expire

# Expire specific stanza
sudo -u postgres cbob expire --stanza prod-cluster-1

# Override retention
sudo -u postgres cbob expire --retention-full 3 --force
```

### postgres

Manage local PostgreSQL instances for restore testing.

```bash
cbob postgres <subcommand> [options]
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `start` | Start PostgreSQL clusters |
| `stop` | Stop PostgreSQL clusters |
| `restart` | Restart PostgreSQL clusters |
| `status` | Show cluster status |
| `initdb` | Initialize data directories |
| `list` | List configured clusters |

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--cluster ID` | Operate on specific cluster | All clusters |
| `--force` | Force operation without confirmation | false |

**Examples:**

```bash
# Start all clusters
cbob postgres start

# Stop specific cluster
cbob postgres stop --cluster prod-1

# Check status
cbob postgres status

# Initialize databases
sudo -u postgres cbob postgres initdb
```

### replicate

Manage multi-region replication.

```bash
cbob replicate <subcommand> [options]
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `sync` | Sync to replica destinations |
| `status` | Show replication status |
| `health` | Check replication health |
| `verify` | Verify replica integrity |
| `config` | Show replication configuration |
| `init` | Initialize replication config |
| `test` | Test replica connectivity |

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--replica NAME` | Operate on specific replica | All replicas |
| `--parallel N` | Number of parallel operations | 1 |
| `--verify` | Verify after sync | false |
| `--force` | Force operation | false |

**Examples:**

```bash
# Initialize replication
cbob replicate init

# Sync all replicas
cbob replicate sync

# Sync specific replica
cbob replicate sync --replica eu-west

# Check status
cbob replicate status

# Test connectivity
cbob replicate test

# Verify replica
cbob replicate verify --replica us-west
```

### config

Configuration management commands.

```bash
cbob config <subcommand> [options]
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `validate` | Validate current configuration |
| `show` | Display configuration |
| `init` | Initialize configuration interactively |
| `get KEY` | Get specific configuration value |
| `set KEY VALUE` | Set configuration value |

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--file FILE` | Use specific config file | Auto-detected |
| `--format FORMAT` | Output format (text, json, env) | text |
| `--unmask` | Show sensitive values unmasked | false |

**Examples:**

```bash
# Validate configuration
cbob config validate

# Show configuration
cbob config show

# Show with secrets
cbob config show --unmask

# Get specific value
cbob config get CBOB_TARGET_PATH

# Set value
cbob config set CBOB_LOG_LEVEL debug

# Initialize interactively
cbob config init
```

## Examples

### Daily Operations

```bash
# Morning sync
sudo -u postgres cbob sync --parallel 4

# Check sync results
cbob info

# Afternoon validation
sudo -u postgres cbob restore-check

# Evening replication
cbob replicate sync --parallel 2
```

### Disaster Recovery

```bash
# Check replica health
cbob replicate health

# Verify specific replica
cbob replicate verify --replica dr-site

# Restore from replica
cbob postgres stop
sudo -u postgres pgbackrest --stanza=prod restore
cbob postgres start
```

### Maintenance

```bash
# Check disk usage
cbob info --format json | jq '.[] | {cluster: .cluster_id, size: .total_size_bytes}'

# Expire old backups
sudo -u postgres cbob expire --retention-full 7

# Update configuration
cbob config set CBOB_RETENTION_FULL 14
cbob config validate
```

## Environment Variables

CBOB respects these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `CBOB_CONFIG_FILE` | Configuration file path | Auto-detected |
| `CBOB_BASE_PATH` | Base directory for CBOB data | /mnt/volume_cbob |
| `CBOB_TARGET_PATH` | Backup storage path | $CBOB_BASE_PATH/backups |
| `CBOB_LOG_PATH` | Log directory | /var/log/cbob |
| `CBOB_LOG_LEVEL` | Log level | info |
| `CBOB_LOG_FORMAT` | Log format | text |
| `CBOB_DRY_RUN` | Enable dry-run mode | false |
| `CBOB_NO_LOCK` | Disable lock files | false |

## Exit Codes

CBOB uses standard exit codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Permission error |
| 4 | Lock file exists |
| 5 | Dependency missing |

## Tips and Tricks

### Aliases

Add to your shell profile:

```bash
alias cbob-sync='sudo -u postgres cbob sync'
alias cbob-check='sudo -u postgres cbob restore-check'
alias cbob-status='cbob info && cbob replicate status'
```

### Bash Completion

Enable tab completion:

```bash
# Add to ~/.bashrc
complete -W "sync restore-check info expire postgres replicate config help version" cbob
```

### Monitoring Script

```bash
#!/bin/bash
# cbob-monitor.sh
cbob info --format json | jq -r '.[] | 
  "\(.cluster_id): \(.last_backup // "Never") - \(.total_size_bytes | tonumber / 1073741824 | round)GB"'
```

### Parallel Operations

```bash
# Sync and replicate in parallel
cbob sync --parallel 4 &
cbob replicate sync --parallel 2 &
wait
echo "All operations complete"
```