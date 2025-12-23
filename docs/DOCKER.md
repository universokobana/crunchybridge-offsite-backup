# CBOB Docker Guide

This guide covers running CBOB in Docker containers with PostgreSQL 18 support.

## Quick Start

### 1. Build the Docker Image

```bash
docker build -t cbob:latest .
```

### 2. Run with Docker Compose

```bash
# Copy and edit environment file
cp .env.example .env
# Edit .env with your configuration

# Start services
docker-compose up -d

# View logs
docker-compose logs -f
```

### 3. Run Standalone Container

```bash
docker run -d \
  --name cbob \
  -e CBOB_CRUNCHY_API_KEY=your-api-key \
  -e CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2 \
  -v cbob-data:/data \
  -v cbob-logs:/var/log/cbob \
  cbob:latest
```

## Complete Setup and Testing Guide

This section provides a step-by-step guide to set up and test CBOB in a Docker container.

### Step 1: Start a Debian Container

```bash
# Start a Debian container for testing
docker run -dit --name cbob-test \
  -e DEBIAN_FRONTEND=noninteractive \
  debian:12 bash

# Access the container
docker exec -it cbob-test bash
```

### Step 2: Install Dependencies and Clone Project

```bash
# Update and install git
apt update && apt install -y git

# Clone the project
cd /root
git clone https://github.com/kobana/crunchybridge-offsite-backup.git
cd crunchybridge-offsite-backup
```

### Step 3: Run Full Setup

```bash
# Run the setup script (non-interactive for testing)
./setup.sh
```

The setup will install:
- PostgreSQL 18 (client and server)
- pgBackRest
- AWS CLI v2
- pgbackrest_auto
- All CBOB scripts and libraries

### Step 4: Configure CBOB

Edit the configuration file:

```bash
nano /usr/local/etc/cb_offsite_backup
```

#### For Local Storage:
```bash
CBOB_CRUNCHY_API_KEY=your-crunchy-api-key
CBOB_CRUNCHY_CLUSTERS=your-cluster-id
CBOB_TARGET_PATH=/var/lib/cbob/backups
CBOB_PG_VERSION=18
```

#### For S3-Compatible Storage (DigitalOcean Spaces):
```bash
CBOB_CRUNCHY_API_KEY=your-crunchy-api-key
CBOB_CRUNCHY_CLUSTERS=your-cluster-id
CBOB_DEST_TYPE=s3
CBOB_DEST_ENDPOINT=https://ams3.digitaloceanspaces.com
CBOB_DEST_BUCKET=your-bucket-name
CBOB_DEST_ACCESS_KEY=your-access-key
CBOB_DEST_SECRET_KEY=your-secret-key
CBOB_DEST_REGION=ams3
CBOB_DEST_PREFIX=/backup-replica
CBOB_PG_VERSION=18
```

### Step 5: Test Sync

```bash
# Run sync as postgres user
sudo -u postgres cbob sync

# Check logs
tail -f /var/log/cbob/cbob_sync.log
```

### Step 6: Verify Backup in Destination

For S3 destination:
```bash
# Source config and test
. /usr/local/etc/cb_offsite_backup
export AWS_ACCESS_KEY_ID="$CBOB_DEST_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$CBOB_DEST_SECRET_KEY"

# List synced files
aws --endpoint-url "$CBOB_DEST_ENDPOINT" s3 ls "s3://$CBOB_DEST_BUCKET/$CBOB_DEST_PREFIX/" --recursive | wc -l
```

### Step 7: Test Restore-Check

```bash
# Run restore check
sudo -u postgres cbob restore-check

# Or with pgbackrest directly
sudo -u postgres pgbackrest --stanza=your-stanza-id info
```

### Step 8: Test Full Restore

```bash
# Create restore directory
mkdir -p /var/lib/cbob/restores/test

# Run restore
sudo -u postgres pgbackrest \
  --stanza=your-stanza-id \
  --pg1-path=/var/lib/cbob/restores/test \
  --type=immediate \
  restore

# Verify restored files
ls -la /var/lib/cbob/restores/test/
du -sh /var/lib/cbob/restores/test/
```

### Cleanup Test Container

```bash
docker stop cbob-test
docker rm cbob-test
```

## Configuration

### Environment Variables

All CBOB configuration can be set via environment variables:

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `CBOB_CRUNCHY_API_KEY` | Crunchy Bridge API key | Yes | - |
| `CBOB_CRUNCHY_CLUSTERS` | Comma-separated cluster IDs | Yes | - |
| `CBOB_DEST_TYPE` | Destination type (local/s3) | No | local |
| `CBOB_TARGET_PATH` | Local backup path | No | /data/backups |
| `CBOB_DEST_ENDPOINT` | S3 endpoint URL | If s3 | - |
| `CBOB_DEST_BUCKET` | S3 bucket name | If s3 | - |
| `CBOB_DEST_ACCESS_KEY` | S3 access key | If s3 | - |
| `CBOB_DEST_SECRET_KEY` | S3 secret key | If s3 | - |
| `CBOB_DEST_REGION` | S3 region | No | us-east-1 |
| `CBOB_RETENTION_FULL` | Number of full backups to retain | No | 1 |
| `CBOB_DRY_RUN` | Enable dry-run mode | No | false |
| `CBOB_SLACK_CLI_TOKEN` | Slack token for notifications | No | - |
| `CBOB_SLACK_CHANNEL` | Slack channel | No | #backup-log |
| `CBOB_LOG_LEVEL` | Log level (debug/info/warning/error) | No | info |
| `CBOB_LOG_FORMAT` | Log format (text/json) | No | text |

### Volumes

The following volumes should be mounted:

- `/data` - Backup data storage (for local destination)
- `/var/log/cbob` - Application logs
- `/etc/cbob` - Configuration files

## Destination Types

### Local Storage (Default)

Store backups on local filesystem:

```bash
docker run -d \
  --name cbob \
  -e CBOB_DEST_TYPE=local \
  -e CBOB_TARGET_PATH=/data/backups \
  -v cbob-data:/data \
  cbob:latest
```

### S3-Compatible Storage

Store backups on S3-compatible storage (Digital Ocean Spaces, Hetzner, MinIO, etc.):

```bash
docker run -d \
  --name cbob \
  -e CBOB_DEST_TYPE=s3 \
  -e CBOB_DEST_ENDPOINT=https://fra1.digitaloceanspaces.com \
  -e CBOB_DEST_BUCKET=my-cbob-backups \
  -e CBOB_DEST_ACCESS_KEY=your-access-key \
  -e CBOB_DEST_SECRET_KEY=your-secret-key \
  -e CBOB_DEST_REGION=fra1 \
  cbob:latest
```

## Running Modes

### Cron Mode (Default)

Runs scheduled tasks (sync at 6 AM UTC, restore-check at 6 PM UTC):

```bash
docker run -d cbob:latest cron
```

### One-off Commands

Run specific CBOB commands:

```bash
# Sync backups
docker run --rm cbob:latest sync

# Sync with dry-run
docker run --rm cbob:latest sync --dry-run

# Check restore
docker run --rm cbob:latest restore-check

# Show info
docker run --rm cbob:latest info

# Validate configuration
docker run --rm cbob:latest config validate
```

## Resource Limits

Default resource limits in docker-compose.yml:

- CPU: 2 cores limit, 0.5 cores reserved
- Memory: 2GB limit, 512MB reserved

Adjust these based on your workload:

```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 4G
```

## Monitoring

### Log Access

```bash
# View logs from container
docker exec cbob tail -f /var/log/cbob/cbob_sync.log

# View cron log
docker exec cbob tail -f /var/log/cbob/cron.log
```

### Heartbeat URLs

Configure heartbeat URLs for external monitoring:

```bash
docker run -d \
  -e CBOB_SYNC_HEARTBEAT_URL=https://monitoring.example.com/sync \
  -e CBOB_RESTORE_HEARTBEAT_URL=https://monitoring.example.com/restore \
  cbob:latest
```

## Security Considerations

1. **Network Isolation**: Use Docker networks to isolate CBOB:
   ```bash
   docker network create cbob-net
   docker run --network cbob-net ...
   ```

2. **Read-only Root Filesystem**: For additional security:
   ```bash
   docker run --read-only \
     --tmpfs /tmp \
     --tmpfs /run \
     cbob:latest
   ```

3. **Non-root User**: The container runs as `postgres` user by default.

4. **Secrets Management**: Use Docker secrets for sensitive data:
   ```bash
   echo "your-api-key" | docker secret create cbob_api_key -
   ```

## Troubleshooting

### Container Won't Start

Check logs:
```bash
docker logs cbob
```

Common issues:
- Missing required environment variables
- Invalid API key
- Network connectivity issues

### High Memory Usage

Monitor memory:
```bash
docker stats cbob
```

Solutions:
- Increase memory limits
- Reduce parallel operations
- Enable swap accounting

### Backup Sync Fails

1. Check configuration:
   ```bash
   docker exec cbob cbob config validate
   ```

2. Test connectivity:
   ```bash
   docker exec cbob curl -I https://api.crunchybridge.com
   ```

3. Review sync logs:
   ```bash
   docker exec cbob cat /var/log/cbob/cbob_sync.log
   ```

### S3 Connection Issues

1. Test S3 connectivity:
   ```bash
   docker exec cbob aws --endpoint-url $CBOB_DEST_ENDPOINT s3 ls s3://$CBOB_DEST_BUCKET/
   ```

2. Verify credentials and endpoint URL

## Advanced Usage

### Custom Entrypoint

Override the entrypoint for debugging:

```bash
docker run -it --entrypoint /bin/bash cbob:latest
```

### Volume Backup

Backup Docker volumes:

```bash
# Backup data volume
docker run --rm \
  -v cbob-data:/source:ro \
  -v $(pwd):/backup \
  alpine tar czf /backup/cbob-data-backup.tar.gz -C /source .
```

### Multi-stage Sync

Run parallel syncs with multiple containers:

```bash
# Container 1: Clusters 1-5
docker run -d \
  --name cbob-1 \
  -e CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2,cluster3,cluster4,cluster5 \
  cbob:latest sync

# Container 2: Clusters 6-10
docker run -d \
  --name cbob-2 \
  -e CBOB_CRUNCHY_CLUSTERS=cluster6,cluster7,cluster8,cluster9,cluster10 \
  cbob:latest sync
```
