#!/bin/bash

# CBOB Install Script - v2
# Installs CBOB CLI and libraries to the system
# For full setup with dependency installation, use setup.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root: sudo $0"
    fi
}

# Detect installation source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Installation paths
BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/cbob"
ETC_DIR="/usr/local/etc"
LOG_DIR="/var/log/cbob"
LOGROTATE_DIR="/etc/logrotate.d"

install_v2() {
    info "Installing CBOB v2 CLI and libraries..."

    # Create directories
    mkdir -p "$LIB_DIR"
    mkdir -p "$LOG_DIR"
    chown postgres:postgres "$LOG_DIR" 2>/dev/null || true

    # Install library files
    info "Installing library files to $LIB_DIR"
    if [ -d "$SCRIPT_DIR/lib" ]; then
        cp "$SCRIPT_DIR/lib/cbob_common.sh" "$LIB_DIR/"
        cp "$SCRIPT_DIR/lib/cbob_metrics.sh" "$LIB_DIR/"
        cp "$SCRIPT_DIR/lib/cbob_security.sh" "$LIB_DIR/"
        if [ -f "$SCRIPT_DIR/lib/cbob_replication.sh" ]; then
            cp "$SCRIPT_DIR/lib/cbob_replication.sh" "$LIB_DIR/"
        fi
        chmod 644 "$LIB_DIR"/*.sh
    else
        error "Library directory not found: $SCRIPT_DIR/lib"
    fi

    # Install CLI binaries
    info "Installing CLI tools to $BIN_DIR"
    if [ -d "$SCRIPT_DIR/bin" ]; then
        # Main cbob command
        cp "$SCRIPT_DIR/bin/cbob" "$BIN_DIR/"
        chmod 755 "$BIN_DIR/cbob"

        # Subcommands
        for cmd in cbob-sync cbob-restore-check cbob-info cbob-expire cbob-config cbob-postgres; do
            if [ -f "$SCRIPT_DIR/bin/$cmd" ]; then
                cp "$SCRIPT_DIR/bin/$cmd" "$BIN_DIR/"
                chmod 755 "$BIN_DIR/$cmd"
            fi
        done

        # Optional: replication command
        if [ -f "$SCRIPT_DIR/bin/cbob-replicate" ]; then
            cp "$SCRIPT_DIR/bin/cbob-replicate" "$BIN_DIR/"
            chmod 755 "$BIN_DIR/cbob-replicate"
        fi

        # Legacy sync script (for backward compatibility)
        if [ -f "$SCRIPT_DIR/bin/cbob_sync" ]; then
            cp "$SCRIPT_DIR/bin/cbob_sync" "$BIN_DIR/cbob_sync_legacy"
            chmod 755 "$BIN_DIR/cbob_sync_legacy"
        fi

        # Slack CLI
        if [ -f "$SCRIPT_DIR/bin/slack" ]; then
            cp -n "$SCRIPT_DIR/bin/slack" "$BIN_DIR/slack" 2>/dev/null || true
            chmod 755 "$BIN_DIR/slack"
        fi

        # pgbackrest_auto
        if [ -f "$SCRIPT_DIR/bin/pgbackrest_auto" ]; then
            cp "$SCRIPT_DIR/bin/pgbackrest_auto" "$BIN_DIR/pgbackrest_auto"
            chmod 755 "$BIN_DIR/pgbackrest_auto"
        fi
    else
        error "Binary directory not found: $SCRIPT_DIR/bin"
    fi

    # Install config example if not exists
    if [ -f "$SCRIPT_DIR/etc/cb_offsite_backup_example.env" ]; then
        if [ ! -f "$ETC_DIR/cb_offsite_backup" ]; then
            info "Installing example configuration to $ETC_DIR/cb_offsite_backup"
            cp "$SCRIPT_DIR/etc/cb_offsite_backup_example.env" "$ETC_DIR/cb_offsite_backup"
        else
            info "Configuration file already exists, skipping"
        fi
    elif [ -f "$SCRIPT_DIR/.env.example" ]; then
        if [ ! -f "$ETC_DIR/cb_offsite_backup" ]; then
            info "Installing example configuration to $ETC_DIR/cb_offsite_backup"
            cp "$SCRIPT_DIR/.env.example" "$ETC_DIR/cb_offsite_backup"
        fi
    fi

    # Install logrotate configuration
    if [ -f "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" ]; then
        info "Installing logrotate configuration"
        cp -n "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" "$LOGROTATE_DIR/" 2>/dev/null || true
    fi

    # Set ownership for postgres user
    chown -R postgres:postgres "$LIB_DIR" 2>/dev/null || true

    info "Installation complete!"
}

install_legacy() {
    info "Installing legacy CBOB scripts..."

    # Original install.sh behavior
    if [ -f "$SCRIPT_DIR/bin/cbob_sync" ]; then
        info "Copying cbob_sync to $BIN_DIR"
        cp "$SCRIPT_DIR/bin/cbob_sync" "$BIN_DIR/cbob_sync"
    fi

    if [ -f "$SCRIPT_DIR/bin/slack" ]; then
        info "Copying slack to $BIN_DIR"
        cp -n "$SCRIPT_DIR/bin/slack" "$BIN_DIR/slack" 2>/dev/null || true
    fi

    if [ -f "$SCRIPT_DIR/etc/cb_offsite_backup_example.env" ]; then
        info "Copying config example to $ETC_DIR"
        cp -n "$SCRIPT_DIR/etc/cb_offsite_backup_example.env" "$ETC_DIR/cb_offsite_backup" 2>/dev/null || true
    fi

    if [ -f "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" ]; then
        info "Copying logrotate config"
        cp -n "$SCRIPT_DIR/etc/logrotate.d/cb_offsite_backup" "$LOGROTATE_DIR/" 2>/dev/null || true
    fi

    info "Linking cbob_sync to cron.daily"
    ln -sf "$BIN_DIR/cbob_sync" /etc/cron.daily/cbob_sync 2>/dev/null || true

    info "Legacy installation complete!"
}

show_help() {
    cat << EOF
CBOB Installer v2

Usage: sudo $0 [options]

Options:
    --v2          Install v2 architecture (default)
    --legacy      Install legacy scripts only
    --help, -h    Show this help message

Examples:
    sudo ./install.sh          # Install v2 architecture
    sudo ./install.sh --legacy # Install legacy scripts only

After installation:
    1. Edit configuration: sudo nano /usr/local/etc/cb_offsite_backup
    2. Run sync: sudo -u postgres cbob sync
    3. Check info: sudo -u postgres cbob info

For full setup with dependency installation, use:
    sudo ./setup.sh

EOF
}

# Main
main() {
    local install_mode="v2"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --v2)
                install_mode="v2"
                shift
                ;;
            --legacy)
                install_mode="legacy"
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

    check_root

    info "CBOB Installer"
    info "Installation mode: $install_mode"

    case "$install_mode" in
        v2)
            install_v2
            ;;
        legacy)
            install_legacy
            ;;
    esac

    echo ""
    info "Next steps:"
    echo "  1. Edit configuration: sudo nano /usr/local/etc/cb_offsite_backup"
    echo "  2. Run sync: sudo -u postgres cbob sync"
    echo ""
    info "Done!"
}

main "$@"
