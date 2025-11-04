#!/usr/bin/env bash
#
# CachePilot - Security Functions Library
#
# Security-focused functions for path validation, input sanitization,
# permission checks, and secure operations.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

validate_path() {
    local path="$1"
    local base_dir="${2:-/opt/cachepilot}"
    
    if [[ -z "$path" ]]; then
        echo "Error: Path cannot be empty" >&2
        return 1
    fi
    
    if [[ "$path" =~ \.\. ]]; then
        echo "Error: Path contains directory traversal pattern" >&2
        return 1
    fi
    
    if [[ ! "$path" =~ ^/ ]]; then
        path="$base_dir/$path"
    fi
    
    local real_path
    real_path=$(realpath -m "$path" 2>/dev/null) || {
        echo "Error: Invalid path: $path" >&2
        return 1
    }
    
    local real_base
    real_base=$(realpath "$base_dir" 2>/dev/null) || {
        echo "Error: Invalid base directory: $base_dir" >&2
        return 1
    }
    
    if [[ ! "$real_path" =~ ^"$real_base" ]]; then
        echo "Error: Path outside base directory" >&2
        return 1
    fi
    
    echo "$real_path"
    return 0
}

sanitize_input() {
    local input="$1"
    local allow_spaces="${2:-false}"
    
    if [[ -z "$input" ]]; then
        echo "Error: Input cannot be empty" >&2
        return 1
    fi
    
    local dangerous_chars=';|&$`<>(){}[]'
    local char
    for ((i=0; i<${#dangerous_chars}; i++)); do
        char="${dangerous_chars:$i:1}"
        if [[ "$input" == *"$char"* ]]; then
            echo "Error: Input contains dangerous character: $char" >&2
            return 1
        fi
    done
    
    if [[ "$input" =~ \$\{ ]]; then
        echo "Error: Input contains variable expansion pattern" >&2
        return 1
    fi
    
    if [[ "$allow_spaces" != "true" ]] && [[ "$input" =~ [[:space:]] ]]; then
        echo "Error: Input contains whitespace (not allowed)" >&2
        return 1
    fi
    
    echo "$input"
    return 0
}

check_permissions() {
    local file="$1"
    local expected_perms="${2:-600}"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    local actual_perms
    actual_perms=$(stat -c '%a' "$file" 2>/dev/null) || {
        echo "Error: Cannot read file permissions: $file" >&2
        return 1
    }
    
    if [[ "$actual_perms" != "$expected_perms" ]]; then
        echo "Warning: File permissions mismatch: $file" >&2
        echo "  Expected: $expected_perms" >&2
        echo "  Actual: $actual_perms" >&2
        return 1
    fi
    
    return 0
}

verify_file_ownership() {
    local file="$1"
    local expected_user="${2:-root}"
    local expected_group="${3:-root}"
    
    if [[ ! -e "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    local actual_user
    actual_user=$(stat -c '%U' "$file" 2>/dev/null) || {
        echo "Error: Cannot read file owner: $file" >&2
        return 1
    }
    
    local actual_group
    actual_group=$(stat -c '%G' "$file" 2>/dev/null) || {
        echo "Error: Cannot read file group: $file" >&2
        return 1
    }
    
    if [[ "$actual_user" != "$expected_user" ]] || [[ "$actual_group" != "$expected_group" ]]; then
        echo "Warning: File ownership mismatch: $file" >&2
        echo "  Expected: $expected_user:$expected_group" >&2
        echo "  Actual: $actual_user:$actual_group" >&2
        return 1
    fi
    
    return 0
}

audit_configuration() {
    local config_dir="${1:-/etc/cachepilot}"
    local data_dir="${2:-/var/cachepilot}"
    local errors=0
    
    echo "Running security audit..."
    echo
    
    echo "Checking sensitive file permissions..."
    
    local sensitive_files=(
        "$config_dir/.env"
        "/opt/cachepilot/api-keys.json"
        "$data_dir/ca/ca-key.pem"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            if ! check_permissions "$file" "600"; then
                ((errors++))
            fi
        fi
    done
    
    echo
    echo "Checking directory permissions..."
    
    local secure_dirs=(
        "$data_dir/ca"
        "$data_dir/tenants"
        "$config_dir"
    )
    
    for dir in "${secure_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local perms
            perms=$(stat -c '%a' "$dir" 2>/dev/null)
            if [[ "$perms" != "700" ]] && [[ "$perms" != "755" ]]; then
                echo "Warning: Directory $dir has permissions $perms" >&2
                ((errors++))
            fi
        fi
    done
    
    echo
    if [[ $errors -eq 0 ]]; then
        echo "Security audit passed: No issues found"
        return 0
    else
        echo "Security audit completed with $errors warning(s)" >&2
        return 1
    fi
}

validate_tenant_name_strict() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        echo "Error: Tenant name cannot be empty" >&2
        return 1
    fi
    
    if [[ ${#name} -lt 3 ]] || [[ ${#name} -gt 63 ]]; then
        echo "Error: Tenant name must be 3-63 characters long" >&2
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        echo "Error: Tenant name must start with a letter, contain only lowercase letters, numbers, and hyphens, and not end with a hyphen" >&2
        return 1
    fi
    
    if [[ "$name" =~ -- ]]; then
        echo "Error: Tenant name cannot contain consecutive hyphens" >&2
        return 1
    fi
    
    local reserved_names=("test" "prod" "dev" "staging" "localhost" "redis" "admin" "root" "system")
    for reserved in "${reserved_names[@]}"; do
        if [[ "$name" == "$reserved" ]]; then
            echo "Error: Tenant name '$name' is reserved" >&2
            return 1
        fi
    done
    
    echo "$name"
    return 0
}

validate_port_number() {
    local port="$1"
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        echo "Error: Port must be a number" >&2
        return 1
    fi
    
    if [[ $port -lt 1024 ]]; then
        echo "Error: Port must be 1024 or higher (privileged ports not allowed)" >&2
        return 1
    fi
    
    if [[ $port -gt 65535 ]]; then
        echo "Error: Port must be 65535 or lower" >&2
        return 1
    fi
    
    local reserved_ports=(6379 8000 8001 8080 8443 9090)
    for reserved in "${reserved_ports[@]}"; do
        if [[ $port -eq $reserved ]]; then
            echo "Error: Port $port is reserved for system use" >&2
            return 1
        fi
    done
    
    echo "$port"
    return 0
}

validate_memory_limit() {
    local memory="$1"
    
    if [[ ! "$memory" =~ ^[0-9]+$ ]]; then
        echo "Error: Memory limit must be a number" >&2
        return 1
    fi
    
    if [[ $memory -lt 64 ]]; then
        echo "Error: Memory limit must be at least 64 MB" >&2
        return 1
    fi
    
    if [[ $memory -gt 65536 ]]; then
        echo "Error: Memory limit cannot exceed 64 GB" >&2
        return 1
    fi
    
    echo "$memory"
    return 0
}

validate_domain_name() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        echo "Error: Domain cannot be empty" >&2
        return 1
    fi
    
    if [[ ${#domain} -gt 253 ]]; then
        echo "Error: Domain name too long (max 253 characters)" >&2
        return 1
    fi
    
    if [[ ! "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
        echo "Error: Invalid domain name format" >&2
        return 1
    fi
    
    echo "$domain"
    return 0
}

validate_email_address() {
    local email="$1"
    
    if [[ -z "$email" ]]; then
        echo "Error: Email cannot be empty" >&2
        return 1
    fi
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Error: Invalid email address format" >&2
        return 1
    fi
    
    if [[ ${#email} -gt 254 ]]; then
        echo "Error: Email address too long" >&2
        return 1
    fi
    
    echo "$email"
    return 0
}

check_command_whitelist() {
    local command="$1"
    
    local allowed_commands=(
        "docker"
        "redis-cli"
        "openssl"
        "tar"
        "gzip"
        "nginx"
        "systemctl"
        "curl"
        "wget"
        "mkdir"
        "cp"
        "mv"
        "rm"
        "chmod"
        "chown"
        "cat"
        "grep"
        "awk"
        "sed"
    )
    
    local cmd_base
    cmd_base=$(basename "$command")
    
    for allowed in "${allowed_commands[@]}"; do
        if [[ "$cmd_base" == "$allowed" ]]; then
            return 0
        fi
    done
    
    echo "Error: Command '$cmd_base' is not in whitelist" >&2
    return 1
}

generate_secure_password() {
    local length="${1:-32}"
    
    if [[ $length -lt 16 ]]; then
        echo "Error: Password length must be at least 16 characters" >&2
        return 1
    fi
    
    if ! command -v openssl &> /dev/null; then
        echo "Error: openssl not found" >&2
        return 1
    fi
    
    openssl rand -base64 "$length" | tr -d '/+=' | head -c "$length"
    return 0
}

verify_certificate_validity() {
    local cert_file="$1"
    local warn_days="${2:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        echo "Error: Certificate file not found: $cert_file" >&2
        return 1
    fi
    
    if ! command -v openssl &> /dev/null; then
        echo "Error: openssl not found" >&2
        return 1
    fi
    
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        echo "Error: Cannot read certificate expiry date" >&2
        return 1
    fi
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null) || {
        echo "Error: Cannot parse certificate expiry date" >&2
        return 1
    }
    
    local current_epoch
    current_epoch=$(date +%s)
    
    local days_until_expiry
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_expiry -lt 0 ]]; then
        echo "Error: Certificate has expired" >&2
        return 1
    fi
    
    if [[ $days_until_expiry -lt $warn_days ]]; then
        echo "Warning: Certificate expires in $days_until_expiry days" >&2
        return 2
    fi
    
    return 0
}

secure_file_deletion() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi
    
    if command -v shred &> /dev/null; then
        shred -vfz -n 3 "$file" 2>/dev/null
    else
        dd if=/dev/urandom of="$file" bs=1M count=1 conv=notrunc 2>/dev/null
        rm -f "$file"
    fi
    
    return 0
}

log_security_event() {
    local event_type="$1"
    local details="$2"
    local log_file="${3:-/opt/cachepilot/data/logs/security.log}"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local log_entry="[$timestamp] [SECURITY] [$event_type] $details"
    
    mkdir -p "$(dirname "$log_file")"
    echo "$log_entry" >> "$log_file"
    
    if [[ "$event_type" == "CRITICAL" ]] || [[ "$event_type" == "ERROR" ]]; then
        echo "$log_entry" >&2
    fi
    
    return 0
}
