#!/bin/bash

# CBOB Metrics Library
# Functions for collecting and storing backup metrics

# Initialize metrics storage
init_metrics() {
    # Set metrics paths dynamically (after config is loaded)
    METRICS_FILE="${CBOB_METRICS_FILE:-${CBOB_BASE_PATH:-/var/lib/cbob}/metrics/cbob_metrics.json}"
    METRICS_HISTORY="${CBOB_METRICS_HISTORY:-${CBOB_BASE_PATH:-/var/lib/cbob}/metrics/history}"
    export METRICS_FILE METRICS_HISTORY

    local metrics_dir=$(dirname "$METRICS_FILE")
    mkdir -p "$metrics_dir" "$METRICS_HISTORY"
    
    if [ ! -f "$METRICS_FILE" ]; then
        echo '{"sync": {}, "restore": {}, "storage": {}, "performance": {}}' > "$METRICS_FILE"
    fi
}

# Record sync metrics
record_sync_metrics() {
    local cluster_id="$1"
    local start_time="$2"
    local end_time="$3"
    local status="$4"
    local bytes_synced="${5:-0}"
    local files_synced="${6:-0}"
    
    init_metrics
    
    local duration=$((end_time - start_time))
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create metrics entry
    local metrics=$(cat <<EOF
{
    "cluster_id": "$cluster_id",
    "timestamp": "$timestamp",
    "duration_seconds": $duration,
    "status": "$status",
    "bytes_synced": $bytes_synced,
    "files_synced": $files_synced,
    "bytes_per_second": $(awk "BEGIN {print $bytes_synced / $duration}" 2>/dev/null || echo 0)
}
EOF
)
    
    # Update current metrics
    local temp_file=$(mktemp)
    jq --arg cluster "$cluster_id" --argjson metrics "$metrics" \
        '.sync[$cluster] = $metrics' "$METRICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$METRICS_FILE"
    
    # Append to history
    echo "$metrics" >> "$METRICS_HISTORY/sync_${cluster_id}_$(date +%Y%m).jsonl"
    
    # Log to audit trail
    audit_log "SYNC_COMPLETE" "cluster=$cluster_id duration=$duration status=$status bytes=$bytes_synced"
}

# Record restore check metrics
record_restore_metrics() {
    local stanza="$1"
    local start_time="$2"
    local end_time="$3"
    local status="$4"
    local backups_checked="${5:-0}"
    
    init_metrics
    
    local duration=$((end_time - start_time))
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create metrics entry
    local metrics=$(cat <<EOF
{
    "stanza": "$stanza",
    "timestamp": "$timestamp",
    "duration_seconds": $duration,
    "status": "$status",
    "backups_checked": $backups_checked
}
EOF
)
    
    # Update current metrics
    local temp_file=$(mktemp)
    jq --arg stanza "$stanza" --argjson metrics "$metrics" \
        '.restore[$stanza] = $metrics' "$METRICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$METRICS_FILE"
    
    # Append to history
    echo "$metrics" >> "$METRICS_HISTORY/restore_${stanza}_$(date +%Y%m).jsonl"
    
    # Log to audit trail
    audit_log "RESTORE_CHECK_COMPLETE" "stanza=$stanza duration=$duration status=$status"
}

# Record storage metrics
record_storage_metrics() {
    local cluster_id="$1"
    local target_path="${CBOB_TARGET_PATH:-/var/lib/cbob/backups}"
    local backup_path="${target_path}/backup/${cluster_id}"
    local archive_path="${target_path}/archive/${cluster_id}"
    
    init_metrics
    
    # Calculate sizes
    local backup_size=0
    local archive_size=0
    local backup_count=0
    
    if [ -d "$backup_path" ]; then
        backup_size=$(du -sb "$backup_path" 2>/dev/null | cut -f1 || echo 0)
        backup_count=$(find "$backup_path" -name "*.manifest" -type f 2>/dev/null | wc -l)
    fi
    
    if [ -d "$archive_path" ]; then
        archive_size=$(du -sb "$archive_path" 2>/dev/null | cut -f1 || echo 0)
    fi
    
    local total_size=$((backup_size + archive_size))
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create metrics entry
    local metrics=$(cat <<EOF
{
    "cluster_id": "$cluster_id",
    "timestamp": "$timestamp",
    "backup_size_bytes": $backup_size,
    "archive_size_bytes": $archive_size,
    "total_size_bytes": $total_size,
    "backup_count": $backup_count,
    "backup_size_human": "$(human_readable_size $backup_size)",
    "archive_size_human": "$(human_readable_size $archive_size)",
    "total_size_human": "$(human_readable_size $total_size)"
}
EOF
)
    
    # Update current metrics
    local temp_file=$(mktemp)
    jq --arg cluster "$cluster_id" --argjson metrics "$metrics" \
        '.storage[$cluster] = $metrics' "$METRICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$METRICS_FILE"
    
    # Append to history
    echo "$metrics" >> "$METRICS_HISTORY/storage_${cluster_id}_$(date +%Y%m).jsonl"
}

# Record performance metrics
record_performance_metrics() {
    local operation="$1"
    local metric_name="$2"
    local value="$3"
    
    init_metrics
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create metrics entry
    local metrics=$(cat <<EOF
{
    "operation": "$operation",
    "metric": "$metric_name",
    "value": $value,
    "timestamp": "$timestamp"
}
EOF
)
    
    # Update current metrics
    local temp_file=$(mktemp)
    jq --arg op "$operation" --arg metric "$metric_name" --argjson value "$value" \
        '.performance[$op][$metric] = $value' "$METRICS_FILE" > "$temp_file" && \
        mv "$temp_file" "$METRICS_FILE"
}

# Get current metrics
get_metrics() {
    local filter="${1:-}"

    # Ensure metrics paths are set
    METRICS_FILE="${CBOB_METRICS_FILE:-${CBOB_BASE_PATH:-/var/lib/cbob}/metrics/cbob_metrics.json}"

    if [ ! -f "$METRICS_FILE" ]; then
        echo "{}"
        return
    fi
    
    if [ -n "$filter" ]; then
        jq ".$filter" "$METRICS_FILE"
    else
        cat "$METRICS_FILE"
    fi
}

# Get metrics summary
get_metrics_summary() {
    local period="${1:-24h}"
    
    init_metrics
    
    # Calculate time range
    local now=$(date +%s)
    local start_time
    case "$period" in
        1h) start_time=$((now - 3600)) ;;
        24h) start_time=$((now - 86400)) ;;
        7d) start_time=$((now - 604800)) ;;
        30d) start_time=$((now - 2592000)) ;;
        *) start_time=$((now - 86400)) ;;
    esac
    
    # Aggregate metrics from history
    local summary=$(cat <<EOF
{
    "period": "$period",
    "start_time": "$(date -u -d @$start_time +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r $start_time +%Y-%m-%dT%H:%M:%SZ)",
    "end_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "sync": {
        "total": 0,
        "successful": 0,
        "failed": 0,
        "total_bytes": 0,
        "average_duration": 0
    },
    "restore": {
        "total": 0,
        "successful": 0,
        "failed": 0,
        "average_duration": 0
    }
}
EOF
)
    
    echo "$summary"
}

# Generate metrics report
generate_metrics_report() {
    init_metrics
    local output_file="${1:-${CBOB_BASE_PATH:-/var/lib/cbob}/metrics/report_$(date +%Y%m%d_%H%M%S).txt}"

    cat > "$output_file" << EOF
CBOB Metrics Report
Generated: $(date)
===================

Current Metrics:
$(get_metrics | jq -r '.')

Storage Summary:
$(get_metrics storage | jq -r 'to_entries[] | "- \(.key): \(.value.total_size_human) (\(.value.backup_count) backups)"')

Recent Sync Operations:
$(get_metrics sync | jq -r 'to_entries[] | "- \(.key): \(.value.status) (duration: \(.value.duration_seconds)s, size: \(.value.bytes_synced) bytes)"')

Recent Restore Checks:
$(get_metrics restore | jq -r 'to_entries[] | "- \(.key): \(.value.status) (duration: \(.value.duration_seconds)s)"')

Performance Metrics:
$(get_metrics performance | jq -r '.')
EOF
    
    info "Metrics report generated: $output_file"
}

# Clean old metrics
cleanup_old_metrics() {
    local days="${1:-90}"
    
    info "Cleaning metrics older than $days days"
    
    # Clean old history files
    find "$METRICS_HISTORY" -name "*.jsonl" -mtime +$days -exec rm {} \;
    
    # Archive current month's data if needed
    local archive_dir="$METRICS_HISTORY/archive"
    mkdir -p "$archive_dir"
    
    # Compress old monthly files
    find "$METRICS_HISTORY" -name "*.jsonl" -mtime +30 ! -name "*.gz" -exec gzip {} \;
}

# Export Prometheus metrics
export_prometheus_metrics() {
    local output_file="${1:-/tmp/cbob_metrics.prom}"
    
    init_metrics
    
    # Generate Prometheus format metrics
    cat > "$output_file" << EOF
# HELP cbob_sync_duration_seconds Backup sync duration in seconds
# TYPE cbob_sync_duration_seconds gauge
EOF
    
    get_metrics sync | jq -r 'to_entries[] | "cbob_sync_duration_seconds{cluster=\"\(.key)\"} \(.value.duration_seconds)"' >> "$output_file"
    
    cat >> "$output_file" << EOF

# HELP cbob_sync_bytes_total Total bytes synced
# TYPE cbob_sync_bytes_total counter
EOF
    
    get_metrics sync | jq -r 'to_entries[] | "cbob_sync_bytes_total{cluster=\"\(.key)\"} \(.value.bytes_synced)"' >> "$output_file"
    
    cat >> "$output_file" << EOF

# HELP cbob_backup_size_bytes Current backup size in bytes
# TYPE cbob_backup_size_bytes gauge
EOF
    
    get_metrics storage | jq -r 'to_entries[] | "cbob_backup_size_bytes{cluster=\"\(.key)\"} \(.value.total_size_bytes)"' >> "$output_file"
    
    echo "$output_file"
}

# Track operation timing
start_timing() {
    echo $(date +%s)
}

end_timing() {
    local start_time="$1"
    local end_time=$(date +%s)
    echo $((end_time - start_time))
}

# Export metrics functions
export -f init_metrics record_sync_metrics record_restore_metrics record_storage_metrics
export -f record_performance_metrics get_metrics get_metrics_summary
export -f generate_metrics_report cleanup_old_metrics export_prometheus_metrics
export -f start_timing end_timing