# CBOB Installation Guide

This guide covers all installation methods for CBOB v2 with PostgreSQL 18 support.

## Table of Contents
- [Requirements](#requirements)
- [Installation Methods](#installation-methods)
  - [Quick Install (Sync Only)](#quick-install-sync-only)
  - [Full Setup (Complete Solution)](#full-setup-complete-solution)
  - [Docker Installation](#docker-installation)
  - [Manual Installation](#manual-installation)
- [Post-Installation](#post-installation)
- [Verification](#verification)
- [Uninstallation](#uninstallation)

## Requirements

### System Requirements
- **OS**: Debian 11+, Ubuntu 20.04+, or compatible Linux distribution
- **CPU**: 2+ cores recommended
- **Memory**: 2GB minimum, 4GB recommended
- **Storage**: Varies based on backup size (20x database size recommended)
- **Network**: Stable internet connection for S3 sync

### Software Dependencies
- PostgreSQL 18 client tools
- pgBackRest
- AWS CLI v2
- curl, jq, unzip
- Docker (optional, for containerized deployment)

## Installation Methods

### Quick Install (Sync Only)

For basic backup synchronization without full backup management:

```bash
# Clone the repository
git clone https://github.com/kobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup

# Run installation script (v2 architecture - default)
sudo ./install.sh

# Or install legacy scripts only
sudo ./install.sh --legacy

# Configure
sudo cp /usr/local/etc/cb_offsite_backup.example /usr/local/etc/cb_offsite_backup
sudo nano /usr/local/etc/cb_offsite_backup
```

**Install Options:**
| Option | Description |
|--------|-------------|
| `--v2` | Install v2 architecture with unified CLI (default) |
| `--legacy` | Install legacy scripts only for backward compatibility |
| `--help` | Show help message |

This installs:
- `cbob` CLI tool and subcommands (`cbob-sync`, `cbob-restore-check`, etc.)
- Library files in `/usr/local/lib/cbob/`
- Configuration files
- Cron job for daily sync
- Log rotation

### Full Setup (Complete Solution)

For complete backup solution with restore capabilities:

```bash
# Clone the repository
git clone https://github.com/kobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup

# Run setup script (interactive)
sudo ./setup.sh
```

The setup script will:
1. Install all dependencies (PostgreSQL 18, pgBackRest, AWS CLI)
2. Create system users and directories
3. Configure pgBackRest
4. Set up PostgreSQL instances for restore testing
5. Configure automated backups and checks

#### Non-Interactive Setup (Docker/CI)

For automated deployments, use environment variables:

```bash
# Set required environment variables
export CBOB_NONINTERACTIVE=true
export CBOB_PG_VERSION=18
export CBOB_CRUNCHY_API_KEY=your-api-key
export CBOB_CRUNCHY_CLUSTERS=cluster-id-1,cluster-id-2
export CBOB_BASE_PATH=/var/lib/cbob

# For S3-compatible storage destination
export CBOB_DEST_TYPE=s3
export CBOB_DEST_ENDPOINT=https://ams3.digitaloceanspaces.com
export CBOB_DEST_BUCKET=my-backups
export CBOB_DEST_ACCESS_KEY=your-access-key
export CBOB_DEST_SECRET_KEY=your-secret-key
export CBOB_DEST_REGION=ams3
export CBOB_DEST_PREFIX=/backup-replica

# Run setup
./setup.sh
```

**Non-Interactive Environment Variables:**

| Variable | Description | Required |
|----------|-------------|----------|
| `CBOB_NONINTERACTIVE` | Enable non-interactive mode | Yes |
| `CBOB_PG_VERSION` | PostgreSQL version (18) | Yes |
| `CBOB_CRUNCHY_API_KEY` | Crunchy Bridge API key | Yes |
| `CBOB_CRUNCHY_CLUSTERS` | Comma-separated cluster IDs | Yes |
| `CBOB_BASE_PATH` | Base path for CBOB data | No (default: /var/lib/cbob) |
| `CBOB_DEST_TYPE` | Destination type: `local` or `s3` | No (default: local) |
| `CBOB_DEST_ENDPOINT` | S3 endpoint URL | If s3 |
| `CBOB_DEST_BUCKET` | S3 bucket name | If s3 |
| `CBOB_DEST_ACCESS_KEY` | S3 access key | If s3 |
| `CBOB_DEST_SECRET_KEY` | S3 secret key | If s3 |
| `CBOB_DEST_REGION` | S3 region | No (default: us-east-1) |
| `CBOB_DEST_PREFIX` | S3 path prefix | No |

**Note:** The setup script automatically detects system architecture (x86_64/ARM64) and downloads the correct AWS CLI version.

### Docker Installation

Using Docker Compose:

```bash
# Clone the repository
git clone https://github.com/kobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup

# Copy and configure environment
cp .env.example .env
nano .env  # Add your configuration

# Build and start
docker-compose up -d

# Check status
docker-compose ps
docker-compose logs
```

Using standalone Docker:

```bash
# Build image
docker build -t cbob:latest .

# Run container with local storage
docker run -d \
  --name cbob \
  -e CBOB_CRUNCHY_API_KEY=your-api-key \
  -e CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2 \
  -v /path/to/backups:/data \
  cbob:latest

# Run container with S3 storage
docker run -d \
  --name cbob \
  -e CBOB_CRUNCHY_API_KEY=your-api-key \
  -e CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2 \
  -e CBOB_DEST_TYPE=s3 \
  -e CBOB_DEST_ENDPOINT=https://fra1.digitaloceanspaces.com \
  -e CBOB_DEST_BUCKET=my-backups \
  -e CBOB_DEST_ACCESS_KEY=your-key \
  -e CBOB_DEST_SECRET_KEY=your-secret \
  cbob:latest
```

### Manual Installation

For custom installations:

1. **Install Dependencies**:
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install basic tools
sudo apt install -y curl wget jq unzip git

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Add PostgreSQL repository
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update

# Install PostgreSQL 18 client and pgBackRest
sudo apt install -y postgresql-client-18 pgbackrest
```

2. **Install CBOB**:
```bash
# Copy binaries
sudo cp -r bin/* /usr/local/bin/
sudo chmod +x /usr/local/bin/cbob*

# Copy libraries
sudo mkdir -p /usr/local/lib/cbob
sudo cp -r lib/* /usr/local/lib/cbob/

# Create directories
sudo mkdir -p /etc/cbob /var/log/cbob /var/lib/cbob

# Set permissions
sudo chown -R postgres:postgres /var/log/cbob /var/lib/cbob
```

3. **Configure**:
```bash
# Create configuration
sudo cp etc/cb_offsite_backup_example.env /etc/cbob/config
sudo nano /etc/cbob/config

# Set up cron jobs
echo "0 6 * * * postgres /usr/local/bin/cbob sync" | sudo tee /etc/cron.d/cbob_sync
echo "0 18 * * * postgres /usr/local/bin/cbob restore-check" | sudo tee /etc/cron.d/cbob_restore_check
```

## Post-Installation

### 1. Configure CBOB

Edit the configuration file with your settings:

```bash
sudo nano /usr/local/etc/cb_offsite_backup
# or
sudo nano /etc/cbob/config
```

#### Local Storage Configuration
```bash
CBOB_CRUNCHY_API_KEY=your-api-key-here
CBOB_CRUNCHY_CLUSTERS=cluster-id-1,cluster-id-2
CBOB_TARGET_PATH=/path/to/backup/storage
```

#### S3-Compatible Storage Configuration
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

### 2. Initialize pgBackRest

For full setup, initialize pgBackRest configuration:

```bash
sudo -u postgres cbob config validate
sudo -u postgres cbob postgres initdb
```

### 3. Start Services

For Docker:
```bash
docker-compose up -d
```

## Verification

### 1. Check Installation

```bash
# Check CLI
cbob version

# Check configuration
cbob config validate

# List available commands
cbob help
```

### 2. Test Sync

```bash
# Dry run
sudo -u postgres cbob sync --dry-run

# Check logs
tail -f /var/log/cbob/cbob_sync.log
```

### 3. Verify Cron Jobs

```bash
# Check cron configuration
sudo crontab -l -u postgres
ls -la /etc/cron.d/cbob*
```

## Uninstallation

### Remove CBOB

```bash
# Stop services
docker-compose down

# Remove files
sudo rm -rf /usr/local/bin/cbob*
sudo rm -rf /usr/local/lib/cbob
sudo rm -rf /etc/cbob
sudo rm -rf /var/log/cbob
sudo rm -rf /var/lib/cbob

# Remove cron jobs
sudo rm -f /etc/cron.d/cbob*
```

### Clean Docker

```bash
# Remove containers and volumes
docker-compose down -v

# Remove images
docker rmi cbob:latest
```

## Troubleshooting Installation

### Permission Issues

```bash
# Fix ownership
sudo chown -R postgres:postgres /var/log/cbob /var/lib/cbob

# Fix permissions
sudo chmod 755 /usr/local/bin/cbob*
sudo chmod 644 /usr/local/lib/cbob/*.sh
```

### Missing Dependencies

```bash
# Check what's missing
cbob config validate

# Install missing packages
sudo apt install -y [missing-package]
```

### Configuration Issues

```bash
# Validate configuration
cbob config validate

# Check environment variables
env | grep CBOB
```

## Next Steps

- [Quick Start Guide](QUICKSTART.md) - Get started with your first backup
- [Configuration Guide](CONFIGURATION.md) - Detailed configuration options
- [CLI Reference](CLI.md) - Learn all CLI commands
- [Docker Guide](DOCKER.md) - Docker-specific configurations
