#!/bin/bash

# CBOB End-to-End Test
# Tests the complete flow: PostgreSQL -> pgBackRest -> S3 Source -> CBOB Sync -> S3 Dest
#
# Usage: ./tests/e2e-test.sh

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Configuration
MINIO_SOURCE_ENDPOINT="http://localhost:9000"
MINIO_SOURCE_USER="sourceuser"
MINIO_SOURCE_PASS="sourcepass123"
MINIO_SOURCE_BUCKET="pgbackrest-repo"

MINIO_DEST_ENDPOINT="http://localhost:9002"
MINIO_DEST_USER="destuser"
MINIO_DEST_PASS="destpass123"
MINIO_DEST_BUCKET="cbob-backups"

POSTGRES_HOST="localhost"
POSTGRES_PORT="5433"
POSTGRES_USER="testuser"
POSTGRES_PASS="testpass123"
POSTGRES_DB="testdb"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_step() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}STEP: $1${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."
    cd "$TEST_DIR"
    docker compose -f docker-compose.test.yml down -v 2>/dev/null || true
    rm -rf "$TEST_DIR/tmp" 2>/dev/null || true
}

# Check dependencies
check_dependencies() {
    log_step "Checking dependencies"

    local deps=(docker aws psql)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Please install them before running this test"
        exit 1
    fi

    # Check Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running"
        exit 1
    fi

    log_success "All dependencies available"
}

# Start test environment
start_environment() {
    log_step "Starting test environment"

    cd "$TEST_DIR"

    # Clean up any previous runs
    docker compose -f docker-compose.test.yml down -v 2>/dev/null || true

    # Start services
    log_info "Starting MinIO source..."
    docker compose -f docker-compose.test.yml up -d minio-source

    log_info "Starting MinIO destination..."
    docker compose -f docker-compose.test.yml up -d minio-dest

    log_info "Starting PostgreSQL..."
    docker compose -f docker-compose.test.yml up -d postgres-source

    # Wait for services to be healthy
    log_info "Waiting for services to be ready..."
    sleep 5

    # Check MinIO source
    local retries=30
    while ! curl -sf "$MINIO_SOURCE_ENDPOINT/minio/health/live" &>/dev/null; do
        retries=$((retries - 1))
        if [ $retries -eq 0 ]; then
            log_error "MinIO source failed to start"
            exit 1
        fi
        sleep 1
    done
    log_success "MinIO source is ready"

    # Check MinIO dest
    retries=30
    while ! curl -sf "$MINIO_DEST_ENDPOINT/minio/health/live" &>/dev/null; do
        retries=$((retries - 1))
        if [ $retries -eq 0 ]; then
            log_error "MinIO destination failed to start"
            exit 1
        fi
        sleep 1
    done
    log_success "MinIO destination is ready"

    # Check PostgreSQL (longer timeout for first run with image pull)
    log_info "Waiting for PostgreSQL to be ready (this may take a while on first run)..."
    retries=90
    while ! PGPASSWORD="$POSTGRES_PASS" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1" &>/dev/null; do
        retries=$((retries - 1))
        if [ $retries -eq 0 ]; then
            log_error "PostgreSQL failed to start"
            # Show docker logs for debugging
            docker logs cbob-test-postgres-source 2>&1 | tail -30
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    log_success "PostgreSQL is ready"
}

# Create MinIO buckets
setup_minio_buckets() {
    log_step "Setting up MinIO buckets"

    # Configure AWS CLI for source MinIO
    export AWS_ACCESS_KEY_ID="$MINIO_SOURCE_USER"
    export AWS_SECRET_ACCESS_KEY="$MINIO_SOURCE_PASS"

    # Create source bucket
    aws --endpoint-url "$MINIO_SOURCE_ENDPOINT" s3 mb "s3://$MINIO_SOURCE_BUCKET" 2>/dev/null || true
    log_success "Source bucket created: $MINIO_SOURCE_BUCKET"

    # Configure AWS CLI for dest MinIO
    export AWS_ACCESS_KEY_ID="$MINIO_DEST_USER"
    export AWS_SECRET_ACCESS_KEY="$MINIO_DEST_PASS"

    # Create destination bucket
    aws --endpoint-url "$MINIO_DEST_ENDPOINT" s3 mb "s3://$MINIO_DEST_BUCKET" 2>/dev/null || true
    log_success "Destination bucket created: $MINIO_DEST_BUCKET"
}

# Create test data in PostgreSQL
create_test_data() {
    log_step "Creating test data in PostgreSQL"

    PGPASSWORD="$POSTGRES_PASS" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" << 'EOF'
-- Create test table
DROP TABLE IF EXISTS test_data;
CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    value NUMERIC(10,2),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Insert test data
INSERT INTO test_data (name, value) VALUES
    ('Test Item 1', 100.50),
    ('Test Item 2', 200.75),
    ('Test Item 3', 300.25),
    ('Test Item 4', 400.00),
    ('Test Item 5', 500.99);

-- Verify data
SELECT COUNT(*) as row_count FROM test_data;
EOF

    log_success "Test data created (5 rows)"
}

# Create pgBackRest backup (simulated)
create_pgbackrest_backup() {
    log_step "Creating simulated pgBackRest backup structure"

    # Create a simulated pgBackRest repository structure in MinIO source
    # In a real scenario, pgBackRest would do this, but for testing we simulate it

    local temp_dir=$(mktemp -d)
    local stanza="test-stanza"

    # Create pgBackRest directory structure
    mkdir -p "$temp_dir/archive/$stanza/18-1/0000000100000000"
    mkdir -p "$temp_dir/backup/$stanza/20241221-120000F"

    # Create simulated WAL file
    dd if=/dev/urandom of="$temp_dir/archive/$stanza/18-1/0000000100000000/000000010000000000000001.gz" bs=1024 count=16 2>/dev/null

    # Create simulated backup files
    dd if=/dev/urandom of="$temp_dir/backup/$stanza/20241221-120000F/backup.manifest.gz" bs=1024 count=8 2>/dev/null
    dd if=/dev/urandom of="$temp_dir/backup/$stanza/20241221-120000F/pg_data.tar.gz" bs=1024 count=64 2>/dev/null

    # Create backup.info
    cat > "$temp_dir/backup/$stanza/backup.info" << EOF
[backup:current]
20241221-120000F={"backrest-format":5,"backrest-version":"2.48","backup-archive-start":"000000010000000000000001","backup-archive-stop":"000000010000000000000001","backup-info-repo-size":65536,"backup-info-repo-size-delta":65536,"backup-info-size":262144,"backup-info-size-delta":262144,"backup-timestamp-start":1734782400,"backup-timestamp-stop":1734782460,"backup-type":"full","db-id":1,"option-archive-check":true,"option-archive-copy":false,"option-backup-standby":false,"option-checksum-page":true,"option-compress":true,"option-hardlink":false,"option-online":true}

[db]
db-catalog-version=202411121
db-control-version=1300
db-id=1
db-system-id=7123456789012345678
db-version="18"

[db:history]
1={"db-catalog-version":202411121,"db-control-version":1300,"db-system-id":7123456789012345678,"db-version":"18"}
EOF

    # Copy backup.info to backup.info.copy
    cp "$temp_dir/backup/$stanza/backup.info" "$temp_dir/backup/$stanza/backup.info.copy"

    # Create backup.history
    mkdir -p "$temp_dir/backup/$stanza/backup.history/2024"
    echo "20241221-120000F" > "$temp_dir/backup/$stanza/backup.history/2024/20241221-120000F.manifest"

    # Upload to MinIO source
    export AWS_ACCESS_KEY_ID="$MINIO_SOURCE_USER"
    export AWS_SECRET_ACCESS_KEY="$MINIO_SOURCE_PASS"

    log_info "Uploading simulated backup to MinIO source..."
    aws --endpoint-url "$MINIO_SOURCE_ENDPOINT" s3 sync "$temp_dir" "s3://$MINIO_SOURCE_BUCKET/repo" --quiet

    # Verify upload
    local file_count=$(aws --endpoint-url "$MINIO_SOURCE_ENDPOINT" s3 ls "s3://$MINIO_SOURCE_BUCKET/repo/" --recursive | wc -l)
    log_success "Uploaded $file_count files to source bucket"

    # Show structure
    log_info "Source bucket structure:"
    aws --endpoint-url "$MINIO_SOURCE_ENDPOINT" s3 ls "s3://$MINIO_SOURCE_BUCKET/repo/" --recursive

    # Cleanup
    rm -rf "$temp_dir"
}

# Test CBOB S3 functions directly
test_cbob_s3_functions() {
    log_step "Testing CBOB S3 functions"

    # Source the library
    source "$PROJECT_ROOT/lib/cbob_common.sh"

    # Configure for source
    export CBOB_DEST_TYPE="s3"
    export CBOB_DEST_ENDPOINT="$MINIO_DEST_ENDPOINT"
    export CBOB_DEST_BUCKET="$MINIO_DEST_BUCKET"
    export CBOB_DEST_ACCESS_KEY="$MINIO_DEST_USER"
    export CBOB_DEST_SECRET_KEY="$MINIO_DEST_PASS"
    export CBOB_DEST_REGION="us-east-1"
    export CBOB_DEST_PREFIX=""

    # Test is_dest_s3
    if is_dest_s3; then
        log_success "is_dest_s3() correctly returns true"
    else
        log_error "is_dest_s3() should return true"
        return 1
    fi

    # Test get_dest_path
    local path=$(get_dest_path "/archive/test-stanza")
    if [ "$path" = "s3://$MINIO_DEST_BUCKET/archive/test-stanza" ]; then
        log_success "get_dest_path() returns correct path: $path"
    else
        log_error "get_dest_path() returned wrong path: $path"
        return 1
    fi

    # Test validate_dest_s3_config
    validate_dest_s3_config 2>/dev/null
    log_success "validate_dest_s3_config() passed"
}

# Test sync from source to destination
test_sync_to_dest() {
    log_step "Testing sync from source S3 to destination S3"

    # Source the library
    source "$PROJECT_ROOT/lib/cbob_common.sh"

    # Configure source credentials and endpoint
    export AWS_ACCESS_KEY_ID="$MINIO_SOURCE_USER"
    export AWS_SECRET_ACCESS_KEY="$MINIO_SOURCE_PASS"
    export AWS_DEFAULT_REGION="us-east-1"
    export CBOB_SOURCE_ENDPOINT="$MINIO_SOURCE_ENDPOINT"

    # Configure destination
    export CBOB_DEST_TYPE="s3"
    export CBOB_DEST_ENDPOINT="$MINIO_DEST_ENDPOINT"
    export CBOB_DEST_BUCKET="$MINIO_DEST_BUCKET"
    export CBOB_DEST_ACCESS_KEY="$MINIO_DEST_USER"
    export CBOB_DEST_SECRET_KEY="$MINIO_DEST_PASS"
    export CBOB_DEST_REGION="us-east-1"
    export CBOB_DEST_PREFIX=""

    local stanza="test-stanza"

    # Sync archive
    log_info "Syncing archive..."
    sync_to_dest "s3://$MINIO_SOURCE_BUCKET/repo/archive/$stanza" "/archive/$stanza"
    log_success "Archive synced"

    # Sync backup
    log_info "Syncing backup..."
    sync_to_dest "s3://$MINIO_SOURCE_BUCKET/repo/backup/$stanza/20241221-120000F" "/backup/$stanza/20241221-120000F"
    log_success "Backup synced"

    # Sync metadata
    log_info "Syncing metadata..."
    sync_to_dest "s3://$MINIO_SOURCE_BUCKET/repo/backup/$stanza/backup.history" "/backup/$stanza/backup.history"
    copy_to_dest "s3://$MINIO_SOURCE_BUCKET/repo/backup/$stanza/backup.info" "/backup/$stanza/backup.info"
    copy_to_dest "s3://$MINIO_SOURCE_BUCKET/repo/backup/$stanza/backup.info.copy" "/backup/$stanza/backup.info.copy"
    log_success "Metadata synced"

    # Verify destination
    log_info "Verifying destination bucket..."
    export AWS_ACCESS_KEY_ID="$MINIO_DEST_USER"
    export AWS_SECRET_ACCESS_KEY="$MINIO_DEST_PASS"

    local dest_files=$(aws --endpoint-url "$MINIO_DEST_ENDPOINT" s3 ls "s3://$MINIO_DEST_BUCKET/" --recursive | wc -l)
    log_info "Destination bucket contains $dest_files files"

    # Show destination structure
    log_info "Destination bucket structure:"
    aws --endpoint-url "$MINIO_DEST_ENDPOINT" s3 ls "s3://$MINIO_DEST_BUCKET/" --recursive

    if [ "$dest_files" -gt 0 ]; then
        log_success "Sync to destination completed successfully!"
    else
        log_error "No files found in destination bucket"
        return 1
    fi
}

# Test dest_exists and get_dest_size
test_dest_operations() {
    log_step "Testing destination operations"

    source "$PROJECT_ROOT/lib/cbob_common.sh"

    # Configure destination
    export CBOB_DEST_TYPE="s3"
    export CBOB_DEST_ENDPOINT="$MINIO_DEST_ENDPOINT"
    export CBOB_DEST_BUCKET="$MINIO_DEST_BUCKET"
    export CBOB_DEST_ACCESS_KEY="$MINIO_DEST_USER"
    export CBOB_DEST_SECRET_KEY="$MINIO_DEST_PASS"
    export CBOB_DEST_REGION="us-east-1"
    export CBOB_DEST_PREFIX=""

    # Test dest_exists
    if dest_exists "/backup/test-stanza/backup.info"; then
        log_success "dest_exists() correctly found backup.info"
    else
        log_error "dest_exists() should find backup.info"
        return 1
    fi

    if ! dest_exists "/nonexistent/path"; then
        log_success "dest_exists() correctly returns false for nonexistent path"
    else
        log_error "dest_exists() should return false for nonexistent path"
        return 1
    fi
}

# Test download from destination
test_download_from_dest() {
    log_step "Testing download from destination"

    source "$PROJECT_ROOT/lib/cbob_common.sh"

    # Configure destination
    export CBOB_DEST_TYPE="s3"
    export CBOB_DEST_ENDPOINT="$MINIO_DEST_ENDPOINT"
    export CBOB_DEST_BUCKET="$MINIO_DEST_BUCKET"
    export CBOB_DEST_ACCESS_KEY="$MINIO_DEST_USER"
    export CBOB_DEST_SECRET_KEY="$MINIO_DEST_PASS"
    export CBOB_DEST_REGION="us-east-1"
    export CBOB_DEST_PREFIX=""

    local temp_dir=$(mktemp -d)

    log_info "Downloading backup from destination to local..."
    download_from_dest "/backup/test-stanza" "$temp_dir/backup"

    # Verify download
    if [ -f "$temp_dir/backup/backup.info" ]; then
        log_success "backup.info downloaded successfully"
    else
        log_error "backup.info not found in downloaded files"
        ls -la "$temp_dir/backup/" 2>/dev/null || true
        rm -rf "$temp_dir"
        return 1
    fi

    local file_count=$(find "$temp_dir" -type f | wc -l)
    log_success "Downloaded $file_count files to local"

    # Show downloaded structure
    log_info "Downloaded structure:"
    find "$temp_dir" -type f

    # Cleanup
    rm -rf "$temp_dir"
}

# Main test flow
main() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           CBOB End-to-End Integration Test                 ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Trap for cleanup
    trap cleanup EXIT

    local start_time=$(date +%s)
    local tests_passed=0
    local tests_failed=0

    # Run tests (use pre-increment to avoid bash arithmetic quirk where ((0++)) returns false)
    check_dependencies && ((++tests_passed)) || ((++tests_failed))
    start_environment && ((++tests_passed)) || ((++tests_failed))
    setup_minio_buckets && ((++tests_passed)) || ((++tests_failed))
    create_test_data && ((++tests_passed)) || ((++tests_failed))
    create_pgbackrest_backup && ((++tests_passed)) || ((++tests_failed))
    test_cbob_s3_functions && ((++tests_passed)) || ((++tests_failed))
    test_sync_to_dest && ((++tests_passed)) || ((++tests_failed))
    test_dest_operations && ((++tests_passed)) || ((++tests_failed))
    test_download_from_dest && ((++tests_passed)) || ((++tests_failed))

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Test Summary                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Duration: ${duration}s"
    echo -e "Tests passed: ${GREEN}$tests_passed${NC}"
    echo -e "Tests failed: ${RED}$tests_failed${NC}"
    echo ""

    if [ $tests_failed -eq 0 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              ✓ ALL TESTS PASSED!                           ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║              ✗ SOME TESTS FAILED!                          ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

# Run
main "$@"
