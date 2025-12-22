#!/bin/bash

# CBOB Security Library
# Security functions for input validation, secure storage, and audit logging

# Validate input against allowed patterns
validate_input() {
    local input="$1"
    local pattern="$2"
    local description="${3:-input}"
    
    if [[ ! "$input" =~ $pattern ]]; then
        error "Invalid $description: '$input' does not match required pattern"
    fi
}

# Validate cluster ID format
validate_cluster_id() {
    local cluster_id="$1"
    
    # Cluster IDs should be alphanumeric with hyphens
    if [[ ! "$cluster_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]]; then
        error "Invalid cluster ID format: $cluster_id"
    fi
    
    # Length check (reasonable limits)
    if [ ${#cluster_id} -lt 3 ] || [ ${#cluster_id} -gt 64 ]; then
        error "Invalid cluster ID length: $cluster_id (must be 3-64 characters)"
    fi
}

# Validate API key format
validate_api_key() {
    local api_key="$1"
    
    # Basic format validation (adjust pattern based on actual format)
    if [[ ! "$api_key" =~ ^[a-zA-Z0-9_-]{20,}$ ]]; then
        error "Invalid API key format"
    fi
}

# Validate file path (prevent directory traversal)
validate_path() {
    local path="$1"
    local base_path="${2:-}"
    
    # Remove trailing slashes
    path="${path%/}"
    
    # Check for dangerous patterns
    if [[ "$path" =~ \.\. ]] || [[ "$path" =~ ^~ ]]; then
        error "Invalid path: directory traversal detected"
    fi
    
    # If base path provided, ensure path is within it
    if [ -n "$base_path" ]; then
        local realpath_base=$(realpath "$base_path" 2>/dev/null || echo "$base_path")
        local realpath_target=$(realpath "$path" 2>/dev/null || echo "$path")
        
        if [[ ! "$realpath_target" =~ ^"$realpath_base" ]]; then
            error "Path '$path' is outside allowed base path '$base_path'"
        fi
    fi
}

# Validate URL format
validate_url() {
    local url="$1"
    
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        error "Invalid URL format: $url"
    fi
}

# Sanitize input for shell execution
sanitize_shell_input() {
    local input="$1"
    
    # Remove potentially dangerous characters
    local sanitized="${input//[^a-zA-Z0-9._-]/}"
    
    echo "$sanitized"
}

# Secure credential storage using system keyring (if available)
store_credential() {
    local key="$1"
    local value="$2"
    local service="cbob"
    
    # Try to use system keyring
    if command -v secret-tool &> /dev/null; then
        # GNOME keyring
        echo "$value" | secret-tool store --label="$key" service "$service" key "$key"
    elif command -v security &> /dev/null; then
        # macOS keychain
        security add-generic-password -a "$service" -s "$key" -w "$value" -U
    else
        # Fall back to encrypted file
        store_credential_file "$key" "$value"
    fi
}

# Retrieve credential from secure storage
get_credential() {
    local key="$1"
    local service="cbob"
    
    # Try system keyring first
    if command -v secret-tool &> /dev/null; then
        secret-tool lookup service "$service" key "$key" 2>/dev/null
    elif command -v security &> /dev/null; then
        security find-generic-password -a "$service" -s "$key" -w 2>/dev/null
    else
        # Fall back to encrypted file
        get_credential_file "$key"
    fi
}

# Store credential in encrypted file (fallback)
store_credential_file() {
    local key="$1"
    local value="$2"
    local cred_dir="${HOME}/.config/cbob/credentials"
    local cred_file="$cred_dir/$key.enc"
    
    # Create directory with secure permissions
    mkdir -p "$cred_dir"
    chmod 700 "$cred_dir"
    
    # Encrypt using openssl (with key derived from hostname and username)
    local encryption_key=$(echo -n "${HOSTNAME}:${USER}:cbob" | sha256sum | cut -d' ' -f1)
    
    echo "$value" | openssl enc -aes-256-cbc -salt -pass pass:"$encryption_key" -out "$cred_file"
    chmod 600 "$cred_file"
}

# Get credential from encrypted file (fallback)
get_credential_file() {
    local key="$1"
    local cred_dir="${HOME}/.config/cbob/credentials"
    local cred_file="$cred_dir/$key.enc"
    
    if [ ! -f "$cred_file" ]; then
        return 1
    fi
    
    # Decrypt
    local encryption_key=$(echo -n "${HOSTNAME}:${USER}:cbob" | sha256sum | cut -d' ' -f1)
    openssl enc -aes-256-cbc -d -salt -pass pass:"$encryption_key" -in "$cred_file" 2>/dev/null
}

# Audit log function
audit_log() {
    local action="$1"
    local details="$2"
    local user="${USER:-unknown}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local audit_file="${CBOB_AUDIT_LOG:-${CBOB_LOG_PATH}/cbob_audit.log}"
    
    # Create audit directory if needed
    mkdir -p "$(dirname "$audit_file")"
    
    # Log entry format: timestamp|user|action|details
    echo "${timestamp}|${user}|${action}|${details}" >> "$audit_file"
    
    # Also log to syslog for centralized logging
    logger -p user.info -t "cbob-audit" "${action}: ${details}"
}

# Check file permissions
check_secure_permissions() {
    local file="$1"
    local required_perms="${2:-600}"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    local actual_perms=$(stat -c %a "$file" 2>/dev/null || stat -f %p "$file" 2>/dev/null | tail -c 4)
    
    if [ "$actual_perms" != "$required_perms" ]; then
        warning "Insecure permissions on $file (expected $required_perms, got $actual_perms)"
        return 1
    fi
    
    return 0
}

# Set secure permissions on file
set_secure_permissions() {
    local file="$1"
    local perms="${2:-600}"
    local owner="${3:-$USER}"
    
    chmod "$perms" "$file"
    chown "$owner" "$file"
}

# Validate configuration file security
validate_config_security() {
    local config_file="$1"
    
    # Check file exists
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
    fi
    
    # Check permissions (should not be world-readable)
    local perms=$(stat -c %a "$config_file" 2>/dev/null || stat -f %p "$config_file" 2>/dev/null | tail -c 4)
    if [[ "$perms" =~ [0-9][0-9][4-7] ]]; then
        warning "Configuration file is world-readable: $config_file"
        warning "Run: chmod 600 $config_file"
    fi
    
    # Check for sensitive data in plain text
    if grep -qE "(password|token|key|secret)" "$config_file"; then
        audit_log "CONFIG_CHECK" "Configuration file contains sensitive data: $config_file"
    fi
}

# Mask sensitive data in logs
mask_sensitive_data() {
    local text="$1"
    
    # Mask API keys
    text=$(echo "$text" | sed -E 's/([Aa][Pp][Ii][-_]?[Kk][Ee][Yy][=:]?)([a-zA-Z0-9_-]{8})[a-zA-Z0-9_-]+/\1\2***/g')
    
    # Mask tokens
    text=$(echo "$text" | sed -E 's/([Tt][Oo][Kk][Ee][Nn][=:]?)([a-zA-Z0-9_-]{8})[a-zA-Z0-9_-]+/\1\2***/g')
    
    # Mask AWS credentials
    text=$(echo "$text" | sed -E 's/(AWS_[A-Z_]+[=:])([a-zA-Z0-9_-]{8})[a-zA-Z0-9_-]+/\1\2***/g')
    
    echo "$text"
}

# Generate secure random string
generate_secure_random() {
    local length="${1:-32}"
    
    if command -v openssl &> /dev/null; then
        openssl rand -hex "$((length / 2))"
    elif [ -r /dev/urandom ]; then
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
    else
        # Fallback to less secure method
        date +%s%N | sha256sum | head -c "$length"
    fi
}

# Export security functions
export -f validate_input validate_cluster_id validate_api_key validate_path validate_url
export -f sanitize_shell_input store_credential get_credential
export -f audit_log check_secure_permissions set_secure_permissions
export -f validate_config_security mask_sensitive_data generate_secure_random