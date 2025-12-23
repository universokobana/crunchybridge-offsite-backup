#!/bin/bash

# Common functions and utilities for CBOB scripts
# This library provides shared functionality for logging, notifications, and error handling

# Global variables
CBOB_VERSION="2.0.0"
CBOB_LOG_FORMAT="${CBOB_LOG_FORMAT:-text}"  # text or json
CBOB_LOG_LEVEL="${CBOB_LOG_LEVEL:-info}"    # debug, info, warning, error

# AWS CLI v2 compatibility for S3-compatible services (DigitalOcean Spaces, MinIO, etc.)
# Disables CRC32 checksums that AWS CLI v2 sends by default but some services don't support
export AWS_S3_REQUEST_CHECKSUM_CALCULATION="${AWS_S3_REQUEST_CHECKSUM_CALCULATION:-when_required}"

# Color codes for terminal output (use declare to allow re-sourcing)
declare -g COLOR_RED='\033[0;31m' 2>/dev/null || true
declare -g COLOR_YELLOW='\033[0;33m' 2>/dev/null || true
declare -g COLOR_GREEN='\033[0;32m' 2>/dev/null || true
declare -g COLOR_BLUE='\033[0;34m' 2>/dev/null || true
declare -g COLOR_RESET='\033[0m' 2>/dev/null || true

# Log levels
declare -g LOG_LEVEL_DEBUG=0 2>/dev/null || true
declare -g LOG_LEVEL_INFO=1 2>/dev/null || true
declare -g LOG_LEVEL_WARNING=2 2>/dev/null || true
declare -g LOG_LEVEL_ERROR=3 2>/dev/null || true

# Get numeric log level
# Uses tr for lowercase conversion (compatible with bash 3.2+)
get_log_level_num() {
    local level=$(echo "$CBOB_LOG_LEVEL" | tr '[:upper:]' '[:lower:]')
    case "$level" in
        debug) echo $LOG_LEVEL_DEBUG ;;
        info) echo $LOG_LEVEL_INFO ;;
        warning|warn) echo $LOG_LEVEL_WARNING ;;
        error) echo $LOG_LEVEL_ERROR ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

# Core logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%F %T")
    local caller="${3:-$(basename "$0")}"
    
    local level_num
    case "$level" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO) level_num=$LOG_LEVEL_INFO ;;
        WARNING|WARN) level_num=$LOG_LEVEL_WARNING ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *) level_num=$LOG_LEVEL_INFO ;;
    esac
    
    # Check if we should log this level
    if [ $level_num -lt $(get_log_level_num) ]; then
        return 0
    fi
    
    if [ "$CBOB_LOG_FORMAT" = "json" ]; then
        # JSON format for structured logging (output to stderr to avoid polluting stdout)
        printf '{"timestamp":"%s","level":"%s","message":"%s","caller":"%s"}\n' \
            "$timestamp" "$level" "$message" "$caller" >&2
    else
        # Traditional text format with colors (output to stderr to avoid polluting stdout)
        local color=""
        case "$level" in
            DEBUG) color="$COLOR_BLUE" ;;
            INFO) color="$COLOR_GREEN" ;;
            WARNING|WARN) color="$COLOR_YELLOW" ;;
            ERROR) color="$COLOR_RED" ;;
        esac

        if [ -t 2 ]; then  # Check if stderr is a terminal
            echo -e "${timestamp} ${color}${level}:${COLOR_RESET} ${message}" >&2
        else
            echo "${timestamp} ${level}: ${message}" >&2
        fi
    fi
    
    # Also log to syslog
    local syslog_priority
    case "$level" in
        DEBUG) syslog_priority="user.debug" ;;
        INFO) syslog_priority="user.notice" ;;
        WARNING|WARN) syslog_priority="user.warning" ;;
        ERROR) syslog_priority="user.error" ;;
        *) syslog_priority="user.notice" ;;
    esac
    
    logger -p "$syslog_priority" -t "$caller" "$message"
}

# Convenience functions
debug() {
    log_message "DEBUG" "$1"
}

info() {
    log_message "INFO" "$1"
    # Note: info messages are logged but NOT sent to Slack
    # Use notify() directly for important messages that should go to Slack
}

warning() {
    log_message "WARNING" "$1"
    notify ":warning: $1"
    return 1
}

error() {
    log_message "ERROR" "$1"
    notify ":octagonal_sign: $1"

    # Clean up lock file if it exists
    if [ -n "${CBOB_LOCK_FILE:-}" ] && [ -f "${CBOB_LOCK_FILE}" ]; then
        rm -f "${CBOB_LOCK_FILE}"
    fi

    exit "${2:-1}"  # Allow custom exit codes
}

# Notification function
notify() {
    local message="$1"

    # Skip if no Slack token configured
    if [ -z "${CBOB_SLACK_CLI_TOKEN:-}" ]; then
        return 0
    fi
    
    # Check if slack command exists
    if ! command -v slack &> /dev/null; then
        debug "Slack CLI not found, skipping notification"
        return 0
    fi
    
    # Send notification (ignore errors)
    export SLACK_CLI_TOKEN="${CBOB_SLACK_CLI_TOKEN}"
    (slack chat send --text "$message" --channel "${CBOB_SLACK_CHANNEL:-#general}" >/dev/null 2>&1) || true
}

# Lock file management
acquire_lock() {
    local lock_name="${1:-cbob}"
    local lock_file="/tmp/${lock_name}.lock"
    
    export CBOB_LOCK_FILE="$lock_file"
    
    # Create lock file with exclusive access
    exec 9>"${lock_file}"
    if ! flock -n 9; then
        error "Another instance is already running (lock file: $lock_file)"
    fi
    
    # Set trap to clean up lock file on exit
    trap 'rm -f "${CBOB_LOCK_FILE}"' EXIT
    
    debug "Acquired lock: $lock_file"
}

release_lock() {
    if [ -n "${CBOB_LOCK_FILE}" ] && [ -f "${CBOB_LOCK_FILE}" ]; then
        rm -f "${CBOB_LOCK_FILE}"
        debug "Released lock: ${CBOB_LOCK_FILE}"
    fi
}

# Configuration loading
load_config() {
    local config_file=""

    # Search for config file in standard locations
    if [ -n "${CBOB_CONFIG_FILE:-}" ]; then
        config_file="$CBOB_CONFIG_FILE"
    elif [ -r "${HOME}/.cb_offsite_backup" ]; then
        config_file="${HOME}/.cb_offsite_backup"
    elif [ -r "/usr/local/etc/cb_offsite_backup" ]; then
        config_file="/usr/local/etc/cb_offsite_backup"
    elif [ -r "/etc/cb_offsite_backup" ]; then
        config_file="/etc/cb_offsite_backup"
    fi
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        error "Configuration file not found"
    fi
    
    info "Loading configuration from: $config_file"
    
    # Load configuration based on OS
    local uname_str=$(uname)
    if [ "$uname_str" = 'Linux' ]; then
        export $(grep -v '^#' "$config_file" | xargs -d '\n')
    elif [ "$uname_str" = 'FreeBSD' ] || [ "$uname_str" = 'Darwin' ]; then
        export $(grep -v '^#' "$config_file" | xargs -0)
    fi
    
    # Set defaults for optional variables
    export CBOB_LOG_PATH="${CBOB_LOG_PATH:-/var/log}"
    export CBOB_DRY_RUN="${CBOB_DRY_RUN:-false}"
    export TZ="${TZ:-UTC}"

    # Set defaults for destination storage (local or s3)
    export CBOB_DEST_TYPE="${CBOB_DEST_TYPE:-local}"
}

# Validate required configuration
validate_config() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        error "Missing required configuration variables: ${missing_vars[*]}"
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("$@")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}. Please install them before continuing."
    fi
}

# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts="${1:-3}"
    local initial_delay="${2:-1}"
    local max_delay="${3:-60}"
    shift 3
    
    local attempt=1
    local delay=$initial_delay
    
    while [ $attempt -le $max_attempts ]; do
        debug "Attempt $attempt of $max_attempts: $*"
        
        if "$@"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            warning "Command failed, retrying in ${delay}s..."
            sleep $delay
            
            # Exponential backoff with max delay
            delay=$((delay * 2))
            if [ $delay -gt $max_delay ]; then
                delay=$max_delay
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    error "Command failed after $max_attempts attempts: $*"
}

# Heartbeat function
send_heartbeat() {
    local url="$1"
    local event="${2:-heartbeat}"
    
    if [ -z "$url" ]; then
        return 0
    fi
    
    debug "Sending heartbeat to: $url"
    
    if curl -s -f -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"event\":\"$event\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
        >/dev/null 2>&1; then
        debug "Heartbeat sent successfully"
    else
        warning "Failed to send heartbeat"
    fi
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    
    if [ "$total" -eq 0 ]; then
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%$((width - filled))s" | tr ' ' ']'
    printf "] %d%%" "$percent"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# Human readable sizes
# Converts bytes to human readable format (KB, MB, GB, TB)
human_readable_size() {
    local size="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0

    # Use >= 1024 to properly convert at boundaries
    while [ "$size" -ge 1024 ] && [ "$unit" -lt 4 ]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done

    echo "${size}${units[$unit]}"
}

# =============================================================================
# S3-Compatible Object Storage Functions
# =============================================================================

# Check if destination is S3-compatible storage
is_dest_s3() {
    [ "${CBOB_DEST_TYPE:-local}" = "s3" ]
}

# Validate S3 destination configuration
validate_dest_s3_config() {
    if ! is_dest_s3; then
        return 0
    fi

    local required_vars=(
        "CBOB_DEST_ENDPOINT"
        "CBOB_DEST_BUCKET"
        "CBOB_DEST_ACCESS_KEY"
        "CBOB_DEST_SECRET_KEY"
    )
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        error "Missing required S3 destination configuration: ${missing_vars[*]}"
    fi

    # Set default region if not specified
    export CBOB_DEST_REGION="${CBOB_DEST_REGION:-us-east-1}"
    export CBOB_DEST_PREFIX="${CBOB_DEST_PREFIX:-}"

    debug "S3 destination configured: ${CBOB_DEST_ENDPOINT}/${CBOB_DEST_BUCKET}"
}

# Build AWS CLI command for source (Crunchy Bridge S3 or custom S3)
# Uses environment AWS_* credentials and optional CBOB_SOURCE_ENDPOINT
# Usage: aws_source_cmd s3 sync source dest
aws_source_cmd() {
    local cmd_args=("$@")

    if [ -n "${CBOB_SOURCE_ENDPOINT:-}" ]; then
        # Custom source endpoint (e.g., MinIO for testing)
        aws --endpoint-url "${CBOB_SOURCE_ENDPOINT}" "${cmd_args[@]}"
    else
        # Default AWS S3 endpoint (Crunchy Bridge)
        aws "${cmd_args[@]}"
    fi
}

# Build AWS CLI command with destination endpoint
# Usage: aws_dest_cmd s3 sync source dest
# Note: Uses subshell with explicit exports to ensure S3-compatible services work
aws_dest_cmd() {
    local cmd_args=("$@")

    if is_dest_s3; then
        # Run in subshell with exported env vars to ensure they're inherited
        # by all AWS CLI threads/subprocesses (needed for parallel uploads)
        (
            # IMPORTANT: Unset AWS_SESSION_TOKEN from source (Crunchy Bridge) credentials
            # as it's not valid for destination S3-compatible services (DO Spaces, etc.)
            unset AWS_SESSION_TOKEN
            export AWS_ACCESS_KEY_ID="${CBOB_DEST_ACCESS_KEY}"
            export AWS_SECRET_ACCESS_KEY="${CBOB_DEST_SECRET_KEY}"
            export AWS_DEFAULT_REGION="${CBOB_DEST_REGION:-us-east-1}"
            # Disable CRC32 checksums - not supported by all S3-compatible services
            export AWS_S3_REQUEST_CHECKSUM_CALCULATION="when_required"
            aws --endpoint-url "${CBOB_DEST_ENDPOINT}" \
                --region "${CBOB_DEST_REGION:-us-east-1}" \
                "${cmd_args[@]}"
        )
    else
        # Local destination - just use local path
        error "aws_dest_cmd should only be called when CBOB_DEST_TYPE=s3"
    fi
}

# Get the destination path based on type
# Returns: s3://bucket/prefix or local path
get_dest_path() {
    local subpath="${1:-}"

    if is_dest_s3; then
        local prefix="${CBOB_DEST_PREFIX:-}"
        # Remove trailing slash from prefix if present
        prefix="${prefix%/}"
        echo "s3://${CBOB_DEST_BUCKET}${prefix}${subpath}"
    else
        echo "${CBOB_TARGET_PATH}${subpath}"
    fi
}

# Upload files to S3 destination one by one (for S3-compatible services)
# AWS CLI v2 cp --recursive uses parallel threads that don't properly inherit
# the AWS_S3_REQUEST_CHECKSUM_CALCULATION env var needed for DigitalOcean Spaces
# Usage: upload_files_to_s3 local_dir dest_s3_path
upload_files_to_s3() {
    local local_dir="$1"
    local dest_path="$2"
    local failed=0
    local total=0
    local uploaded=0

    # Count total files
    total=$(find "$local_dir" -type f | wc -l)
    info "Uploading $total files to S3..."

    # Upload files one by one
    while IFS= read -r -d '' file; do
        local rel_path="${file#$local_dir/}"
        local dest_file="${dest_path}/${rel_path}"

        ((uploaded++))
        if [ $((uploaded % 50)) -eq 0 ]; then
            info "  Progress: $uploaded / $total files..."
        fi

        aws_dest_cmd s3 cp "$file" "$dest_file" --quiet 2>/dev/null || {
            debug "Failed to upload: $rel_path"
            ((failed++))
        }
    done < <(find "$local_dir" -type f -print0)

    if [ $failed -gt 0 ]; then
        warning "Failed to upload $failed of $total files"
        return 1
    fi

    info "Successfully uploaded $total files"
    return 0
}

# Sync from source S3 to destination (local or S3)
# Usage: sync_to_dest source_s3_url dest_subpath [additional_aws_args...]
sync_to_dest() {
    local source_url="$1"
    local dest_subpath="$2"
    shift 2
    local additional_args=("$@")

    local dest_path=$(get_dest_path "$dest_subpath")

    if is_dest_s3; then
        debug "Syncing to S3 destination: $source_url -> $dest_path"

        # For S3-to-S3 sync, we need to:
        # 1. Download from source with source credentials
        # 2. Upload to destination with destination credentials
        # AWS CLI doesn't support cross-account S3-to-S3 with different credentials directly
        # So we use a streaming approach with pipes

        # Create a temporary directory for the sync
        local temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" RETURN

        # Download from source
        debug "Downloading from source S3..."
        aws_source_cmd s3 sync "$source_url" "$temp_dir" "${additional_args[@]}" || {
            warning "Failed to download from source: $source_url"
            return 1
        }

        # Upload to destination file by file
        # Using individual uploads because AWS CLI v2 cp --recursive doesn't
        # properly apply AWS_S3_REQUEST_CHECKSUM_CALCULATION to its parallel workers
        debug "Uploading to destination S3..."
        upload_files_to_s3 "$temp_dir" "$dest_path" || {
            warning "Failed to upload to destination: $dest_path"
            return 1
        }
    else
        debug "Syncing to local destination: $source_url -> $dest_path"

        # Ensure destination directory exists
        mkdir -p "$(dirname "$dest_path")"
        mkdir -p "$dest_path"

        aws_source_cmd s3 sync "$source_url" "$dest_path" "${additional_args[@]}"
    fi
}

# Copy a single file from source S3 to destination (local or S3)
# Usage: copy_to_dest source_s3_url dest_subpath [additional_aws_args...]
copy_to_dest() {
    local source_url="$1"
    local dest_subpath="$2"
    shift 2
    local additional_args=("$@")

    local dest_path=$(get_dest_path "$dest_subpath")

    if is_dest_s3; then
        debug "Copying to S3 destination: $source_url -> $dest_path"

        # Download to temp file, then upload
        local temp_file=$(mktemp)
        trap "rm -f $temp_file" RETURN

        aws_source_cmd s3 cp "$source_url" "$temp_file" "${additional_args[@]}" || {
            warning "Failed to download from source: $source_url"
            return 1
        }

        aws_dest_cmd s3 cp "$temp_file" "$dest_path" "${additional_args[@]}" || {
            warning "Failed to upload to destination: $dest_path"
            return 1
        }
    else
        debug "Copying to local destination: $source_url -> $dest_path"

        # Ensure destination directory exists
        mkdir -p "$(dirname "$dest_path")"

        aws_source_cmd s3 cp "$source_url" "$dest_path" "${additional_args[@]}"
    fi
}

# List files in destination
# Usage: list_dest subpath
list_dest() {
    local subpath="${1:-}"
    local dest_path=$(get_dest_path "$subpath")

    if is_dest_s3; then
        aws_dest_cmd s3 ls "$dest_path" --recursive
    else
        if [ -d "$dest_path" ]; then
            find "$dest_path" -type f
        fi
    fi
}

# Check if destination path exists
# Usage: dest_exists subpath
dest_exists() {
    local subpath="${1:-}"
    local dest_path=$(get_dest_path "$subpath")

    if is_dest_s3; then
        # Use s3api head-object for better S3-compatible service support
        # s3 ls uses ListObjectsV2 which some services don't support
        local bucket="${CBOB_DEST_BUCKET}"
        local prefix="${CBOB_DEST_PREFIX:-}"
        prefix="${prefix%/}"
        local key="${prefix}${subpath}"
        key="${key#/}"  # Remove leading slash if present

        aws_dest_cmd s3api head-object --bucket "$bucket" --key "$key" >/dev/null 2>&1
    else
        [ -e "$dest_path" ]
    fi
}

# Get destination size in bytes
# Usage: get_dest_size subpath
# Compatible with Linux (du -sb) and macOS (du -sk * 1024)
get_dest_size() {
    local subpath="${1:-}"
    local dest_path=$(get_dest_path "$subpath")

    if is_dest_s3; then
        aws_dest_cmd s3 ls "$dest_path" --recursive --summarize 2>/dev/null | \
            grep "Total Size:" | awk '{print $3}' || echo "0"
    else
        if [ -d "$dest_path" ]; then
            # Use portable du command (works on Linux and macOS)
            if du -sb "$dest_path" 2>/dev/null | awk '{print $1}'; then
                : # Linux style worked
            else
                # macOS style: du -sk returns KB, multiply by 1024
                local kb=$(du -sk "$dest_path" 2>/dev/null | awk '{print $1}')
                if [ -n "$kb" ] && [ "$kb" -gt 0 ]; then
                    echo $((kb * 1024))
                else
                    echo "0"
                fi
            fi
        else
            echo "0"
        fi
    fi
}

# Download from destination to local path (for restore operations)
# Usage: download_from_dest dest_subpath local_path
download_from_dest() {
    local dest_subpath="$1"
    local local_path="$2"

    local dest_path=$(get_dest_path "$dest_subpath")

    if is_dest_s3; then
        debug "Downloading from S3 destination: $dest_path -> $local_path"
        mkdir -p "$local_path"
        aws_dest_cmd s3 sync "$dest_path" "$local_path"
    else
        debug "Copying from local destination: $dest_path -> $local_path"
        if [ "$dest_path" != "$local_path" ]; then
            mkdir -p "$local_path"
            cp -r "$dest_path"/* "$local_path/" 2>/dev/null || true
        fi
    fi
}

# Source security functions if available
CBOB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${CBOB_LIB_DIR}/cbob_security.sh" ]; then
    source "${CBOB_LIB_DIR}/cbob_security.sh"
elif [ -f "/usr/local/lib/cbob/cbob_security.sh" ]; then
    source "/usr/local/lib/cbob/cbob_security.sh"
fi

# Export all functions
export -f log_message debug info warning error notify
export -f acquire_lock release_lock load_config validate_config
export -f check_dependencies retry_with_backoff send_heartbeat
export -f show_progress human_readable_size
export -f is_dest_s3 validate_dest_s3_config aws_source_cmd aws_dest_cmd get_dest_path
export -f upload_files_to_s3 sync_to_dest copy_to_dest list_dest dest_exists get_dest_size
export -f download_from_dest