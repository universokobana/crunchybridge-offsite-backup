#!/bin/bash

# Author: Rafael Lima (https://github.com/rafaelp)
# Updated for v2.1 architecture with non-interactive mode support
# Requires: pgBackRest 2.58+ for native STS token refresh

# terminate script as soon as any command fails
set -e

# Minimum required pgBackRest version
MIN_PGBACKREST_VERSION="2.58"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function info(){
    msg="$1"
    echo -e "${GREEN}$(date "+%F %T") INFO:${NC} $msg"
    logger -p user.notice -t "$(basename "$0")" "$msg" 2>/dev/null || true
}

function warning(){
    msg="$1"
    echo -e "${YELLOW}$(date "+%F %T") WARNING:${NC} $msg"
    logger -p user.notice -t "$(basename "$0")" "$msg" 2>/dev/null || true
}

function error(){
    msg="$1"
    echo -e "${RED}$(date "+%F %T") ERROR:${NC} $msg"
    logger -p user.error -t "$(basename "$0")" "$msg" 2>/dev/null || true
    exit 1
}

# Check pgBackRest version meets minimum requirement
function check_pgbackrest_version(){
    if ! command -v pgbackrest &> /dev/null; then
        warning "pgBackRest not found after installation"
        return 1
    fi

    local version=$(pgbackrest version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major=$(echo "$version" | cut -d. -f1)
    local minor=$(echo "$version" | cut -d. -f2)
    local min_major=$(echo "$MIN_PGBACKREST_VERSION" | cut -d. -f1)
    local min_minor=$(echo "$MIN_PGBACKREST_VERSION" | cut -d. -f2)

    if [ "$major" -lt "$min_major" ] || ([ "$major" -eq "$min_major" ] && [ "$minor" -lt "$min_minor" ]); then
        warning "pgBackRest $version is installed, but $MIN_PGBACKREST_VERSION+ is required for native STS token refresh."
        warning "Please upgrade: apt update && apt install pgbackrest"
        return 1
    fi

    info "pgBackRest $version detected (>= $MIN_PGBACKREST_VERSION required) ✓"
    return 0
}

# Check for non-interactive mode
CBOB_NONINTERACTIVE="${CBOB_NONINTERACTIVE:-false}"

# Load config file if exists to determine the default values
if [ -n "${CBOB_CONFIG_FILE}" ]; then
    CONFIG_FILE="$CBOB_CONFIG_FILE"
elif [ -r "${HOME}/.cb_offsite_backup" ] && [ -f "${HOME}/.cb_offsite_backup" ]; then
    CONFIG_FILE="${HOME}/.cb_offsite_backup"
elif [ -r "/usr/local/etc/cb_offsite_backup" ] && [ -f "/usr/local/etc/cb_offsite_backup" ]; then
    CONFIG_FILE="/usr/local/etc/cb_offsite_backup"
elif [ -r "/etc/cb_offsite_backup" ] && [ -f "/etc/cb_offsite_backup" ]; then
    CONFIG_FILE="/etc/cb_offsite_backup"
fi

if [ -f "$CONFIG_FILE" ]; then
    info "Reading existing config file $CONFIG_FILE"
    unamestr=$(uname)
    if [ "$unamestr" = 'Linux' ]; then
        export $(grep -v '^#' "$CONFIG_FILE" | xargs -d '\n')
    elif [ "$unamestr" = 'FreeBSD' ] || [ "$unamestr" = 'Darwin' ]; then
        export $(grep -v '^#' "$CONFIG_FILE" | xargs -0)
    fi
fi

# Function to prompt or use environment variable
prompt_or_env() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local required="${4:-false}"

    # Get current value from environment
    local current_value="${!var_name:-$default_value}"

    if [ "$CBOB_NONINTERACTIVE" = "true" ]; then
        # Non-interactive mode: use environment variable or default
        if [ -z "$current_value" ] && [ "$required" = "true" ]; then
            error "$var_name is required but not set"
        fi
        eval "$var_name='$current_value'"
    else
        # Interactive mode: prompt user
        read -re -p "$prompt_text" -i "$current_value" "$var_name"
        current_value="${!var_name}"
        if [ -z "$current_value" ] && [ "$required" = "true" ]; then
            error "$var_name cannot be empty"
        fi
    fi
}

show_help() {
    cat << EOF
CBOB Setup Script

Usage: sudo $0 [options]

Options:
    --non-interactive    Run without prompts (requires environment variables)
    --skip-deps          Skip dependency installation
    --skip-pg-init       Skip PostgreSQL cluster initialization
    --help, -h           Show this help message

Environment Variables (for non-interactive mode):
    CBOB_PG_VERSION          PostgreSQL version (default: 18)
    CBOB_CRUNCHY_API_KEY     Crunchy Bridge API key (required)
    CBOB_CRUNCHY_CLUSTERS    Comma-separated cluster IDs (required)
    CBOB_RETENTION_FULL      Full backup retention count (default: 1)
    CBOB_BASE_PATH           Base path for CBOB data (default: /mnt/volume_cbob)
    CBOB_SLACK_CLI_TOKEN     Slack token for notifications (optional)
    CBOB_SLACK_CHANNEL       Slack channel (default: #backup-log)
    CBOB_SYNC_HEARTBEAT_URL  Heartbeat URL for sync (optional)
    CBOB_RESTORE_HEARTBEAT_URL  Heartbeat URL for restore (optional)

    # S3 Destination Configuration (optional)
    CBOB_DEST_TYPE           Destination type: local or s3 (default: local)
    CBOB_DEST_ENDPOINT       S3 endpoint URL (required if CBOB_DEST_TYPE=s3)
    CBOB_DEST_BUCKET         S3 bucket name (required if CBOB_DEST_TYPE=s3)
    CBOB_DEST_ACCESS_KEY     S3 access key (required if CBOB_DEST_TYPE=s3)
    CBOB_DEST_SECRET_KEY     S3 secret key (required if CBOB_DEST_TYPE=s3)
    CBOB_DEST_REGION         S3 region (default: us-east-1)
    CBOB_DEST_PREFIX         S3 path prefix (optional)

Examples:
    # Interactive setup
    sudo ./setup.sh

    # Non-interactive setup
    sudo CBOB_NONINTERACTIVE=true \\
         CBOB_CRUNCHY_API_KEY=your-api-key \\
         CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2 \\
         ./setup.sh

    # Non-interactive with S3 destination
    sudo CBOB_NONINTERACTIVE=true \\
         CBOB_CRUNCHY_API_KEY=your-api-key \\
         CBOB_CRUNCHY_CLUSTERS=cluster1 \\
         CBOB_DEST_TYPE=s3 \\
         CBOB_DEST_ENDPOINT=https://ams3.digitaloceanspaces.com \\
         CBOB_DEST_BUCKET=my-backups \\
         CBOB_DEST_ACCESS_KEY=access-key \\
         CBOB_DEST_SECRET_KEY=secret-key \\
         ./setup.sh

EOF
}

# Parse command line arguments
SKIP_DEPS=false
SKIP_PG_INIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive)
            CBOB_NONINTERACTIVE=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-pg-init)
            SKIP_PG_INIT=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Get configuration values
info "Gathering configuration..."

prompt_or_env "CBOB_PG_VERSION" "Which version of PostgreSQL do you use: " "18"
if [ "$CBOB_PG_VERSION" != "18" ]; then
    error "Invalid version, choose 18"
fi

prompt_or_env "CBOB_CRUNCHY_API_KEY" "Please inform your Crunchy Bridge API Key: " "" "true"

if [ "$CBOB_NONINTERACTIVE" != "true" ]; then
    prompt_or_env "CBOB_SLACK_CLI_TOKEN" "Please inform your Slack CLI Token (leave blank if will not use): " ""
    if [ -n "$CBOB_SLACK_CLI_TOKEN" ]; then
        prompt_or_env "CBOB_SLACK_CHANNEL" "Slack channel to send logs: " "#backup-log"
    fi
fi

prompt_or_env "CBOB_CRUNCHY_CLUSTERS" "Please paste the list of cluster ids separated by comma: " "" "true"

prompt_or_env "CBOB_RETENTION_FULL" "How many full backups you would like to retain: " "1"

prompt_or_env "CBOB_BASE_PATH" "Path where Crunchy Bridge Offsite Backup data will reside: " "/mnt/volume_cbob"
info "Crunchy Bridge Offsite Backup repository path: $CBOB_BASE_PATH"

if [ "$CBOB_NONINTERACTIVE" != "true" ]; then
    prompt_or_env "CBOB_SYNC_HEARTBEAT_URL" "Heartbeat URL for Sync (leave blank if not used): " ""
    prompt_or_env "CBOB_RESTORE_HEARTBEAT_URL" "Heartbeat URL for Restore (leave blank if not used): " ""

    # S3 destination configuration
    prompt_or_env "CBOB_DEST_TYPE" "Destination type (local or s3): " "local"
    if [ "$CBOB_DEST_TYPE" = "s3" ]; then
        prompt_or_env "CBOB_DEST_ENDPOINT" "S3 endpoint URL: " "" "true"
        prompt_or_env "CBOB_DEST_BUCKET" "S3 bucket name: " "" "true"
        prompt_or_env "CBOB_DEST_ACCESS_KEY" "S3 access key: " "" "true"
        prompt_or_env "CBOB_DEST_SECRET_KEY" "S3 secret key: " "" "true"
        prompt_or_env "CBOB_DEST_REGION" "S3 region: " "us-east-1"
        prompt_or_env "CBOB_DEST_PREFIX" "S3 path prefix (optional): " ""
    fi
fi

# Install dependencies
if [ "$SKIP_DEPS" != "true" ]; then
    info "Updating and upgrading packages"
    apt update && apt upgrade -y && apt autoremove -y

    info "Installing dependencies"
    apt install -y software-properties-common apt-transport-https wget curl ca-certificates gnupg jq unzip lsb-release

    # Install sendemail only if available
    apt install -y sendemail 2>/dev/null || warning "sendemail not available, skipping"

    info "Installing AWS CLI v2"
    if ! command -v aws &> /dev/null || ! aws --version 2>&1 | grep -q "aws-cli/2"; then
        # Detect architecture and download correct version
        ARCH=$(uname -m)
        if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
            AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
        else
            AWS_CLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
        fi
        info "  Downloading AWS CLI for $ARCH"
        curl -s "$AWS_CLI_URL" -o "awscliv2.zip"
        unzip -q awscliv2.zip
        ./aws/install --update
        rm -Rf ./aws awscliv2.zip
    else
        info "AWS CLI v2 already installed"
    fi

    info "Adding PostgreSQL repository"
    if [ ! -f /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg ]; then
        info "  Downloading PostgreSQL GPG key"
        curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
    fi
    if [ ! -f /etc/apt/sources.list.d/pgdg.list ]; then
        info "  Adding repo to sources.list"
        echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
        apt update
    fi

    info "Installing PostgreSQL $CBOB_PG_VERSION and pgBackRest"
    apt install -y postgresql-$CBOB_PG_VERSION postgresql-client-$CBOB_PG_VERSION pgbackrest

    # Verify pgBackRest version
    check_pgbackrest_version || warning "pgBackRest version check failed - STS token refresh may not work"

    # Install pgaudit if available
    apt install -y postgresql-$CBOB_PG_VERSION-pgaudit 2>/dev/null || warning "pgaudit not available, skipping"
fi

# Create admin user (only in interactive mode and if not exists)
if [ "$CBOB_NONINTERACTIVE" != "true" ]; then
    info "Creating admin user with sudo privileges"
    if id "admin" &>/dev/null; then
        info "  User admin already exists!"
    else
        info "Choose the password for admin user"
        adduser --gecos "" admin
        usermod -aG sudo admin
        if [ -d ~/.ssh ]; then
            cp -r ~/.ssh /home/admin
        fi
        echo "export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8" >> /home/admin/.bashrc
        chown -R admin:admin /home/admin
    fi
fi

info "Creating pgBackRest config files & directories"
mkdir -p -m 770 /var/log/pgbackrest
chown postgres:postgres /var/log/pgbackrest
mkdir -p /etc/pgbackrest
chown postgres:postgres -R /etc/pgbackrest
mkdir -p /tmp/pgbackrest
chown postgres:postgres -R /tmp/pgbackrest

info "Creating CBOB directories"
# Main directories - use 755 to allow postgres to traverse
mkdir -p "$CBOB_BASE_PATH"
chmod 755 "$CBOB_BASE_PATH"

# Sync directory (used by cbob_sync)
mkdir -p "$CBOB_BASE_PATH/crunchybridge/archive"
mkdir -p "$CBOB_BASE_PATH/crunchybridge/backup"
chmod 750 "$CBOB_BASE_PATH/crunchybridge"
chmod 750 "$CBOB_BASE_PATH/crunchybridge/archive"
chmod 750 "$CBOB_BASE_PATH/crunchybridge/backup"
chown postgres:postgres -R "$CBOB_BASE_PATH/crunchybridge"

# Restores directory
mkdir -p "$CBOB_BASE_PATH/restores"
chmod 750 "$CBOB_BASE_PATH/restores"
chown postgres:postgres "$CBOB_BASE_PATH/restores"

# PostgreSQL data directory
mkdir -p "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION"
chmod 750 "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION"
chown postgres:postgres -R "$CBOB_BASE_PATH/postgresql"

# Log directories
mkdir -p "$CBOB_BASE_PATH/log/cbob"
mkdir -p "$CBOB_BASE_PATH/log/pgbackrest"
mkdir -p "$CBOB_BASE_PATH/log/postgresql"
chmod 750 "$CBOB_BASE_PATH/log"
chmod 750 "$CBOB_BASE_PATH/log/cbob"
chmod 750 "$CBOB_BASE_PATH/log/pgbackrest"
chmod 750 "$CBOB_BASE_PATH/log/postgresql"
chown postgres:postgres -R "$CBOB_BASE_PATH/log"

# Metrics directory (for v2)
mkdir -p "$CBOB_BASE_PATH/metrics"
chmod 750 "$CBOB_BASE_PATH/metrics"
chown postgres:postgres "$CBOB_BASE_PATH/metrics"

# Config directory (for v2)
mkdir -p "$CBOB_BASE_PATH/config"
chmod 750 "$CBOB_BASE_PATH/config"
chown postgres:postgres "$CBOB_BASE_PATH/config"

# Set Slack environment variables
if [ -n "${CBOB_SLACK_CLI_TOKEN:-}" ]; then
    info "Adding Slack CLI Token to /etc/profile.d"
    rm -f /etc/profile.d/slack_cli.sh
    echo "export SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN" >> /etc/profile.d/slack_cli.sh
    echo "export SLACK_CHANNEL=$CBOB_SLACK_CHANNEL" >> /etc/profile.d/slack_cli.sh
    export SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN
    export SLACK_CHANNEL=$CBOB_SLACK_CHANNEL
fi

# Install CBOB v2 scripts and libraries
info "Installing CBOB v2 scripts and libraries"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create library directory
LIB_DIR="/usr/local/lib/cbob"
mkdir -p "$LIB_DIR"

# Copy library files
if [ -d "$SCRIPT_DIR/lib" ]; then
    cp "$SCRIPT_DIR/lib/cbob_common.sh" "$LIB_DIR/"
    cp "$SCRIPT_DIR/lib/cbob_metrics.sh" "$LIB_DIR/"
    cp "$SCRIPT_DIR/lib/cbob_security.sh" "$LIB_DIR/"
    if [ -f "$SCRIPT_DIR/lib/cbob_replication.sh" ]; then
        cp "$SCRIPT_DIR/lib/cbob_replication.sh" "$LIB_DIR/"
    fi
    chmod 644 "$LIB_DIR"/*.sh
    chown postgres:postgres "$LIB_DIR"/*.sh
fi

# Copy v2 binaries
info "Installing v2 CLI tools"
cp "$SCRIPT_DIR/bin/cbob" /usr/local/bin/
chmod 755 /usr/local/bin/cbob

for cmd in cbob-sync cbob-restore-check cbob-info cbob-expire cbob-config cbob-postgres; do
    if [ -f "$SCRIPT_DIR/bin/$cmd" ]; then
        cp "$SCRIPT_DIR/bin/$cmd" /usr/local/bin/
        chmod 755 "/usr/local/bin/$cmd"
    fi
done

if [ -f "$SCRIPT_DIR/bin/cbob-replicate" ]; then
    cp "$SCRIPT_DIR/bin/cbob-replicate" /usr/local/bin/
    chmod 755 /usr/local/bin/cbob-replicate
fi

# Copy utility scripts
if [ -f "$SCRIPT_DIR/bin/slack" ]; then
    cp -n "$SCRIPT_DIR/bin/slack" /usr/local/bin/slack 2>/dev/null || true
    chmod 755 /usr/local/bin/slack
fi

if [ -f "$SCRIPT_DIR/bin/pgbackrest_auto" ]; then
    cp "$SCRIPT_DIR/bin/pgbackrest_auto" /usr/local/bin/pgbackrest_auto
    chmod 755 /usr/local/bin/pgbackrest_auto
fi

# Legacy sync script for backward compatibility
if [ -f "$SCRIPT_DIR/bin/cbob_sync" ]; then
    cp "$SCRIPT_DIR/bin/cbob_sync" /usr/local/bin/cbob_sync_pg
    chown postgres:postgres /usr/local/bin/cbob_sync_pg
fi

# Create main configuration file
info "Creating configuration at /usr/local/etc/cb_offsite_backup"
cat > /usr/local/etc/cb_offsite_backup << EOF
# CBOB Configuration - Generated by setup.sh
CBOB_PG_VERSION=$CBOB_PG_VERSION
CBOB_CRUNCHY_API_KEY=$CBOB_CRUNCHY_API_KEY
CBOB_CRUNCHY_CLUSTERS=$CBOB_CRUNCHY_CLUSTERS
CBOB_RETENTION_FULL=$CBOB_RETENTION_FULL
CBOB_BASE_PATH=$CBOB_BASE_PATH
CBOB_TARGET_PATH=$CBOB_BASE_PATH/crunchybridge
CBOB_LOG_PATH=$CBOB_BASE_PATH/log/cbob
EOF

# Add S3 destination config if set
if [ "${CBOB_DEST_TYPE:-local}" = "s3" ]; then
    cat >> /usr/local/etc/cb_offsite_backup << EOF

# S3 Destination Configuration
CBOB_DEST_TYPE=s3
CBOB_DEST_ENDPOINT=$CBOB_DEST_ENDPOINT
CBOB_DEST_BUCKET=$CBOB_DEST_BUCKET
CBOB_DEST_ACCESS_KEY=$CBOB_DEST_ACCESS_KEY
CBOB_DEST_SECRET_KEY=$CBOB_DEST_SECRET_KEY
CBOB_DEST_REGION=${CBOB_DEST_REGION:-us-east-1}
EOF
    if [ -n "${CBOB_DEST_PREFIX:-}" ]; then
        echo "CBOB_DEST_PREFIX=$CBOB_DEST_PREFIX" >> /usr/local/etc/cb_offsite_backup
    fi
fi

# Add optional configuration
if [ -n "${CBOB_SLACK_CLI_TOKEN:-}" ]; then
    echo "CBOB_SLACK_CLI_TOKEN=$CBOB_SLACK_CLI_TOKEN" >> /usr/local/etc/cb_offsite_backup
    echo "CBOB_SLACK_CHANNEL=$CBOB_SLACK_CHANNEL" >> /usr/local/etc/cb_offsite_backup
fi

if [ -n "${CBOB_SYNC_HEARTBEAT_URL:-}" ]; then
    echo "CBOB_SYNC_HEARTBEAT_URL=$CBOB_SYNC_HEARTBEAT_URL" >> /usr/local/etc/cb_offsite_backup
fi

if [ -n "${CBOB_RESTORE_HEARTBEAT_URL:-}" ]; then
    echo "CBOB_RESTORE_HEARTBEAT_URL=$CBOB_RESTORE_HEARTBEAT_URL" >> /usr/local/etc/cb_offsite_backup
fi

# Configure logrotate
if [ -f "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" ]; then
    cp -n "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" /etc/logrotate.d/ 2>/dev/null || true
fi

# Set locale
info "Setting locale"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen 2>/dev/null || true
locale-gen 2>/dev/null || true
dpkg-reconfigure -fnoninteractive locales 2>/dev/null || true
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Stop any running PostgreSQL clusters
info "Stopping PostgreSQL clusters"
cbob_postgres_stop 2>/dev/null || true
systemctl stop postgresql 2>/dev/null || true

# Generate dynamic scripts and configuration files
info "Generating dynamic scripts and configuration files"
TMP_PATH="/tmp/cbob-generated-configs"
mkdir -p "$TMP_PATH/bin"

# Legacy wrapper scripts for backward compatibility
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_sync"
echo "sudo -u postgres cbob_sync_pg" >> "$TMP_PATH/bin/cbob_sync"

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_sync_and_expire"
echo "cbob_sync" >> "$TMP_PATH/bin/cbob_sync_and_expire"
echo "cbob_expire" >> "$TMP_PATH/bin/cbob_sync_and_expire"

echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_restore_check"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_check"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_info"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_expire"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_start"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_stop"
echo "#!/bin/bash" > "$TMP_PATH/bin/cbob_postgres_restart"

# pgBackRest configuration
cat > "$TMP_PATH/pgbackrest.conf" << EOF
[global]
start-fast=y
log-level-file=detail
log-path=$CBOB_BASE_PATH/log/pgbackrest
repo1-retention-full=$CBOB_RETENTION_FULL
repo1-path=$CBOB_BASE_PATH/crunchybridge

EOF

port_counter=5432

IFS=',' read -ra CLUSTER_IDS <<< "$CBOB_CRUNCHY_CLUSTERS"
for CLUSTER_ID in "${CLUSTER_IDS[@]}"; do
    IFS=''

    info "Processing cluster $CLUSTER_ID"
    CREDENTIALS_RESPONSE=$(curl -s -X POST "https://api.crunchybridge.com/clusters/$CLUSTER_ID/backup-tokens" -H "Authorization: Bearer $CBOB_CRUNCHY_API_KEY")
    STANZA=$(echo "$CREDENTIALS_RESPONSE" | jq -r '.stanza')
    if [ "$STANZA" = "null" ] || [ -z "$STANZA" ]; then
        error "Missing STANZA for CLUSTER $CLUSTER_ID. Response: $CREDENTIALS_RESPONSE"
    fi

    info "  -> Stanza $STANZA"

    if [ "$SKIP_PG_INIT" != "true" ]; then
        info "  Initializing database for cluster $CLUSTER_ID"
        rm -rf "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID"
        # Ensure parent directory exists and has correct permissions (initdb will create the cluster dir)
        mkdir -p "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION"
        chown postgres:postgres "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION"
        chmod 755 "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION"

        # Use runuser if available (for containers), otherwise use sudo
        if command -v runuser &> /dev/null; then
            runuser -u postgres -- /usr/lib/postgresql/$CBOB_PG_VERSION/bin/initdb -D "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID"
        else
            sudo -u postgres /usr/lib/postgresql/$CBOB_PG_VERSION/bin/initdb -D "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID"
        fi

        info "  Updating postgresql.conf for cluster $CLUSTER_ID"
        mv "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf" \
           "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.default.conf"

        if [ -f "$SCRIPT_DIR/etc/postgresql.template.conf" ]; then
            cp "$SCRIPT_DIR/etc/postgresql.template.conf" "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf"
            sed -i -e "s/{{stanza}}/$STANZA/g" "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf"
            sed -i -e "s/{{port}}/$port_counter/g" "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf"
        else
            # Create minimal postgresql.conf
            cat > "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf" << PGCONF
port = $port_counter
listen_addresses = 'localhost'
archive_mode = off
PGCONF
        fi
        chown postgres:postgres "$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID/postgresql.conf"
    fi

    info "  Adding cluster $CLUSTER_ID to script files"
    echo "sudo -u postgres /usr/lib/postgresql/$CBOB_PG_VERSION/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-$CBOB_PG_VERSION-$CLUSTER_ID.log start" >> "$TMP_PATH/bin/cbob_postgres_start"
    echo "sudo -u postgres /usr/lib/postgresql/$CBOB_PG_VERSION/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-$CBOB_PG_VERSION-$CLUSTER_ID.log stop" >> "$TMP_PATH/bin/cbob_postgres_stop"
    echo "sudo -u postgres /usr/lib/postgresql/$CBOB_PG_VERSION/bin/pg_ctl -D $CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID -l $CBOB_BASE_PATH/log/postgresql/postgresql-$CBOB_PG_VERSION-$CLUSTER_ID.log restart" >> "$TMP_PATH/bin/cbob_postgres_restart"
    echo "sudo -u postgres pgbackrest_auto --from=$STANZA --to=$CBOB_BASE_PATH/restores/$STANZA --checkdb --clear --report --config=/etc/pgbackrest/pgbackrest.conf" >> "$TMP_PATH/bin/cbob_restore_check"
    echo "sudo -u postgres pgbackrest --stanza=$STANZA check" >> "$TMP_PATH/bin/cbob_check"
    echo "sudo -u postgres pgbackrest --stanza=$STANZA info" >> "$TMP_PATH/bin/cbob_info"
    echo "sudo -u postgres pgbackrest --stanza=$STANZA expire" >> "$TMP_PATH/bin/cbob_expire"

    cat >> "$TMP_PATH/pgbackrest.conf" << EOF
[$STANZA]
pg1-path=$CBOB_BASE_PATH/postgresql/$CBOB_PG_VERSION/$CLUSTER_ID
pg1-port=$port_counter

EOF

    ((port_counter++))
done

info "Installing generated files"
chown postgres:postgres "$TMP_PATH"/* 2>/dev/null || true
chmod +x "$TMP_PATH/bin"/*
cp "$TMP_PATH/bin"/* /usr/local/bin/
cp "$TMP_PATH/pgbackrest.conf" /etc/pgbackrest/pgbackrest.conf

info "Adding automatic sync to cron"
rm -f /etc/cron.d/cbob_sync_and_expire
cat > /etc/cron.d/cbob_sync_and_expire << EOF
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Crunchy Bridge Offsite Backup - Sync at 6 AM UTC
00 06 * * * root /usr/local/bin/cbob sync 2>&1 | tee -a /var/log/cbob/cron_sync.log
EOF

info "Adding automatic restore check to cron"
rm -f /etc/cron.d/cbob_restore_check
cat > /etc/cron.d/cbob_restore_check << EOF
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Crunchy Bridge Offsite Backup - Restore check at 6 PM UTC
00 18 * * * root /usr/local/bin/cbob restore-check 2>&1 | tee -a /var/log/cbob/cron_restore.log
EOF

info "Cleaning up temporary files"
rm -rf "$TMP_PATH"

info "Setting ownership on executables"
chown postgres:postgres /usr/local/bin/cbob* 2>/dev/null || true

# Disable default PostgreSQL service
info "Disabling default PostgreSQL service"
systemctl disable postgresql 2>/dev/null || true

echo ""
info "======================================"
info "CBOB Setup completed successfully!"
info "======================================"
echo ""
info "Next steps:"
echo "  1. Review configuration: cat /usr/local/etc/cb_offsite_backup"
echo "  2. Run initial sync: sudo -u postgres cbob sync"
echo "  3. Check backup info: sudo -u postgres cbob info"
echo "  4. Test restore: sudo -u postgres cbob restore-check"
echo ""
info "For v2 CLI help: cbob --help"
