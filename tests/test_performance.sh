#!/bin/bash

# Performance tests for CBOB
# Benchmarks various operations and generates performance reports

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
PERF_RESULTS_DIR="${TEST_DIR}/performance"
PERF_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create results directory
mkdir -p "$PERF_RESULTS_DIR"

# Source libraries
source "$PROJECT_ROOT/lib/cbob_common.sh"
source "$PROJECT_ROOT/lib/cbob_metrics.sh"

# Performance test utilities
measure_time() {
    local cmd="$1"
    local iterations="${2:-10}"
    local results=()
    
    echo "Measuring: $cmd (${iterations} iterations)"
    
    for i in $(seq 1 $iterations); do
        local start=$(date +%s%N)
        eval "$cmd" >/dev/null 2>&1
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))  # Convert to milliseconds
        results+=($duration)
    done
    
    # Calculate statistics
    local sum=0
    local min=${results[0]}
    local max=${results[0]}
    
    for val in "${results[@]}"; do
        sum=$((sum + val))
        if [ $val -lt $min ]; then min=$val; fi
        if [ $val -gt $max ]; then max=$val; fi
    done
    
    local avg=$((sum / iterations))
    
    echo "  Average: ${avg}ms"
    echo "  Min: ${min}ms"
    echo "  Max: ${max}ms"
    echo
    
    # Save results
    echo "$cmd,$iterations,$avg,$min,$max" >> "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv"
}

# Test: CLI command performance
test_cli_performance() {
    echo "=== CLI Command Performance ==="
    echo
    
    # Initialize CSV
    echo "Command,Iterations,Avg(ms),Min(ms),Max(ms)" > "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv"
    
    # Test various commands
    measure_time "$PROJECT_ROOT/bin/cbob help" 50
    measure_time "$PROJECT_ROOT/bin/cbob config show" 20
    measure_time "$PROJECT_ROOT/bin/cbob config validate" 20
    measure_time "$PROJECT_ROOT/bin/cbob sync --help" 50
}

# Test: Configuration loading performance
test_config_loading() {
    echo "=== Configuration Loading Performance ==="
    echo
    
    # Create test configs of different sizes
    local small_config="/tmp/cbob_small.conf"
    local medium_config="/tmp/cbob_medium.conf"
    local large_config="/tmp/cbob_large.conf"
    
    # Small config (basic)
    cat > "$small_config" << EOF
CBOB_CRUNCHY_API_KEY=test-key
CBOB_CRUNCHY_CLUSTERS=cluster1
CBOB_TARGET_PATH=/tmp/test
EOF
    
    # Medium config (typical)
    cat > "$medium_config" << EOF
CBOB_CRUNCHY_API_KEY=test-key-123456789
CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2,cluster3,cluster4,cluster5
CBOB_TARGET_PATH=/mnt/backups
CBOB_LOG_PATH=/var/log/cbob
CBOB_RETENTION_FULL=7
CBOB_SLACK_CLI_TOKEN=xoxb-test-token
CBOB_SLACK_CHANNEL=#backup-alerts
CBOB_SYNC_HEARTBEAT_URL=https://example.com/heartbeat
EOF
    
    # Large config (many clusters)
    echo "CBOB_CRUNCHY_API_KEY=test-key-123456789" > "$large_config"
    echo -n "CBOB_CRUNCHY_CLUSTERS=" >> "$large_config"
    for i in {1..50}; do
        echo -n "cluster$i," >> "$large_config"
    done
    echo >> "$large_config"
    cat >> "$large_config" << EOF
CBOB_TARGET_PATH=/mnt/backups
CBOB_LOG_PATH=/var/log/cbob
CBOB_RETENTION_FULL=30
EOF
    
    # Test loading performance
    export CBOB_CONFIG_FILE="$small_config"
    measure_time "source $PROJECT_ROOT/lib/cbob_common.sh && load_config" 100
    
    export CBOB_CONFIG_FILE="$medium_config"
    measure_time "source $PROJECT_ROOT/lib/cbob_common.sh && load_config" 50
    
    export CBOB_CONFIG_FILE="$large_config"
    measure_time "source $PROJECT_ROOT/lib/cbob_common.sh && load_config" 20
    
    # Cleanup
    rm -f "$small_config" "$medium_config" "$large_config"
}

# Test: Metrics operations performance
test_metrics_performance() {
    echo "=== Metrics Operations Performance ==="
    echo
    
    export CBOB_METRICS_FILE="/tmp/cbob_perf_metrics.json"
    
    # Test metrics recording
    measure_time "record_sync_metrics 'test-cluster' '1000' '1100' 'success' '1048576' '10'" 100
    measure_time "record_storage_metrics 'test-cluster'" 50
    measure_time "get_metrics" 100
    measure_time "get_metrics_summary '24h'" 50
    
    # Cleanup
    rm -f "$CBOB_METRICS_FILE"
}

# Test: Large file operations
test_file_operations() {
    echo "=== File Operations Performance ==="
    echo
    
    local test_dir="/tmp/cbob_perf_test"
    mkdir -p "$test_dir"
    
    # Create test files of different sizes
    dd if=/dev/zero of="$test_dir/1mb.dat" bs=1M count=1 2>/dev/null
    dd if=/dev/zero of="$test_dir/10mb.dat" bs=1M count=10 2>/dev/null
    dd if=/dev/zero of="$test_dir/100mb.dat" bs=1M count=100 2>/dev/null
    
    # Test file size calculations
    measure_time "du -sb $test_dir/1mb.dat" 100
    measure_time "du -sb $test_dir/10mb.dat" 50
    measure_time "du -sb $test_dir/100mb.dat" 20
    
    # Cleanup
    rm -rf "$test_dir"
}

# Test: JSON parsing performance
test_json_performance() {
    echo "=== JSON Parsing Performance ==="
    echo
    
    # Create test JSON files
    local small_json="/tmp/small.json"
    local medium_json="/tmp/medium.json"
    local large_json="/tmp/large.json"
    
    # Small JSON
    echo '{"key": "value"}' > "$small_json"
    
    # Medium JSON
    echo '{"clusters": [' > "$medium_json"
    for i in {1..10}; do
        echo '{"id": "cluster'$i'", "status": "active"},' >> "$medium_json"
    done
    echo '{}]}' >> "$medium_json"
    
    # Large JSON
    echo '{"clusters": [' > "$large_json"
    for i in {1..100}; do
        echo '{"id": "cluster'$i'", "status": "active", "metrics": {"size": 1048576, "count": 100}},' >> "$large_json"
    done
    echo '{}]}' >> "$large_json"
    
    # Test parsing
    measure_time "jq '.key' $small_json" 100
    measure_time "jq '.clusters | length' $medium_json" 50
    measure_time "jq '.clusters | length' $large_json" 20
    
    # Cleanup
    rm -f "$small_json" "$medium_json" "$large_json"
}

# Test: Concurrent operations
test_concurrent_operations() {
    echo "=== Concurrent Operations Performance ==="
    echo
    
    # Test concurrent metric writes
    local concurrent_test() {
        for i in {1..10}; do
            record_performance_metrics "test" "metric$i" "$RANDOM" &
        done
        wait
    }
    
    export CBOB_METRICS_FILE="/tmp/cbob_concurrent_test.json"
    measure_time "concurrent_test" 10
    
    # Cleanup
    rm -f "$CBOB_METRICS_FILE"
}

# Generate performance report
generate_performance_report() {
    local report_file="$PERF_RESULTS_DIR/performance_report_$PERF_TIMESTAMP.txt"
    
    cat > "$report_file" << EOF
CBOB Performance Test Report
Generated: $(date)
==========================

System Information:
- Hostname: $(hostname)
- CPU: $(nproc) cores
- Memory: $(free -h | grep Mem | awk '{print $2}')
- OS: $(uname -s) $(uname -r)

Test Results:
EOF
    
    if [ -f "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv" ]; then
        echo >> "$report_file"
        echo "Command Performance Summary:" >> "$report_file"
        echo "===========================" >> "$report_file"
        column -t -s',' "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv" >> "$report_file"
    fi
    
    echo >> "$report_file"
    echo "Performance Recommendations:" >> "$report_file"
    echo "===========================" >> "$report_file"
    
    # Analyze results and provide recommendations
    if [ -f "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv" ]; then
        while IFS=',' read -r cmd iterations avg min max; do
            if [[ "$cmd" == "Command" ]]; then continue; fi
            if [ "$avg" -gt 1000 ]; then
                echo "- $cmd is slow (avg: ${avg}ms). Consider optimization." >> "$report_file"
            fi
        done < "$PERF_RESULTS_DIR/results_$PERF_TIMESTAMP.csv"
    fi
    
    echo >> "$report_file"
    echo "Report saved to: $report_file"
    cat "$report_file"
}

# Main performance test runner
main() {
    echo "CBOB Performance Tests"
    echo "====================="
    echo "Started: $(date)"
    echo
    
    # Run performance tests
    test_cli_performance
    test_config_loading
    test_metrics_performance
    test_file_operations
    test_json_performance
    test_concurrent_operations
    
    # Generate report
    echo
    generate_performance_report
    
    echo
    echo "Performance tests completed: $(date)"
}

# Run tests
main "$@"