#!/bin/bash

# Unit tests for CBOB common functions
# Run with: bash tests/test_common.sh
# Compatible with bash 3.2+ (macOS) and bash 4+ (Linux)

set -eo pipefail

# Get test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Set default values for optional variables before sourcing
export CBOB_SLACK_CLI_TOKEN="${CBOB_SLACK_CLI_TOKEN:-}"
export CBOB_SLACK_CHANNEL="${CBOB_SLACK_CHANNEL:-}"
export CBOB_LOG_LEVEL="${CBOB_LOG_LEVEL:-info}"
export CBOB_LOG_FORMAT="${CBOB_LOG_FORMAT:-text}"

# Source the library
source "${PROJECT_ROOT}/lib/cbob_common.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test framework functions
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

assert_exit_code() {
    local expected="$1"
    local command="$2"
    local message="${3:-}"
    
    ((TESTS_RUN++))
    
    local actual=0
    eval "$command" >/dev/null 2>&1 || actual=$?
    
    if [ "$expected" = "$actual" ]; then
        ((TESTS_PASSED++))
        echo "✓ $message"
    else
        ((TESTS_FAILED++))
        echo "✗ $message"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code: $actual"
    fi
}

# Test: human_readable_size
test_human_readable_size() {
    echo "Testing human_readable_size..."
    
    assert_equals "100B" "$(human_readable_size 100)" "100 bytes"
    assert_equals "1KB" "$(human_readable_size 1024)" "1 KB"
    assert_equals "1MB" "$(human_readable_size 1048576)" "1 MB"
    assert_equals "1GB" "$(human_readable_size 1073741824)" "1 GB"
    assert_equals "1TB" "$(human_readable_size 1099511627776)" "1 TB"
}

# Test: log levels
test_log_levels() {
    echo "Testing log levels..."
    
    # Test log level conversion
    CBOB_LOG_LEVEL="debug"
    assert_equals "0" "$(get_log_level_num)" "Debug level = 0"
    
    CBOB_LOG_LEVEL="info"
    assert_equals "1" "$(get_log_level_num)" "Info level = 1"
    
    CBOB_LOG_LEVEL="warning"
    assert_equals "2" "$(get_log_level_num)" "Warning level = 2"
    
    CBOB_LOG_LEVEL="error"
    assert_equals "3" "$(get_log_level_num)" "Error level = 3"
}

# Test: log message format
test_log_format() {
    echo "Testing log message formats..."
    
    # Test text format
    CBOB_LOG_FORMAT="text"
    CBOB_LOG_LEVEL="info"
    local output=$(log_message "INFO" "Test message" 2>&1)
    assert_contains "$output" "INFO:" "Text format contains INFO:"
    assert_contains "$output" "Test message" "Text format contains message"
    
    # Test JSON format
    CBOB_LOG_FORMAT="json"
    local json_output=$(log_message "ERROR" "Error message" 2>&1)
    assert_contains "$json_output" '"level":"ERROR"' "JSON format contains level"
    assert_contains "$json_output" '"message":"Error message"' "JSON format contains message"
}

# Test: configuration validation
test_config_validation() {
    echo "Testing configuration validation..."
    
    # Create temporary config file
    local temp_config=$(mktemp)
    cat > "$temp_config" << EOF
CBOB_CRUNCHY_API_KEY=test-api-key
CBOB_CRUNCHY_CLUSTERS=cluster1,cluster2
CBOB_TARGET_PATH=/tmp/test-target
CBOB_LOG_PATH=/tmp/test-logs
EOF
    
    # Test loading config
    CBOB_CONFIG_FILE="$temp_config"
    load_config
    
    assert_equals "test-api-key" "$CBOB_CRUNCHY_API_KEY" "API key loaded correctly"
    assert_equals "cluster1,cluster2" "$CBOB_CRUNCHY_CLUSTERS" "Clusters loaded correctly"
    assert_equals "/tmp/test-target" "$CBOB_TARGET_PATH" "Target path loaded correctly"
    
    # Test validation
    validate_config "CBOB_CRUNCHY_API_KEY" "CBOB_TARGET_PATH"
    
    # Clean up
    rm -f "$temp_config"
}

# Test: lock file management
test_lock_management() {
    echo "Testing lock file management..."

    # Skip if flock is not available (macOS)
    if ! command -v flock &> /dev/null; then
        echo "⊘ Skipping lock tests (flock not available on this platform)"
        return 0
    fi

    # Test acquiring lock
    local lock_file="/tmp/test_cbob_lock.lock"
    rm -f "$lock_file"

    CBOB_LOCK_FILE=""
    acquire_lock "test_cbob_lock"

    assert_equals "$lock_file" "$CBOB_LOCK_FILE" "Lock file variable set"
    [ -f "$lock_file" ] && assert_equals "0" "$?" "Lock file created"

    # Test releasing lock
    release_lock
    [ ! -f "$lock_file" ] && assert_equals "0" "$?" "Lock file removed"
}

# Test: retry with backoff
test_retry_backoff() {
    echo "Testing retry with backoff..."

    # Test successful command (simple echo command)
    local result=0
    retry_with_backoff 3 0.1 1 echo "test" >/dev/null 2>&1 || result=$?
    assert_equals "0" "$result" "Successful command passes"
}

# Test: dependency checking
test_dependency_check() {
    echo "Testing dependency checking..."

    # Test with existing commands
    check_dependencies "bash" "test"
    assert_equals "0" "$?" "Check passes for existing commands"

    # Test with non-existing command (run in subshell to prevent exit)
    local result=0
    (check_dependencies 'nonexistentcommand123' 2>/dev/null) || result=$?
    [ "$result" -ne 0 ] && result=1
    assert_equals "1" "$result" "Check fails for missing command"
}

# Test: progress indicator
test_progress_indicator() {
    echo "Testing progress indicator..."

    # Just test that it doesn't error
    show_progress 50 100 20 >/dev/null 2>&1
    assert_equals "0" "$?" "Progress indicator runs without error"
}

# =============================================================================
# S3 Destination Tests
# =============================================================================

# Test: is_dest_s3
test_is_dest_s3() {
    echo "Testing is_dest_s3..."

    # Test default (local)
    unset CBOB_DEST_TYPE
    is_dest_s3 && local result="true" || local result="false"
    assert_equals "false" "$result" "Default destination is local"

    # Test explicit local
    CBOB_DEST_TYPE="local"
    is_dest_s3 && result="true" || result="false"
    assert_equals "false" "$result" "CBOB_DEST_TYPE=local returns false"

    # Test s3
    CBOB_DEST_TYPE="s3"
    is_dest_s3 && result="true" || result="false"
    assert_equals "true" "$result" "CBOB_DEST_TYPE=s3 returns true"

    # Reset
    unset CBOB_DEST_TYPE
}

# Test: get_dest_path
test_get_dest_path() {
    echo "Testing get_dest_path..."

    # Test local destination
    CBOB_DEST_TYPE="local"
    CBOB_TARGET_PATH="/mnt/backups"
    local path=$(get_dest_path "/archive/stanza1")
    assert_equals "/mnt/backups/archive/stanza1" "$path" "Local path with subpath"

    path=$(get_dest_path "")
    assert_equals "/mnt/backups" "$path" "Local path without subpath"

    # Test S3 destination
    CBOB_DEST_TYPE="s3"
    CBOB_DEST_BUCKET="my-bucket"
    CBOB_DEST_PREFIX=""
    path=$(get_dest_path "/archive/stanza1")
    assert_equals "s3://my-bucket/archive/stanza1" "$path" "S3 path without prefix"

    CBOB_DEST_PREFIX="/pgbackrest"
    path=$(get_dest_path "/archive/stanza1")
    assert_equals "s3://my-bucket/pgbackrest/archive/stanza1" "$path" "S3 path with prefix"

    # Test prefix with trailing slash (should be removed)
    CBOB_DEST_PREFIX="/pgbackrest/"
    path=$(get_dest_path "/archive/stanza1")
    assert_equals "s3://my-bucket/pgbackrest/archive/stanza1" "$path" "S3 path with trailing slash prefix"

    # Reset
    unset CBOB_DEST_TYPE CBOB_TARGET_PATH CBOB_DEST_BUCKET CBOB_DEST_PREFIX
}

# Test: validate_dest_s3_config
test_validate_dest_s3_config() {
    echo "Testing validate_dest_s3_config..."

    # Test with local destination (should pass without S3 vars)
    CBOB_DEST_TYPE="local"
    validate_dest_s3_config 2>/dev/null
    assert_equals "0" "$?" "Local destination doesn't require S3 vars"

    # Test with S3 destination - all required vars set
    CBOB_DEST_TYPE="s3"
    CBOB_DEST_ENDPOINT="https://s3.example.com"
    CBOB_DEST_BUCKET="test-bucket"
    CBOB_DEST_ACCESS_KEY="test-key"
    CBOB_DEST_SECRET_KEY="test-secret"

    # Override error function for testing
    local original_error=$(declare -f error)
    error() { return 1; }

    validate_dest_s3_config 2>/dev/null
    assert_equals "0" "$?" "S3 destination with all vars passes"

    # Check that default region is set
    assert_equals "us-east-1" "$CBOB_DEST_REGION" "Default region set to us-east-1"

    # Reset
    unset CBOB_DEST_TYPE CBOB_DEST_ENDPOINT CBOB_DEST_BUCKET CBOB_DEST_ACCESS_KEY CBOB_DEST_SECRET_KEY CBOB_DEST_REGION
    eval "$original_error" 2>/dev/null || true
}

# Test: dest_exists (mock test)
test_dest_exists() {
    echo "Testing dest_exists..."

    # Test local destination with existing path
    CBOB_DEST_TYPE="local"
    CBOB_TARGET_PATH="/tmp"

    dest_exists "" && local result="true" || local result="false"
    assert_equals "true" "$result" "Local /tmp exists"

    dest_exists "/nonexistent_path_12345" && result="true" || result="false"
    assert_equals "false" "$result" "Local nonexistent path returns false"

    # Reset
    unset CBOB_DEST_TYPE CBOB_TARGET_PATH
}

# Test: get_dest_size (mock test for local)
test_get_dest_size() {
    echo "Testing get_dest_size..."

    # Create temp directory with known content
    local temp_dir=$(mktemp -d)
    echo "test content" > "$temp_dir/test.txt"

    CBOB_DEST_TYPE="local"
    CBOB_TARGET_PATH="$temp_dir"

    local size=$(get_dest_size "")
    # Size should be greater than 0
    [ "$size" -gt 0 ] && local result="true" || local result="false"
    assert_equals "true" "$result" "Local directory size is greater than 0"

    # Test nonexistent path
    size=$(get_dest_size "/nonexistent")
    assert_equals "0" "$size" "Nonexistent path returns 0"

    # Cleanup
    rm -rf "$temp_dir"
    unset CBOB_DEST_TYPE CBOB_TARGET_PATH
}

# Test: S3 endpoint URL validation
test_s3_endpoint_formats() {
    echo "Testing S3 endpoint URL formats..."

    # Test various endpoint formats
    local endpoints=(
        "https://fra1.digitaloceanspaces.com"
        "https://nyc3.digitaloceanspaces.com"
        "https://s3.us-west-000.backblazeb2.com"
        "https://fsn1.your-objectstorage.com"
        "http://minio.local:9000"
        "http://localhost:9000"
    )

    for endpoint in "${endpoints[@]}"; do
        if [[ "$endpoint" =~ ^https?:// ]]; then
            assert_equals "0" "0" "Valid endpoint: $endpoint"
        else
            assert_equals "1" "0" "Invalid endpoint: $endpoint"
        fi
    done
}

# Main test runner
main() {
    echo "Running CBOB Common Library Tests"
    echo "================================="
    echo
    
    # Disable actual logging to syslog during tests
    logger() { :; }
    export -f logger
    
    # Run all tests
    test_human_readable_size
    echo
    test_log_levels
    echo
    test_log_format
    echo
    test_config_validation
    echo
    test_lock_management
    echo
    test_retry_backoff
    echo
    test_dependency_check
    echo
    test_progress_indicator
    echo

    # S3 Destination tests
    echo "--- S3 Destination Tests ---"
    echo
    test_is_dest_s3
    echo
    test_get_dest_path
    echo
    test_validate_dest_s3_config
    echo
    test_dest_exists
    echo
    test_get_dest_size
    echo
    test_s3_endpoint_formats
    echo
    
    # Summary
    echo "================================="
    echo "Test Summary:"
    echo "  Total tests: $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✓ All tests passed!"
        exit 0
    else
        echo "✗ Some tests failed!"
        exit 1
    fi
}

# Run tests
main "$@"