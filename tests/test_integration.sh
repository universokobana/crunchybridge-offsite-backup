#!/bin/bash

# Integration tests for CBOB
# Tests the complete workflow including Docker and CLI

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TEST_DATA_DIR="${TEST_DIR}/data"
TEST_RESULTS_DIR="${TEST_DIR}/results"
TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
setup_test_env() {
    echo "Setting up test environment..."
    
    # Create test directories
    mkdir -p "$TEST_DATA_DIR" "$TEST_RESULTS_DIR"
    
    # Create test configuration
    cat > "$TEST_DATA_DIR/test_config.env" << EOF
CBOB_CRUNCHY_API_KEY=test-api-key-123456789
CBOB_CRUNCHY_CLUSTERS=test-cluster-1,test-cluster-2
CBOB_TARGET_PATH=/tmp/cbob-test-backups
CBOB_LOG_PATH=/tmp/cbob-test-logs
CBOB_DRY_RUN=true
CBOB_LOG_LEVEL=debug
EOF
    
    # Export test configuration
    export CBOB_CONFIG_FILE="$TEST_DATA_DIR/test_config.env"
    source "$CBOB_CONFIG_FILE"
}

# Cleanup test environment
cleanup_test_env() {
    echo "Cleaning up test environment..."
    
    # Stop any running containers
    docker-compose -f "$PROJECT_ROOT/docker-compose.yml" down 2>/dev/null || true
    
    # Remove test data
    rm -rf /tmp/cbob-test-*
}

# Test result logging
log_test_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [ "$result" = "PASS" ]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} $test_name"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}✗${NC} $test_name"
        if [ -n "$message" ]; then
            echo "  Error: $message"
        fi
    fi
    
    # Log to results file
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $test_name | $result | $message" >> "$TEST_RESULTS_DIR/results_$TEST_TIMESTAMP.log"
}

# Test: CLI installation
test_cli_installation() {
    local test_name="CLI Installation"
    
    # Check if cbob command exists
    if [ -f "$PROJECT_ROOT/bin/cbob" ] && [ -x "$PROJECT_ROOT/bin/cbob" ]; then
        # Test help command
        if "$PROJECT_ROOT/bin/cbob" help >/dev/null 2>&1; then
            log_test_result "$test_name" "PASS"
        else
            log_test_result "$test_name" "FAIL" "cbob help command failed"
        fi
    else
        log_test_result "$test_name" "FAIL" "cbob command not found or not executable"
    fi
}

# Test: Configuration validation
test_config_validation() {
    local test_name="Configuration Validation"
    
    # Test valid configuration
    if "$PROJECT_ROOT/bin/cbob" config validate 2>&1 | grep -q "Configuration is valid"; then
        log_test_result "$test_name - Valid Config" "PASS"
    else
        log_test_result "$test_name - Valid Config" "FAIL" "Valid config not recognized"
    fi
    
    # Test invalid configuration
    local original_key="$CBOB_CRUNCHY_API_KEY"
    export CBOB_CRUNCHY_API_KEY=""
    
    if "$PROJECT_ROOT/bin/cbob" config validate 2>&1 | grep -q "Missing required"; then
        log_test_result "$test_name - Invalid Config Detection" "PASS"
    else
        log_test_result "$test_name - Invalid Config Detection" "FAIL" "Invalid config not detected"
    fi
    
    export CBOB_CRUNCHY_API_KEY="$original_key"
}

# Test: Docker build
test_docker_build() {
    local test_name="Docker Build"
    
    cd "$PROJECT_ROOT"
    
    if docker build -t cbob:test . >/dev/null 2>&1; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "Docker build failed"
    fi
}

# Test: Docker compose
test_docker_compose() {
    local test_name="Docker Compose"
    
    cd "$PROJECT_ROOT"
    
    # Start services
    if docker-compose up -d >/dev/null 2>&1; then
        sleep 10  # Wait for services to start
        
        # Check if container is running
        if docker-compose ps | grep -q "cbob.*Up"; then
            log_test_result "$test_name - Start" "PASS"
        else
            log_test_result "$test_name - Start" "FAIL" "Container not running"
        fi
        
        # Stop services
        if docker-compose down >/dev/null 2>&1; then
            log_test_result "$test_name - Stop" "PASS"
        else
            log_test_result "$test_name - Stop" "FAIL" "Failed to stop services"
        fi
    else
        log_test_result "$test_name" "FAIL" "docker-compose up failed"
    fi
}

# Test: Sync dry run
test_sync_dry_run() {
    local test_name="Sync Dry Run"
    
    # Run sync in dry-run mode
    if "$PROJECT_ROOT/bin/cbob" sync --dry-run 2>&1 | grep -q "DRY-RUN"; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "Dry run mode not working"
    fi
}

# Test: Metrics collection
test_metrics_collection() {
    local test_name="Metrics Collection"
    
    # Source metrics library
    source "$PROJECT_ROOT/lib/cbob_metrics.sh"
    
    # Initialize metrics
    export CBOB_METRICS_FILE="/tmp/cbob-test-metrics.json"
    init_metrics
    
    # Record test metrics
    record_sync_metrics "test-cluster" "1000" "1100" "success" "1048576" "10"
    
    # Check if metrics were recorded
    if get_metrics | grep -q "test-cluster"; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "Metrics not recorded"
    fi
}

# Test: Security functions
test_security_functions() {
    local test_name="Security Functions"
    
    # Source security library
    source "$PROJECT_ROOT/lib/cbob_security.sh"
    
    # Test input validation
    if validate_cluster_id "valid-cluster-123" 2>/dev/null; then
        log_test_result "$test_name - Valid Input" "PASS"
    else
        log_test_result "$test_name - Valid Input" "FAIL" "Valid input rejected"
    fi
    
    # Test invalid input detection
    if ! validate_cluster_id "../../../etc/passwd" 2>/dev/null; then
        log_test_result "$test_name - Invalid Input Detection" "PASS"
    else
        log_test_result "$test_name - Invalid Input Detection" "FAIL" "Invalid input not detected"
    fi
}

# Test: Parallel operations
test_parallel_operations() {
    local test_name="Parallel Operations"
    
    # Test parallel sync command
    if "$PROJECT_ROOT/bin/cbob" sync --parallel 2 --dry-run 2>&1 | grep -q "parallel"; then
        log_test_result "$test_name" "PASS"
    else
        log_test_result "$test_name" "FAIL" "Parallel option not recognized"
    fi
}

# Performance test: Command execution time
test_performance_cli() {
    local test_name="CLI Performance"
    
    # Time help command
    local start_time=$(date +%s%N)
    "$PROJECT_ROOT/bin/cbob" help >/dev/null 2>&1
    local end_time=$(date +%s%N)
    
    local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [ $duration -lt 100 ]; then  # Should complete in less than 100ms
        log_test_result "$test_name - Help Command (<100ms)" "PASS"
    else
        log_test_result "$test_name - Help Command" "FAIL" "Too slow: ${duration}ms"
    fi
}

# Main test runner
main() {
    echo "CBOB Integration Tests"
    echo "======================"
    echo
    
    # Setup
    setup_test_env
    
    # Run tests
    echo "Running tests..."
    echo
    
    test_cli_installation
    test_config_validation
    test_docker_build
    test_docker_compose
    test_sync_dry_run
    test_metrics_collection
    test_security_functions
    test_parallel_operations
    test_performance_cli
    
    echo
    echo "Test Summary"
    echo "============"
    echo "Total tests: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    echo "Results saved to: $TEST_RESULTS_DIR/results_$TEST_TIMESTAMP.log"
    
    # Cleanup
    cleanup_test_env
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests
main "$@"