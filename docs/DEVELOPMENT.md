# CBOB Development Guide

Guide for contributing to CBOB development.

## Table of Contents
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Building](#building)
- [Contributing](#contributing)
- [Release Process](#release-process)

## Development Setup

### Prerequisites

- Bash 4.4+
- Git
- Docker & Docker Compose
- jq (for JSON processing)
- shellcheck (for linting)

### Clone Repository

```bash
git clone https://github.com/CrunchyData/cbob.git
cd cbob
```

### Development Environment

```bash
# Install development dependencies
sudo apt-get update
sudo apt-get install -y \
    bash-completion \
    shellcheck \
    jq \
    bats

# Install pre-commit hooks (optional)
pre-commit install
```

### IDE Setup

#### VS Code

Recommended extensions:
- Bash IDE
- ShellCheck
- Python
- Docker
- YAML

Settings (`.vscode/settings.json`):
```json
{
    "files.associations": {
        "cbob*": "shellscript"
    },
    "shellcheck.enable": true,
    "shellcheck.run": "onSave",
    "editor.formatOnSave": true
}
```

## Project Structure

```
cbob/
├── bin/                    # CLI commands
│   ├── cbob               # Main entry point
│   ├── cbob-sync          # Sync subcommand
│   ├── cbob-restore-check # Restore check subcommand
│   ├── cbob-replicate     # Replication subcommand
│   └── ...                # Other subcommands
├── lib/                    # Shared libraries
│   ├── cbob_common.sh     # Common functions
│   ├── cbob_security.sh   # Security functions
│   ├── cbob_metrics.sh    # Metrics collection
│   └── cbob_replication.sh # Replication engine
├── tests/                  # Test suites
│   ├── test_common.sh     # Unit tests
│   ├── test_integration.sh # Integration tests
│   └── e2e-test.sh        # End-to-end tests
├── docs/                   # Documentation
├── Dockerfile             # Docker image build
├── docker-compose.yml     # Docker Compose setup
└── .env.example           # Configuration template
```

## Coding Standards

### Shell Script Standards

#### Style Guide

Follow Google Shell Style Guide with these additions:

```bash
#!/usr/bin/env bash
# Script description here

# shellcheck disable=SC2034  # Explain why disabled
set -euo pipefail

# Constants (UPPER_CASE)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Global variables (UPPER_CASE with CBOB_ prefix)
CBOB_DEBUG="${CBOB_DEBUG:-false}"

# Functions (lower_case)
function validate_input() {
    local input="$1"
    # Function implementation
}

# Main function
function main() {
    # Main logic here
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

#### Best Practices

1. **Always quote variables**
   ```bash
   # Good
   echo "${variable}"
   
   # Bad
   echo $variable
   ```

2. **Use `[[ ]]` for conditionals**
   ```bash
   # Good
   if [[ -n "${variable}" ]]; then
   
   # Bad
   if [ -n "$variable" ]; then
   ```

3. **Handle errors gracefully**
   ```bash
   if ! command; then
       log_error "Command failed"
       return 1
   fi
   ```

4. **Use local variables in functions**
   ```bash
   function process_data() {
       local data="$1"
       local -r max_size=1000
   }
   ```

### Documentation Standards

1. **Every script needs a header**
2. **Functions need descriptions**
3. **Complex logic needs comments**
4. **README for each directory**

## Testing

### Unit Tests

Using BATS (Bash Automated Testing System):

```bash
# tests/unit/test_common.bats
#!/usr/bin/env bats

setup() {
    source "${BATS_TEST_DIRNAME}/../../lib/cbob_common.sh"
}

@test "log_message creates proper format" {
    run log_message "INFO" "Test message"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "Test message" ]]
}

@test "validate_cluster_id accepts valid ID" {
    run validate_cluster_id "abc-123-def"
    [[ "$status" -eq 0 ]]
}
```

Run tests:
```bash
# All unit tests
bats tests/unit/

# Specific test file
bats tests/unit/test_common.bats
```

### Integration Tests

```bash
# tests/integration/test_sync.sh
#!/usr/bin/env bash

# Test full sync operation
function test_sync_operation() {
    # Setup test environment
    export CBOB_DRY_RUN=true
    export CBOB_TEST_MODE=true
    
    # Run sync
    if cbob sync --cluster test-cluster; then
        echo "PASS: Sync completed"
    else
        echo "FAIL: Sync failed"
        return 1
    fi
}
```

### Linting

```bash
# Shell scripts
shellcheck bin/* lib/*.sh

# Documentation
markdownlint docs/*.md
```

## Building

### Local Build

```bash
# Run build script
./scripts/build.sh

# Creates:
# - dist/cbob-v2.0.0.tar.gz
# - dist/cbob-v2.0.0.deb
# - dist/cbob-v2.0.0.rpm
```

### Docker Build

```bash
# Build image
docker build -t cbob:latest .

# Build with docker-compose
docker-compose build

# Run tests in container
docker-compose -f tests/docker-compose.test.yml up --build
```

### Version Management

Version in `lib/cbob_common.sh`:
```bash
readonly CBOB_VERSION="2.0.0"
```

Update version:
```bash
./scripts/bump-version.sh 2.1.0
```

## Contributing

### Development Workflow

1. **Fork repository**
2. **Create feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **Make changes**
   - Write code
   - Add tests
   - Update documentation

4. **Test locally**
   ```bash
   # Run tests
   make test
   
   # Run linting
   make lint
   ```

5. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   ```

6. **Push and create PR**
   ```bash
   git push origin feature/amazing-feature
   ```

### Commit Message Format

Follow Conventional Commits:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Formatting
- `refactor`: Code restructure
- `test`: Testing
- `chore`: Maintenance

Examples:
```
feat(sync): add parallel sync support
fix(restore): handle missing stanza error
docs(api): update endpoint documentation
```

### Pull Request Process

1. **Update documentation**
2. **Add tests for new features**
3. **Ensure all tests pass**
4. **Update CHANGELOG.md**
5. **Request review**

### Code Review Checklist

- [ ] Code follows style guide
- [ ] Tests cover new functionality
- [ ] Documentation updated
- [ ] No hardcoded values
- [ ] Error handling implemented
- [ ] Security considerations addressed
- [ ] Performance impact assessed

## Release Process

### Release Checklist

1. **Update version**
   ```bash
   ./scripts/bump-version.sh 2.1.0
   ```

2. **Update CHANGELOG.md**
   ```markdown
   ## [2.1.0] - 2024-01-20
   ### Added
   - New feature X
   ### Fixed
   - Bug Y
   ```

3. **Run full test suite**
   ```bash
   make test-all
   ```

4. **Build release artifacts**
   ```bash
   make release
   ```

5. **Create Git tag**
   ```bash
   git tag -a v2.1.0 -m "Release version 2.1.0"
   git push origin v2.1.0
   ```

6. **Create GitHub release**
   - Upload artifacts
   - Copy changelog section
   - Publish release

### Hotfix Process

```bash
# Create hotfix branch from tag
git checkout -b hotfix/2.1.1 v2.1.0

# Make fix
# Update version to 2.1.1
# Test thoroughly

# Merge to main
git checkout main
git merge hotfix/2.1.1

# Tag and release
git tag -a v2.1.1 -m "Hotfix version 2.1.1"
```

## Development Tips

### Debugging

```bash
# Enable debug mode
export CBOB_DEBUG=true
export CBOB_LOG_LEVEL=debug

# Bash debugging
set -x  # Enable trace
set +x  # Disable trace

# Add debug function
debug() {
    [[ "${CBOB_DEBUG}" == "true" ]] && echo "DEBUG: $*" >&2
}
```

### Performance Testing

```bash
# Time operations
time cbob sync --cluster test

# Profile with strace
strace -c cbob sync

# Memory usage
/usr/bin/time -v cbob sync
```

### Local Testing Environment

```bash
# Create test configuration
cat > test.conf <<EOF
CBOB_CRUNCHY_API_KEY=test-key
CBOB_CRUNCHY_CLUSTERS=test-cluster
CBOB_TARGET_PATH=/tmp/cbob-test
CBOB_DRY_RUN=true
EOF

# Run with test config
CBOB_CONFIG_FILE=test.conf cbob sync
```

### Makefile Targets

```makefile
# Common targets
make help          # Show available targets
make test          # Run tests
make lint          # Run linters
make build         # Build project
make clean         # Clean build artifacts
make install       # Install locally
make docker        # Build Docker images
```

## Resources

- [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)