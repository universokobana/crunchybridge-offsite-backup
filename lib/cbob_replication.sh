#!/bin/bash

# CBOB Multi-Region Replication Library
# Provides cross-region and cross-cloud backup replication

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/cbob_common.sh"
source "${SCRIPT_DIR}/cbob_metrics.sh"
source "${SCRIPT_DIR}/cbob_security.sh"

# Replication configuration file
REPLICATION_CONFIG="${CBOB_REPLICATION_CONFIG:-${CBOB_BASE_PATH}/config/replication.yaml}"
REPLICATION_STATE="${CBOB_REPLICATION_STATE:-${CBOB_BASE_PATH}/state/replication.json}"

# Storage provider interface
# Each provider must implement: configure, sync, verify, cleanup
declare -A STORAGE_PROVIDERS=(
    ["aws"]="aws_s3"
    ["azure"]="azure_blob"
    ["gcp"]="gcp_storage"
    ["do"]="digitalocean_spaces"
    ["minio"]="minio_s3"
)

# Initialize replication
init_replication() {
    info "Initializing multi-region replication"
    
    # Create directories
    mkdir -p "$(dirname "$REPLICATION_CONFIG")" "$(dirname "$REPLICATION_STATE")"
    
    # Initialize state file
    if [ ! -f "$REPLICATION_STATE" ]; then
        echo '{"replicas": {}, "last_sync": {}, "health": {}}' > "$REPLICATION_STATE"
    fi
    
    # Validate configuration
    if [ -f "$REPLICATION_CONFIG" ]; then
        validate_replication_config || error "Invalid replication configuration"
    else
        warning "No replication configuration found at $REPLICATION_CONFIG"
        return 1
    fi
}

# Validate replication configuration
validate_replication_config() {
    local config="$REPLICATION_CONFIG"
    
    # Check if config exists
    if [ ! -f "$config" ]; then
        return 1
    fi
    
    # Parse YAML config (using Python for portability)
    local validation_result=$(python3 -c "
import yaml
import sys

try:
    with open('$config', 'r') as f:
        config = yaml.safe_load(f)
    
    # Validate structure
    if 'replication' not in config:
        print('ERROR: Missing replication section')
        sys.exit(1)
    
    repl = config['replication']
    if 'primary' not in repl:
        print('ERROR: Missing primary configuration')
        sys.exit(1)
    
    # Validate primary
    primary = repl['primary']
    required = ['provider', 'region', 'bucket']
    for field in required:
        if field not in primary:
            print(f'ERROR: Missing primary.{field}')
            sys.exit(1)
    
    # Validate replicas
    if 'replicas' in repl:
        for i, replica in enumerate(repl['replicas']):
            for field in ['name', 'provider', 'region']:
                if field not in replica:
                    print(f'ERROR: Missing replicas[{i}].{field}')
                    sys.exit(1)
    
    print('OK')
except Exception as e:
    print(f'ERROR: {str(e)}')
    sys.exit(1)
" 2>&1)
    
    if [[ "$validation_result" == "OK" ]]; then
        debug "Replication configuration is valid"
        return 0
    else
        error "Replication configuration validation failed: $validation_result"
        return 1
    fi
}

# Get replication configuration
get_replication_config() {
    if [ ! -f "$REPLICATION_CONFIG" ]; then
        echo "{}"
        return
    fi
    
    # Convert YAML to JSON for easier parsing in bash
    python3 -c "
import yaml
import json
with open('$REPLICATION_CONFIG', 'r') as f:
    config = yaml.safe_load(f)
print(json.dumps(config.get('replication', {})))
" 2>/dev/null || echo "{}"
}

# AWS S3 Provider
aws_s3_configure() {
    local region="$1"
    local bucket="$2"
    local access_key="${3:-}"
    local secret_key="${4:-}"
    
    # Set AWS environment if credentials provided
    if [ -n "$access_key" ] && [ -n "$secret_key" ]; then
        export AWS_ACCESS_KEY_ID="$access_key"
        export AWS_SECRET_ACCESS_KEY="$secret_key"
    fi
    
    export AWS_DEFAULT_REGION="$region"
    
    # Verify bucket access
    if ! aws s3 ls "s3://$bucket" >/dev/null 2>&1; then
        error "Cannot access S3 bucket: $bucket"
    fi
}

aws_s3_sync() {
    local source="$1"
    local bucket="$2"
    local prefix="${3:-}"
    local options="${4:-}"
    
    info "Syncing to AWS S3: s3://$bucket/$prefix"
    
    local sync_cmd="aws s3 sync '$source' 's3://$bucket/$prefix' --delete"
    
    # Add custom options
    if [ -n "$options" ]; then
        sync_cmd="$sync_cmd $options"
    fi
    
    # Add bandwidth limiting if configured
    if [ -n "${CBOB_REPLICATION_BANDWIDTH:-}" ]; then
        sync_cmd="$sync_cmd --bandwidth $CBOB_REPLICATION_BANDWIDTH"
    fi
    
    # Execute sync with retry
    retry_with_backoff 3 10 300 bash -c "$sync_cmd"
}

aws_s3_verify() {
    local source="$1"
    local bucket="$2"
    local prefix="${3:-}"
    
    info "Verifying AWS S3 replication: s3://$bucket/$prefix"
    
    # Get local checksums
    local local_checksums=$(mktemp)
    find "$source" -type f -exec md5sum {} \; | sort > "$local_checksums"
    
    # Get remote checksums (using S3 ETags)
    local remote_checksums=$(mktemp)
    aws s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
        --query 'Contents[].{Key: Key, ETag: ETag}' \
        --output json | jq -r '.[] | "\(.ETag) \(.Key)"' | sort > "$remote_checksums"
    
    # Compare
    local diff_result=$(diff -u "$local_checksums" "$remote_checksums" || true)
    
    rm -f "$local_checksums" "$remote_checksums"
    
    if [ -z "$diff_result" ]; then
        info "Verification passed: All files match"
        return 0
    else
        warning "Verification failed: Files differ"
        echo "$diff_result"
        return 1
    fi
}

# Azure Blob Storage Provider
azure_blob_configure() {
    local account="$1"
    local container="$2"
    local sas_token="${3:-}"
    local connection_string="${4:-}"
    
    # Configure Azure CLI
    if [ -n "$connection_string" ]; then
        export AZURE_STORAGE_CONNECTION_STRING="$connection_string"
    elif [ -n "$sas_token" ]; then
        export AZURE_STORAGE_ACCOUNT="$account"
        export AZURE_STORAGE_SAS_TOKEN="$sas_token"
    fi
    
    # Verify container access
    if ! az storage container exists --name "$container" >/dev/null 2>&1; then
        error "Cannot access Azure container: $container"
    fi
}

azure_blob_sync() {
    local source="$1"
    local container="$2"
    local prefix="${3:-}"
    local options="${4:-}"
    
    info "Syncing to Azure Blob: $container/$prefix"
    
    # Use azcopy for better performance
    if command -v azcopy &> /dev/null; then
        local dest="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/$container/$prefix"
        retry_with_backoff 3 10 300 \
            azcopy sync "$source" "$dest" --delete-destination=true $options
    else
        # Fallback to Azure CLI
        retry_with_backoff 3 10 300 \
            az storage blob upload-batch \
                --source "$source" \
                --destination "$container" \
                --destination-path "$prefix" \
                --overwrite
    fi
}

# Google Cloud Storage Provider
gcp_storage_configure() {
    local project="$1"
    local bucket="$2"
    local credentials_file="${3:-}"
    
    # Set credentials if provided
    if [ -n "$credentials_file" ] && [ -f "$credentials_file" ]; then
        export GOOGLE_APPLICATION_CREDENTIALS="$credentials_file"
    fi
    
    # Set project
    gcloud config set project "$project" >/dev/null 2>&1
    
    # Verify bucket access
    if ! gsutil ls "gs://$bucket" >/dev/null 2>&1; then
        error "Cannot access GCS bucket: $bucket"
    fi
}

gcp_storage_sync() {
    local source="$1"
    local bucket="$2"
    local prefix="${3:-}"
    local options="${4:-}"
    
    info "Syncing to GCS: gs://$bucket/$prefix"
    
    retry_with_backoff 3 10 300 \
        gsutil -m rsync -r -d $options "$source" "gs://$bucket/$prefix"
}

# DigitalOcean Spaces Provider (S3-compatible)
digitalocean_spaces_configure() {
    local region="$1"
    local space="$2"
    local access_key="$3"
    local secret_key="$4"
    
    # Configure S3-compatible endpoint
    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    
    # Spaces endpoint format: https://REGION.digitaloceanspaces.com
    local endpoint="https://${region}.digitaloceanspaces.com"
    
    # Verify space access
    if ! aws s3 ls "s3://$space" --endpoint-url "$endpoint" >/dev/null 2>&1; then
        error "Cannot access DO Space: $space"
    fi
}

digitalocean_spaces_sync() {
    local source="$1"
    local space="$2"
    local prefix="${3:-}"
    local options="${4:-}"
    local region="${5:-nyc3}"
    
    info "Syncing to DO Spaces: $space/$prefix"
    
    local endpoint="https://${region}.digitaloceanspaces.com"
    
    retry_with_backoff 3 10 300 \
        aws s3 sync "$source" "s3://$space/$prefix" \
            --endpoint-url "$endpoint" \
            --delete $options
}

# Replicate to a single destination
replicate_to_destination() {
    local replica_name="$1"
    local source_path="$2"
    local config=$(get_replication_config)
    
    # Get replica configuration
    local replica=$(echo "$config" | jq -r ".replicas[] | select(.name == \"$replica_name\")")
    if [ -z "$replica" ] || [ "$replica" = "null" ]; then
        error "Replica not found: $replica_name"
    fi
    
    local provider=$(echo "$replica" | jq -r '.provider')
    local region=$(echo "$replica" | jq -r '.region')
    local bucket=$(echo "$replica" | jq -r '.bucket // .container // .space // ""')
    local prefix=$(echo "$replica" | jq -r '.prefix // ""')
    
    info "Replicating to $replica_name ($provider/$region)"
    
    # Record start time
    local start_time=$(start_timing)
    local status="failed"
    
    # Configure and sync based on provider
    case "$provider" in
        aws|s3)
            aws_s3_configure "$region" "$bucket"
            if aws_s3_sync "$source_path" "$bucket" "$prefix"; then
                status="success"
            fi
            ;;
        azure)
            local account=$(echo "$replica" | jq -r '.storage_account')
            azure_blob_configure "$account" "$bucket"
            if azure_blob_sync "$source_path" "$bucket" "$prefix"; then
                status="success"
            fi
            ;;
        gcp)
            local project=$(echo "$replica" | jq -r '.project')
            gcp_storage_configure "$project" "$bucket"
            if gcp_storage_sync "$source_path" "$bucket" "$prefix"; then
                status="success"
            fi
            ;;
        do|digitalocean)
            local access_key=$(echo "$replica" | jq -r '.access_key // ""')
            local secret_key=$(echo "$replica" | jq -r '.secret_key // ""')
            digitalocean_spaces_configure "$region" "$bucket" "$access_key" "$secret_key"
            if digitalocean_spaces_sync "$source_path" "$bucket" "$prefix" "" "$region"; then
                status="success"
            fi
            ;;
        *)
            error "Unknown provider: $provider"
            ;;
    esac
    
    # Record metrics
    local end_time=$(date +%s)
    record_replication_metrics "$replica_name" "$provider" "$start_time" "$end_time" "$status"
    
    # Update state
    update_replication_state "$replica_name" "$status"
    
    return $([ "$status" = "success" ] && echo 0 || echo 1)
}

# Replicate to all configured destinations
replicate_all() {
    local source_path="${1:-$CBOB_TARGET_PATH}"
    local parallel="${2:-1}"
    
    init_replication || return 1
    
    local config=$(get_replication_config)
    local replicas=$(echo "$config" | jq -r '.replicas[].name' 2>/dev/null)
    
    if [ -z "$replicas" ]; then
        warning "No replicas configured"
        return 0
    fi
    
    info "Starting replication to all destinations"
    
    local failed=0
    
    if [ "$parallel" -gt 1 ] && command -v parallel &> /dev/null; then
        info "Running parallel replication with $parallel workers"
        
        export -f replicate_to_destination
        echo "$replicas" | parallel -j "$parallel" replicate_to_destination {} "$source_path" || failed=$?
    else
        # Sequential replication
        while IFS= read -r replica_name; do
            if ! replicate_to_destination "$replica_name" "$source_path"; then
                ((failed++))
            fi
        done <<< "$replicas"
    fi
    
    if [ $failed -eq 0 ]; then
        info "✓ All replications completed successfully"
    else
        warning "⚠ $failed replications failed"
    fi
    
    return $failed
}

# Record replication metrics
record_replication_metrics() {
    local replica_name="$1"
    local provider="$2"
    local start_time="$3"
    local end_time="$4"
    local status="$5"
    
    local duration=$((end_time - start_time))
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create metrics entry
    local metrics=$(cat <<EOF
{
    "replica": "$replica_name",
    "provider": "$provider",
    "timestamp": "$timestamp",
    "duration_seconds": $duration,
    "status": "$status"
}
EOF
)
    
    # Update metrics file
    local temp_file=$(mktemp)
    jq --arg replica "$replica_name" --argjson metrics "$metrics" \
        '.replication[$replica] = $metrics' "$METRICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$METRICS_FILE"
    
    # Append to history
    echo "$metrics" >> "$METRICS_HISTORY/replication_${replica_name}_$(date +%Y%m).jsonl"
}

# Update replication state
update_replication_state() {
    local replica_name="$1"
    local status="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    local temp_file=$(mktemp)
    jq --arg replica "$replica_name" \
       --arg status "$status" \
       --arg timestamp "$timestamp" \
       '.replicas[$replica] = {"status": $status, "last_sync": $timestamp}' \
       "$REPLICATION_STATE" > "$temp_file" && \
        mv "$temp_file" "$REPLICATION_STATE"
}

# Check replication health
check_replication_health() {
    local replica_name="${1:-}"
    local config=$(get_replication_config)
    
    if [ -n "$replica_name" ]; then
        # Check specific replica
        local state=$(jq -r ".replicas[\"$replica_name\"]" "$REPLICATION_STATE" 2>/dev/null)
        if [ -z "$state" ] || [ "$state" = "null" ]; then
            echo "unknown"
            return 1
        fi
        
        local last_sync=$(echo "$state" | jq -r '.last_sync // ""')
        local status=$(echo "$state" | jq -r '.status // "unknown"')
        
        # Check if sync is stale (older than 24 hours)
        if [ -n "$last_sync" ]; then
            local last_sync_epoch=$(date -d "$last_sync" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_sync" +%s 2>/dev/null || echo 0)
            local now=$(date +%s)
            local age=$((now - last_sync_epoch))
            
            if [ $age -gt 86400 ]; then
                echo "stale"
                return 1
            fi
        fi
        
        echo "$status"
        return $([ "$status" = "success" ] && echo 0 || echo 1)
    else
        # Check all replicas
        local replicas=$(echo "$config" | jq -r '.replicas[].name' 2>/dev/null)
        local unhealthy=0
        
        while IFS= read -r replica; do
            local health=$(check_replication_health "$replica")
            if [ "$health" != "success" ]; then
                warning "Replica $replica is unhealthy: $health"
                ((unhealthy++))
            else
                info "Replica $replica is healthy"
            fi
        done <<< "$replicas"
        
        return $unhealthy
    fi
}

# Export functions
export -f init_replication validate_replication_config get_replication_config
export -f aws_s3_configure aws_s3_sync aws_s3_verify
export -f azure_blob_configure azure_blob_sync
export -f gcp_storage_configure gcp_storage_sync
export -f digitalocean_spaces_configure digitalocean_spaces_sync
export -f replicate_to_destination replicate_all
export -f record_replication_metrics update_replication_state check_replication_health