#!/usr/bin/env bash
#
# CachePilot - Input Validation Library
#
# Comprehensive validation functions for tenant names, memory limits, ports,
# passwords, file paths, and configuration structures.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

if [[ -f "${BASE_DIR}/lib/logger.sh" ]]; then
    source "${BASE_DIR}/lib/logger.sh"
fi

VALIDATION_ERRORS=()

validation_clear_errors() {
    VALIDATION_ERRORS=()
}

validation_add_error() {
    local error="$1"
    VALIDATION_ERRORS+=("$error")
}

validation_has_errors() {
    [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]
}

validation_get_errors_json() {
    if [[ ${#VALIDATION_ERRORS[@]} -eq 0 ]]; then
        echo "[]"
        return
    fi
    
    local json="["
    local first=true
    for error in "${VALIDATION_ERRORS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json="${json},"
        fi
        local escaped="${error//\"/\\\"}"
        json="${json}\"${escaped}\""
    done
    json="${json}]"
    echo "$json"
}

validation_print_errors() {
    if [[ ${#VALIDATION_ERRORS[@]} -eq 0 ]]; then
        return
    fi
    
    echo "Validation errors:" >&2
    for error in "${VALIDATION_ERRORS[@]}"; do
        echo "  - $error" >&2
    done
}

validate_tenant_name_strict() {
    local tenant="$1"
    local errors=()
    
    if [[ -z "$tenant" ]]; then
        errors+=("Tenant name cannot be empty")
    fi
    
    if [[ ${#tenant} -gt 63 ]]; then
        errors+=("Tenant name must be 63 characters or less (current: ${#tenant})")
    fi
    
    if [[ ! "$tenant" =~ ^[a-z0-9] ]]; then
        errors+=("Tenant name must start with a lowercase letter or number")
    fi
    
    if [[ ! "$tenant" =~ ^[a-z0-9-]+$ ]]; then
        errors+=("Tenant name can only contain lowercase letters, numbers, and hyphens")
    fi
    
    if [[ "$tenant" =~ -$ ]]; then
        errors+=("Tenant name cannot end with a hyphen")
    fi
    
    if [[ "$tenant" =~ -- ]]; then
        errors+=("Tenant name cannot contain consecutive hyphens")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        for error in "${errors[@]}"; do
            validation_add_error "$error"
        done
        return 1
    fi
    
    return 0
}

validate_memory_limit() {
    local value="$1"
    local min="${2:-64}"
    local max="${3:-4096}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        validation_add_error "Memory limit must be a number (got: $value)"
        return 1
    fi
    
    if [[ $value -lt $min ]]; then
        validation_add_error "Memory limit must be at least ${min}MB (got: ${value}MB)"
        return 1
    fi
    
    if [[ $value -gt $max ]]; then
        validation_add_error "Memory limit must not exceed ${max}MB (got: ${value}MB)"
        return 1
    fi
    
    return 0
}

validate_docker_limit() {
    local docker_limit="$1"
    local redis_maxmemory="$2"
    
    if ! [[ "$docker_limit" =~ ^[0-9]+$ ]]; then
        validation_add_error "Docker limit must be a number (got: $docker_limit)"
        return 1
    fi
    
    if [[ $docker_limit -lt 128 ]]; then
        validation_add_error "Docker limit must be at least 128MB (got: ${docker_limit}MB)"
        return 1
    fi
    
    if [[ $docker_limit -gt 8192 ]]; then
        validation_add_error "Docker limit must not exceed 8192MB (got: ${docker_limit}MB)"
        return 1
    fi
    
    if [[ $docker_limit -lt $redis_maxmemory ]]; then
        validation_add_error "Docker limit (${docker_limit}MB) must be >= Redis maxmemory (${redis_maxmemory}MB)"
        return 1
    fi
    
    local overhead=$((docker_limit - redis_maxmemory))
    if [[ $overhead -lt 128 ]]; then
        validation_add_error "Warning: Docker limit should be at least 128MB more than Redis maxmemory (current overhead: ${overhead}MB)"
    fi
    
    return 0
}

validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        validation_add_error "Port must be a number (got: $port)"
        return 1
    fi
    
    if [[ $port -lt 1024 ]]; then
        validation_add_error "Port must be 1024 or higher (got: $port)"
        return 1
    fi
    
    if [[ $port -gt 65535 ]]; then
        validation_add_error "Port must be 65535 or lower (got: $port)"
        return 1
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        validation_add_error "Port $port is already in use"
        return 1
    fi
    
    return 0
}

validate_password_strength() {
    local password="$1"
    local min_length="${2:-16}"
    
    if [[ ${#password} -lt $min_length ]]; then
        validation_add_error "Password must be at least ${min_length} characters (got: ${#password})"
        return 1
    fi
    
    local has_upper=false
    local has_lower=false
    local has_digit=false
    local has_special=false
    
    [[ "$password" =~ [A-Z] ]] && has_upper=true
    [[ "$password" =~ [a-z] ]] && has_lower=true
    [[ "$password" =~ [0-9] ]] && has_digit=true
    [[ "$password" =~ [^a-zA-Z0-9] ]] && has_special=true
    
    local complexity_score=0
    [[ "$has_upper" == "true" ]] && ((complexity_score++))
    [[ "$has_lower" == "true" ]] && ((complexity_score++))
    [[ "$has_digit" == "true" ]] && ((complexity_score++))
    [[ "$has_special" == "true" ]] && ((complexity_score++))
    
    if [[ $complexity_score -lt 3 ]]; then
        validation_add_error "Password must contain at least 3 of: uppercase, lowercase, digits, special characters"
        return 1
    fi
    
    return 0
}

sanitize_input() {
    local input="$1"
    local type="${2:-general}"
    
    case "$type" in
        tenant)
            echo "$input" | tr -cd 'a-z0-9-'
            ;;
        numeric)
            echo "$input" | tr -cd '0-9'
            ;;
        alphanumeric)
            echo "$input" | tr -cd 'a-zA-Z0-9'
            ;;
        path)
            echo "$input" | tr -d ';|&$`<>(){}[]!'
            ;;
        *)
            echo "$input" | tr -d '\000-\037'
            ;;
    esac
}

validate_file_path() {
    local path="$1"
    local base_dir="${2:-$BASE_DIR}"
    
    if [[ "$path" =~ \.\. ]]; then
        validation_add_error "Path traversal detected in: $path"
        return 1
    fi
    
    if [[ "$path" =~ ^/ ]] && [[ ! "$path" =~ ^${base_dir} ]]; then
        validation_add_error "Path must be within base directory: $path"
        return 1
    fi
    
    if [[ "$path" =~ [\;\|\&\$\`\<\>\(\)\{\}\[\]!] ]]; then
        validation_add_error "Path contains invalid characters: $path"
        return 1
    fi
    
    return 0
}

validate_config_file() {
    local config_file="$1"
    local required_fields=("${@:2}")
    
    if [[ ! -f "$config_file" ]]; then
        validation_add_error "Configuration file not found: $config_file"
        return 1
    fi
    
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=" "$config_file"; then
            validation_add_error "Required field '$field' missing in $config_file"
        fi
    done
    
    if validation_has_errors; then
        return 1
    fi
    
    return 0
}

validate_system_config() {
    local config_file="${1:-/etc/cachepilot/system.yaml}"
    
    validation_clear_errors
    
    if [[ ! -f "$config_file" ]]; then
        validation_add_error "Configuration file not found: $config_file"
        return 1
    fi
    
    local required_paths=(
        "paths.base_dir"
        "paths.tenants_dir"
        "paths.ca_dir"
        "paths.backups_dir"
        "paths.logs_dir"
    )
    
    local required_network=(
        "network.internal_ip"
        "network.public_ip"
        "network.redis_port_start"
        "network.redis_port_end"
    )
    
    for field in "${required_paths[@]}" "${required_network[@]}"; do
        if ! grep -q "${field#*.}:" "$config_file"; then
            validation_add_error "Required field '$field' missing in configuration"
        fi
    done
    
    if validation_has_errors; then
        return 1
    fi
    
    local temp_base_dir="/opt/cachepilot"
    source "${temp_base_dir}/lib/common.sh" 2>/dev/null || true
    
    if [[ -z "${CONFIG_PATHS[base_dir]}" ]]; then
        load_system_config 2>/dev/null || true
    fi
    
    local paths_to_check=(
        "${CONFIG_PATHS[base_dir]}"
        "$(dirname "${CONFIG_PATHS[tenants_dir]}")"
        "$(dirname "${CONFIG_PATHS[ca_dir]}")"
        "$(dirname "${CONFIG_PATHS[backups_dir]}")"
        "$(dirname "${CONFIG_PATHS[logs_dir]}")"
    )
    
    for path in "${paths_to_check[@]}"; do
        if [[ -n "$path" ]] && [[ ! -d "$path" ]] && [[ ! -w "$(dirname "$path")" ]]; then
            validation_add_error "Path does not exist and cannot be created: $path"
        fi
    done
    
    local redis_start="${CONFIG_NETWORK[redis_port_start]}"
    local redis_end="${CONFIG_NETWORK[redis_port_end]}"
    
    if [[ $redis_start -lt 1024 ]] || [[ $redis_start -gt 65535 ]]; then
        validation_add_error "Redis port start must be between 1024 and 65535 (got: $redis_start)"
    fi
    
    if [[ $redis_end -lt 1024 ]] || [[ $redis_end -gt 65535 ]]; then
        validation_add_error "Redis port end must be between 1024 and 65535 (got: $redis_end)"
    fi
    
    if [[ $redis_start -ge $redis_end ]]; then
        validation_add_error "Redis port start ($redis_start) must be less than port end ($redis_end)"
    fi
    
    local redis_mem="${CONFIG_DEFAULTS[redis_memory_mb]}"
    local docker_mem="${CONFIG_DEFAULTS[docker_memory_mb]}"
    
    if [[ $redis_mem -lt 64 ]]; then
        validation_add_error "Default Redis memory must be at least 64MB (got: ${redis_mem}MB)"
    fi
    
    if [[ $docker_mem -lt 128 ]]; then
        validation_add_error "Default Docker memory must be at least 128MB (got: ${docker_mem}MB)"
    fi
    
    if [[ $docker_mem -lt $redis_mem ]]; then
        validation_add_error "Default Docker memory (${docker_mem}MB) must be >= Redis memory (${redis_mem}MB)"
    fi
    
    local cert_days="${CONFIG_CERTS[validity_days]}"
    if [[ $cert_days -lt 1 ]] || [[ $cert_days -gt 3650 ]]; then
        validation_add_error "Certificate validity days must be between 1 and 3650 (got: $cert_days)"
    fi
    
    if validation_has_errors; then
        return 1
    fi
    
    return 0
}

validate_email() {
    local email="$1"
    
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        validation_add_error "Invalid email address: $email"
        return 1
    fi
    
    return 0
}

validate_url() {
    local url="$1"
    
    if [[ ! "$url" =~ ^https?:// ]]; then
        validation_add_error "URL must start with http:// or https://"
        return 1
    fi
    
    return 0
}

validate_json() {
    local json_string="$1"
    
    if command -v jq &> /dev/null; then
        if ! echo "$json_string" | jq empty 2>/dev/null; then
            validation_add_error "Invalid JSON format"
            return 1
        fi
    else
        if [[ ! "$json_string" =~ ^\{.*\}$ ]] && [[ ! "$json_string" =~ ^\[.*\]$ ]]; then
            validation_add_error "Invalid JSON format (must start with { or [)"
            return 1
        fi
    fi
    
    return 0
}

validate_cron_expression() {
    local cron_expr="$1"
    
    local fields=($cron_expr)
    
    if [[ ${#fields[@]} -ne 5 ]]; then
        validation_add_error "Cron expression must have 5 fields (minute hour day month weekday)"
        return 1
    fi
    
    return 0
}

validate_batch() {
    validation_clear_errors
    return 0
}
