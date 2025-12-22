#!/bin/bash

# Tests for CBOB Multi-Region Replication
# Tests replication configuration, providers, and sync operations

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TEST_DATA_DIR="${TEST_DIR}/replication_test_data"
TEST_CONFIG_DIR="${TEST_DATA_DIR}/config"
TEST_STATE_DIR="${TEST_DATA_DIR}/state"

# Source libraries
source "$PROJECT_ROOT/lib/cbob_common.sh"
source "$PROJECT_ROOT/lib/cbob_replication.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup test environment
setup_test_env() {
    echo "Setting up replication test environment..."
    
    # Create test directories
    mkdir -p "$TEST_CONFIG_DIR" "$TEST_STATE_DIR" "$TEST_DATA_DIR/backups"
    
    # Set test paths
    export CBOB_REPLICATION_CONFIG="$TEST_CONFIG_DIR/replication.yaml"
    export CBOB_REPLICATION_STATE="$TEST_STATE_DIR/replication.json"
    export CBOB_TARGET_PATH="$TEST_DATA_DIR/backups"
    export CBOB_BASE_PATH="$TEST_DATA_DIR"
    
    # Create test backup data
    mkdir -p "$TEST_DATA_DIR/backups/backup/test-cluster"
    echo "test backup data" > "$TEST_DATA_DIR/backups/backup/test-cluster/test.dat"
    
    # Create test configuration
    cat > "$CBOB_REPLICATION_CONFIG" << EOF
replication:
  primary:
    provider: aws
    region: us-east-1
    bucket: test-primary-bucket
    
  replicas:
    - name: test-aws-eu
      provider: aws
      region: eu-west-1
      bucket: test-eu-bucket
      prefix: backups/
      
    - name: test-azure
      provider: azure
      region: westus2
      storage_account: testaccount
      container: test-container
      
    - name: test-gcp
      provider: gcp
      project: test-project
      region: us-central1
      bucket: test-gcp-bucket
      
    - name: test-do
      provider: digitalocean
      region: nyc3
      space: test-space
      access_key: test-key
      secret_key: test-secret
EOF
}

# Cleanup test environment
cleanup_test_env() {
    echo "Cleaning up test environment..."
    rm -rf "$TEST_DATA_DIR"
}

# Test result logging
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [ "$expected" = "$actual" ]; then
        ((TESTS_PASSED++))
        echo "✓ $message"
    else
        ((TESTS_FAILED++))
        echo "✗ $message"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
    fi
}

assert_success() {
    local exit_code="$1"
    local message="${2:-}"
    
    ((TESTS_RUN++))
    
    if [ "$exit_code" -eq 0 ]; then
        ((TESTS_PASSED++))
        echo "✓ $message"
    else
        ((TESTS_FAILED++))
        echo "✗ $message (exit code: $exit_code)"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo "✓ $message"
    else
        ((TESTS_FAILED++))
        echo "✗ $message"
        echo "  Expected to contain: $needle"
        echo "  Actual: $haystack"
    fi
}

# Test: Replication initialization
test_replication_init() {
    echo "Testing replication initialization..."
    
    # Test init_replication
    if init_replication 2>/dev/null; then
        assert_success 0 "Replication initialization"
    else
        assert_success 1 "Replication initialization"
    fi
    
    # Check state file created
    if [ -f "$CBOB_REPLICATION_STATE" ]; then
        assert_success 0 "State file created"
    else
        assert_success 1 "State file created"
    fi
}

# Test: Configuration validation
test_config_validation() {
    echo "Testing configuration validation..."
    
    # Test valid configuration
    if validate_replication_config; then
        assert_success 0 "Valid configuration accepted"
    else
        assert_success 1 "Valid configuration accepted"
    fi
    
    # Test invalid configuration
    local original_config="$CBOB_REPLICATION_CONFIG"
    CBOB_REPLICATION_CONFIG="$TEST_CONFIG_DIR/invalid.yaml"
    
    # Missing replication section
    echo "invalid: true" > "$CBOB_REPLICATION_CONFIG"
    if ! validate_replication_config 2>/dev/null; then
        assert_success 0 "Invalid config rejected (missing replication)"
    else
        assert_success 1 "Invalid config rejected (missing replication)"
    fi
    
    # Missing primary
    cat > "$CBOB_REPLICATION_CONFIG" << EOF
replication:
  replicas: []
EOF
    if ! validate_replication_config 2>/dev/null; then
        assert_success 0 "Invalid config rejected (missing primary)"
    else
        assert_success 1 "Invalid config rejected (missing primary)"
    fi
    
    CBOB_REPLICATION_CONFIG="$original_config"
}

# Test: Get replication configuration
test_get_config() {
    echo "Testing configuration retrieval..."
    
    local config=$(get_replication_config)
    
    # Check primary
    local primary_provider=$(echo "$config" | jq -r '.primary.provider')
    assert_equals "aws" "$primary_provider" "Primary provider"
    
    # Check replicas
    local replica_count=$(echo "$config" | jq '.replicas | length')
    assert_equals "4" "$replica_count" "Replica count"
    
    # Check specific replica
    local first_replica=$(echo "$config" | jq -r '.replicas[0].name')
    assert_equals "test-aws-eu" "$first_replica" "First replica name"
}

# Test: Provider configuration
test_provider_configuration() {
    echo "Testing provider configuration..."
    
    # Test AWS S3 configuration
    # Mock AWS CLI for testing
    aws() {
        if [[ "$*" == *"s3 ls"* ]]; then
            return 0  # Simulate success
        fi
        command aws "$@"
    }
    export -f aws
    
    if aws_s3_configure "us-east-1" "test-bucket" 2>/dev/null; then
        assert_success 0 "AWS S3 configuration"
    else
        assert_success 1 "AWS S3 configuration"
    fi
    
    # Test environment variables set
    assert_equals "us-east-1" "$AWS_DEFAULT_REGION" "AWS region set"
}

# Test: Replication state management
test_state_management() {
    echo "Testing replication state management..."
    
    # Initialize state
    init_replication
    
    # Update state
    update_replication_state "test-replica" "success"
    
    # Check state file
    local state=$(cat "$CBOB_REPLICATION_STATE")
    local replica_status=$(echo "$state" | jq -r '.replicas["test-replica"].status')
    assert_equals "success" "$replica_status" "State update"
    
    # Check timestamp
    local last_sync=$(echo "$state" | jq -r '.replicas["test-replica"].last_sync')
    if [ -n "$last_sync" ] && [ "$last_sync" != "null" ]; then
        assert_success 0 "Timestamp recorded"
    else
        assert_success 1 "Timestamp recorded"
    fi
}

# Test: Health checks
test_health_checks() {
    echo "Testing replication health checks..."
    
    # Initialize and set state
    init_replication
    update_replication_state "test-aws-eu" "success"
    
    # Check specific replica health
    local health=$(check_replication_health "test-aws-eu")
    assert_equals "success" "$health" "Healthy replica status"
    
    # Simulate stale replica
    local temp_file=$(mktemp)
    jq '.replicas["test-aws-eu"].last_sync = "2020-01-01T00:00:00Z"' "$CBOB_REPLICATION_STATE" > "$temp_file"
    mv "$temp_file" "$CBOB_REPLICATION_STATE"
    
    health=$(check_replication_health "test-aws-eu")
    assert_equals "stale" "$health" "Stale replica detected"
}

# Test: Metrics recording
test_metrics_recording() {
    echo "Testing metrics recording..."
    
    # Initialize metrics
    export CBOB_METRICS_FILE="$TEST_DATA_DIR/metrics.json"
    init_metrics
    
    # Record replication metrics
    record_replication_metrics "test-replica" "aws" "1000" "1100" "success"
    
    # Check metrics
    local metrics=$(cat "$CBOB_METRICS_FILE")
    local replica_metrics=$(echo "$metrics" | jq '.replication["test-replica"]')
    
    if [ -n "$replica_metrics" ] && [ "$replica_metrics" != "null" ]; then
        assert_success 0 "Metrics recorded"
        
        local duration=$(echo "$replica_metrics" | jq -r '.duration_seconds')
        assert_equals "100" "$duration" "Duration calculated correctly"
    else
        assert_success 1 "Metrics recorded"
    fi
}

# Test: CLI commands
test_cli_commands() {
    echo "Testing CLI commands..."
    
    # Test help
    if "$PROJECT_ROOT/bin/cbob" replicate help >/dev/null 2>&1; then
        assert_success 0 "Replicate help command"
    else
        assert_success 1 "Replicate help command"
    fi
    
    # Test status command
    init_replication
    local output=$("$PROJECT_ROOT/bin/cbob" replicate status 2>&1 || true)
    assert_contains "$output" "Primary Storage" "Status shows primary"
    assert_contains "$output" "Replicas" "Status shows replicas"
    
    # Test config command
    output=$("$PROJECT_ROOT/bin/cbob" replicate config 2>&1 || true)
    assert_contains "$output" "replication:" "Config shows YAML"
}

# Test: Provider-specific sync (mock)
test_provider_sync_mock() {
    echo "Testing provider sync operations (mocked)..."
    
    # Mock AWS sync
    aws() {
        if [[ "$*" == *"s3 sync"* ]]; then
            echo "Simulated sync to S3"
            return 0
        fi
        return 1
    }
    export -f aws
    
    # Test sync
    if aws_s3_sync "$TEST_DATA_DIR/backups" "test-bucket" "prefix/" 2>&1 | grep -q "Simulated"; then
        assert_success 0 "AWS S3 sync (mocked)"
    else
        assert_success 1 "AWS S3 sync (mocked)"
    fi
}

# Main test runner
main() {
    echo "CBOB Replication Tests"
    echo "====================="
    echo
    
    # Setup
    setup_test_env
    
    # Run tests
    test_replication_init
    echo
    test_config_validation
    echo
    test_get_config
    echo
    test_provider_configuration
    echo
    test_state_management
    echo
    test_health_checks
    echo
    test_metrics_recording
    echo
    test_cli_commands
    echo
    test_provider_sync_mock
    echo
    
    # Summary
    echo "Test Summary"
    echo "============"
    echo "Total tests: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    # Cleanup
    cleanup_test_env
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        echo
        echo "✓ All tests passed!"
        exit 0
    else
        echo
        echo "✗ Some tests failed!"
        exit 1
    fi
}

# Run tests
main "$@"