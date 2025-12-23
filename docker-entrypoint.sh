#!/bin/bash
set -e

# Source common functions
source /usr/local/lib/cbob/cbob_common.sh

# Initialize configuration if not exists
init_config() {
    if [ ! -f "$CBOB_CONFIG_FILE" ]; then
        info "Initializing configuration from environment variables"

        mkdir -p "$(dirname "$CBOB_CONFIG_FILE")"

        cat > "$CBOB_CONFIG_FILE" << EOF
# CBOB Configuration - Generated from environment
CBOB_CRUNCHY_API_KEY=${CBOB_CRUNCHY_API_KEY}
CBOB_CRUNCHY_CLUSTERS=${CBOB_CRUNCHY_CLUSTERS}
CBOB_TARGET_PATH=${CBOB_TARGET_PATH:-/data/backups}
CBOB_BASE_PATH=${CBOB_BASE_PATH:-/data}
CBOB_LOG_PATH=${CBOB_LOG_PATH:-/var/log/cbob}
CBOB_PG_VERSION=${CBOB_PG_VERSION:-18}
CBOB_RETENTION_FULL=${CBOB_RETENTION_FULL:-1}
CBOB_DRY_RUN=${CBOB_DRY_RUN:-false}
CBOB_SLACK_CLI_TOKEN=${CBOB_SLACK_CLI_TOKEN}
CBOB_SLACK_CHANNEL=${CBOB_SLACK_CHANNEL}
CBOB_SYNC_HEARTBEAT_URL=${CBOB_SYNC_HEARTBEAT_URL}
CBOB_RESTORE_HEARTBEAT_URL=${CBOB_RESTORE_HEARTBEAT_URL}
# Destination configuration
CBOB_DEST_TYPE=${CBOB_DEST_TYPE:-local}
CBOB_DEST_ENDPOINT=${CBOB_DEST_ENDPOINT}
CBOB_DEST_BUCKET=${CBOB_DEST_BUCKET}
CBOB_DEST_ACCESS_KEY=${CBOB_DEST_ACCESS_KEY}
CBOB_DEST_SECRET_KEY=${CBOB_DEST_SECRET_KEY}
CBOB_DEST_REGION=${CBOB_DEST_REGION:-us-east-1}
CBOB_DEST_PREFIX=${CBOB_DEST_PREFIX}
EOF

        # Validate configuration
        cbob config validate || {
            error "Invalid configuration. Please check environment variables."
        }
    fi
}

# Setup pgBackRest configuration
setup_pgbackrest() {
    info "Setting up pgBackRest configuration"

    mkdir -p /etc/pgbackrest /var/log/pgbackrest

    # Generate pgbackrest.conf
    cat > /etc/pgbackrest/pgbackrest.conf << EOF
[global]
start-fast=y
log-level-file=detail
log-path=/var/log/pgbackrest
repo1-retention-full=${CBOB_RETENTION_FULL:-1}
repo1-path=${CBOB_TARGET_PATH:-/data/backups}
EOF

    # Add stanza configurations
    if [ -n "$CBOB_CRUNCHY_CLUSTERS" ]; then
        IFS=',' read -ra CLUSTERS <<< "$CBOB_CRUNCHY_CLUSTERS"
        for cluster_id in "${CLUSTERS[@]}"; do
            # Get stanza info from API
            local credentials=$(curl -s -X POST \
                "https://api.crunchybridge.com/clusters/$cluster_id/backup-tokens" \
                -H "Authorization: Bearer $CBOB_CRUNCHY_API_KEY" 2>/dev/null || echo "{}")

            local stanza=$(echo "$credentials" | jq -r '.stanza // empty')
            if [ -n "$stanza" ]; then
                echo "" >> /etc/pgbackrest/pgbackrest.conf
                echo "[$stanza]" >> /etc/pgbackrest/pgbackrest.conf
                echo "pg1-path=/data/postgresql/18/$cluster_id" >> /etc/pgbackrest/pgbackrest.conf
            fi
        done
    fi
}

# Start cron daemon
start_cron() {
    info "Starting cron daemon"
    sudo service cron start
}

# Run command based on argument
case "$1" in
    cron)
        init_config
        setup_pgbackrest
        start_cron
        info "Running in cron mode"
        # Keep container running
        exec tail -f /var/log/cbob/cron.log
        ;;
    sync)
        init_config
        setup_pgbackrest
        info "Running sync"
        exec cbob sync "${@:2}"
        ;;
    restore-check)
        init_config
        setup_pgbackrest
        info "Running restore check"
        exec cbob restore-check "${@:2}"
        ;;
    bash|sh)
        exec /bin/bash
        ;;
    *)
        # Pass through to cbob command
        init_config
        setup_pgbackrest
        exec cbob "$@"
        ;;
esac
