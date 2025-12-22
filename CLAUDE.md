# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Crunchy Bridge Off-site Backup (CBOB) v2.0 is a comprehensive backup management system that syncs AWS S3 backups from Crunchy Bridge to local or alternative cloud storage. It provides automated backup synchronization, validation, multi-cloud replication, and restoration capabilities using pgBackRest.

**Version:** 2.0.0
**Platform:** Debian 11/12 (target), with Docker support
**Language:** Bash

## Project Structure

```text
crunchybridge-offsite-backup/
├── bin/                          # CLI Commands
│   ├── cbob                      # Main CLI entry point (router)
│   ├── cbob-sync                 # Backup synchronization
│   ├── cbob-restore-check        # Backup integrity validation
│   ├── cbob-info                 # Display backup information
│   ├── cbob-expire               # Backup expiration/retention
│   ├── cbob-postgres             # PostgreSQL instance management
│   ├── cbob-replicate            # Multi-region replication
│   ├── cbob-config               # Configuration management
│   ├── cbob_sync                 # Legacy v1 sync script
│   ├── pgbackrest_auto           # Backup validation utility
│   └── slack                     # Slack notification CLI
│
├── lib/                          # Shared Libraries
│   ├── cbob_common.sh            # Core functions (logging, locks, config)
│   ├── cbob_metrics.sh           # Metrics collection and analytics
│   ├── cbob_security.sh          # Input validation and sanitization
│   └── cbob_replication.sh       # Multi-cloud replication support
│
├── tests/                        # Test Suite
│   ├── test_common.sh            # Unit tests for common functions
│   ├── test_integration.sh       # Integration tests
│   ├── test_performance.sh       # Performance tests
│   ├── test_replication.sh       # Replication tests
│   ├── e2e-test.sh               # End-to-end tests
│   └── docker-compose.test.yml   # Test Docker environment
│
├── docs/                         # Documentation
│   ├── ARCHITECTURE.md           # System architecture
│   ├── CLI.md                    # Command-line reference
│   ├── CONFIGURATION.md          # Configuration options
│   ├── INSTALLATION.md           # Installation guide
│   ├── DOCKER.md                 # Docker usage
│   ├── MONITORING.md             # Monitoring & metrics
│   ├── TROUBLESHOOTING.md        # Common issues
│   └── ...                       # Additional docs
│
├── Dockerfile                    # Docker image (Debian 11)
├── docker-compose.yml            # Container orchestration
├── docker-entrypoint.sh          # Docker entry point
├── setup.sh                      # Full server setup (interactive/non-interactive)
├── install.sh                    # Simple CLI installation
└── .env.example                  # Configuration template
```

## Key Architecture

### CLI Layer (`bin/`)

- **cbob** - Main entry point that routes to subcommands
- **cbob-sync** - Syncs from Crunchy Bridge S3 to local/S3-compatible storage
- **cbob-restore-check** - Validates backup integrity using pgbackrest_auto
- **cbob-info** - Shows stanza information and backup status
- **cbob-expire** - Manages backup retention and cleanup
- **cbob-postgres** - Start/stop/status of PostgreSQL instances
- **cbob-replicate** - Multi-cloud replication (AWS, Azure, GCP, DO, MinIO)
- **cbob-config** - Configuration validation and management

### Library Layer (`lib/`)

- **cbob_common.sh** - Logging (text/JSON), configuration loading, lock management, notifications
- **cbob_metrics.sh** - Performance metrics, storage tracking, audit logging
- **cbob_security.sh** - Input validation, path sanitization, permission checks
- **cbob_replication.sh** - Provider abstraction for multi-cloud support

### Installation Scripts

- **install.sh** - Lightweight installation for CLI only (v2 or legacy mode)
- **setup.sh** - Complete server setup with pgBackRest, PostgreSQL, cron jobs

## Common Commands

### Installation

```bash
# Simple CLI installation (v2)
sudo ./install.sh

# Legacy installation
sudo ./install.sh --legacy

# Full server setup (interactive)
./setup.sh

# Non-interactive setup
CBOB_NONINTERACTIVE=true \
CBOB_CRUNCHY_API_KEY=cbkey_xxx \
CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2 \
CBOB_PG_VERSION=17 \
./setup.sh
```

### CLI Usage (v2)

```bash
# Sync operations
cbob sync                        # Sync all configured clusters
cbob sync --dry-run              # Test without changes
cbob sync --parallel 4           # Parallel workers
cbob sync --stanza <name>        # Sync specific stanza

# Backup validation
cbob restore-check               # Check all backups
cbob restore-check --stanza <n>  # Check specific stanza

# Information
cbob info                        # Show backup information
cbob info --stanza <name>        # Specific stanza info

# PostgreSQL management
cbob postgres start              # Start all instances
cbob postgres stop               # Stop all instances
cbob postgres status             # Show status

# Configuration
cbob config validate             # Validate configuration
cbob config show                 # Show config (masked secrets)
cbob config init                 # Interactive setup

# Replication
cbob replicate                   # Replicate to configured providers
cbob replicate --provider aws    # Specific provider

# Expiration
cbob expire                      # Expire old backups
```

### Docker Usage

```bash
# Build and run
docker-compose up -d

# Run sync manually
docker-compose exec cbob cbob sync

# View logs
docker-compose logs -f cbob
```

### Testing

```bash
# Unit tests
bash tests/test_common.sh

# All tests
bash tests/test_integration.sh
bash tests/test_performance.sh
bash tests/test_replication.sh
bash tests/e2e-test.sh

# Debug mode
CBOB_LOG_LEVEL=debug cbob sync

# JSON logging
CBOB_LOG_FORMAT=json cbob sync
```

## Configuration

Configuration is loaded from (in order):

1. `$CBOB_CONFIG_FILE` environment variable
2. `~/.cb_offsite_backup`
3. `/usr/local/etc/cb_offsite_backup`
4. `/etc/cb_offsite_backup`

### Required Variables

- `CBOB_CRUNCHY_API_KEY` - Crunchy Bridge API key
- `CBOB_CRUNCHY_CLUSTERS` - Comma-separated cluster IDs

### Destination Options

- `CBOB_TARGET_PATH` - Local storage path, OR
- `CBOB_DEST_TYPE` - s3, do_spaces, hetzner, minio
- `CBOB_DEST_BUCKET` - Bucket name
- `CBOB_DEST_ACCESS_KEY` / `CBOB_DEST_SECRET_KEY` - Credentials
- `CBOB_DEST_ENDPOINT` - S3-compatible endpoint
- `CBOB_DEST_REGION` - Region

### PostgreSQL

- `CBOB_PG_VERSION` - PostgreSQL version (17 or 18)
- `CBOB_BASE_PATH` - Base path for all data (default: /var/lib/cbob)

### Monitoring

- `CBOB_SLACK_CLI_TOKEN` - Slack token for notifications
- `CBOB_SLACK_CHANNEL` - Slack channel
- `CBOB_SYNC_HEARTBEAT_URL` - Heartbeat URL for sync
- `CBOB_RESTORE_HEARTBEAT_URL` - Heartbeat URL for restore

### Retention and Performance

- `CBOB_RETENTION_FULL` - Number of full backups to retain
- `CBOB_SYNC_PARALLEL` - Parallel sync workers
- `CBOB_RESTORE_PARALLEL` - Parallel restore workers
- `CBOB_LOG_LEVEL` - debug, info, warning, error
- `CBOB_LOG_FORMAT` - text, json

## Runtime Directory Structure

```text
$CBOB_BASE_PATH/
├── crunchybridge/      # Synced backup repository
│   ├── archive/        # WAL archives
│   └── backup/         # Full/incremental backups
├── restores/           # Temporary restore validation
├── postgresql/<ver>/   # PostgreSQL data directories per cluster
└── log/               # All logs
    ├── cbob/          # CBOB script logs
    ├── pgbackrest/    # pgBackRest logs
    └── postgresql/    # PostgreSQL logs
```

## Implementation Details

1. **User Requirements**: cbob commands run as `postgres` user
2. **Locking**: Uses flock to prevent concurrent executions
3. **Stanza Management**: Each cluster has its own pgBackRest stanza
4. **Port Assignment**: PostgreSQL instances start at 5432, incrementing per cluster
5. **Cron Jobs**: Daily sync (6AM UTC), restore check (6PM UTC)
6. **Multi-Cloud**: Supports AWS S3, Azure Blob, GCP Storage, DigitalOcean Spaces, MinIO
7. **Metrics**: Performance tracking stored in JSONL format
8. **Security**: Input validation, path sanitization, audit logging

## Error Handling

- Fail-fast with `set -e`
- Comprehensive logging to syslog and file
- Slack notifications for errors/warnings
- Lock file cleanup on errors
- Heartbeat URL notifications
- Retry mechanisms with exponential backoff

## Dependencies

- Bash 3.2+
- pgBackRest
- AWS CLI v2
- PostgreSQL 17 or 18
- jq
- curl
- flock
