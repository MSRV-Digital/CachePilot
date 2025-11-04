#!/usr/bin/env bash
#
# CachePilot - Common Functions Library
#
# Core utility functions, configuration loading, validation helpers,
# and legacy function wrappers for backward compatibility.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

declare -A CONFIG_PATHS
declare -A CONFIG_NETWORK
declare -A CONFIG_DEFAULTS
declare -A CONFIG_ORG
declare -A CONFIG_CERTS
declare -A CONFIG_MONITORING
declare -A CONFIG_BACKUP

parse_yaml() {
    local yaml_file="$1"
    local prefix="$2"
    local s='[[:space:]]*'
    local w='[a-zA-Z0-9_]*'
    local fs=$(echo @|tr @ '\034')
    
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$yaml_file" |
    awk -F$fs '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            value = $3;
            sub(/[[:space:]]*#.*$/, "", value);
            sub(/[[:space:]]+$/, "", value);
            printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, value);
        }
    }'
}

ensure_etc_config() {
    local config_dir="/etc/cachepilot"
    
    if [[ ! -d "$config_dir" ]]; then
        echo "ERROR: Configuration directory not found: $config_dir" >&2
        echo "Please run the installation script to create the configuration directory." >&2
        return 1
    fi
    
    if [[ ! -r "$config_dir" ]]; then
        echo "ERROR: Configuration directory is not readable: $config_dir" >&2
        echo "Please check directory permissions." >&2
        return 1
    fi
    
    return 0
}

load_system_config() {
    local config_file="${CONFIG_FILE:-/etc/cachepilot/system.yaml}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        echo "Configuration files should be located in /etc/cachepilot/" >&2
        echo "Please run the installation or upgrade script to set up configuration." >&2
        return 1
    fi
    
    eval $(parse_yaml "$config_file" "CONFIG_")
    
    CONFIG_PATHS[base_dir]="${CONFIG_paths_base_dir}"
    CONFIG_PATHS[tenants_dir]="${CONFIG_paths_tenants_dir}"
    CONFIG_PATHS[ca_dir]="${CONFIG_paths_ca_dir}"
    CONFIG_PATHS[backups_dir]="${CONFIG_paths_backups_dir}"
    CONFIG_PATHS[logs_dir]="${CONFIG_paths_logs_dir}"
    CONFIG_PATHS[cli_dir]="${CONFIG_paths_cli_dir}"
    CONFIG_PATHS[api_dir]="${CONFIG_paths_api_dir}"
    CONFIG_PATHS[frontend_dir]="${CONFIG_paths_frontend_dir}"
    CONFIG_PATHS[config_dir]="${CONFIG_paths_config_dir}"
    CONFIG_PATHS[scripts_dir]="${CONFIG_paths_scripts_dir}"
    
    CONFIG_NETWORK[internal_ip]="${CONFIG_network_internal_ip}"
    CONFIG_NETWORK[public_ip]="${CONFIG_network_public_ip}"
    CONFIG_NETWORK[redis_port_start]="${CONFIG_network_redis_port_start}"
    CONFIG_NETWORK[redis_port_end]="${CONFIG_network_redis_port_end}"
    CONFIG_NETWORK[insight_port_start]="${CONFIG_network_insight_port_start}"
    CONFIG_NETWORK[insight_port_end]="${CONFIG_network_insight_port_end}"
    
    CONFIG_DEFAULTS[redis_memory_mb]="${CONFIG_defaults_redis_memory_mb}"
    CONFIG_DEFAULTS[docker_memory_mb]="${CONFIG_defaults_docker_memory_mb}"
    
    CONFIG_ORG[name]="${CONFIG_organization_name}"
    CONFIG_ORG[contact_name]="${CONFIG_organization_contact_name}"
    CONFIG_ORG[contact_email]="${CONFIG_organization_contact_email}"
    CONFIG_ORG[contact_phone]="${CONFIG_organization_contact_phone}"
    CONFIG_ORG[contact_web]="${CONFIG_organization_contact_web}"
    
    CONFIG_CERTS[country]="${CONFIG_certificates_country}"
    CONFIG_CERTS[state]="${CONFIG_certificates_state}"
    CONFIG_CERTS[city]="${CONFIG_certificates_city}"
    CONFIG_CERTS[validity_days]="${CONFIG_certificates_validity_days}"
    
    CONFIG_MONITORING[health_check_interval]="${CONFIG_monitoring_health_check_interval}"
    CONFIG_MONITORING[alert_retention_days]="${CONFIG_monitoring_alert_retention_days}"
    CONFIG_MONITORING[metrics_retention_days]="${CONFIG_monitoring_metrics_retention_days}"
    
    CONFIG_BACKUP[retention_days]="${CONFIG_backup_retention_days}"
    CONFIG_BACKUP[compression]="${CONFIG_backup_compression}"
    CONFIG_BACKUP[verify_after_backup]="${CONFIG_backup_verify_after_backup}"
    
    BASE_DIR="${BASE_DIR:-${CONFIG_PATHS[base_dir]}}"
    TENANTS_DIR="${TENANTS_DIR:-${CONFIG_PATHS[tenants_dir]}}"
    CA_DIR="${CA_DIR:-${CONFIG_PATHS[ca_dir]}}"
    BACKUPS_DIR="${BACKUPS_DIR:-${CONFIG_PATHS[backups_dir]}}"
    LOGS_DIR="${LOGS_DIR:-${CONFIG_PATHS[logs_dir]}}"
    
    export BASE_DIR TENANTS_DIR CA_DIR BACKUPS_DIR LOGS_DIR
    
    INTERNAL_IP="${CONFIG_NETWORK[internal_ip]}"
    PUBLIC_IP="${CONFIG_NETWORK[public_ip]}"
    REDIS_PORT_START="${CONFIG_NETWORK[redis_port_start]}"
    REDIS_PORT_END="${CONFIG_NETWORK[redis_port_end]}"
    INSIGHT_PORT_START="${CONFIG_NETWORK[insight_port_start]}"
    INSIGHT_PORT_END="${CONFIG_NETWORK[insight_port_end]}"
    
    DEFAULT_REDIS_MEMORY="${CONFIG_DEFAULTS[redis_memory_mb]}"
    DEFAULT_DOCKER_MEMORY="${CONFIG_DEFAULTS[docker_memory_mb]}"
    
    ORGANIZATION="${CONFIG_ORG[name]}"
    CONTACT_NAME="${CONFIG_ORG[contact_name]}"
    CONTACT_EMAIL="${CONFIG_ORG[contact_email]}"
    CONTACT_PHONE="${CONFIG_ORG[contact_phone]}"
    CONTACT_WEB="${CONFIG_ORG[contact_web]}"
    
    CERT_COUNTRY="${CONFIG_CERTS[country]}"
    CERT_STATE="${CONFIG_CERTS[state]}"
    CERT_CITY="${CONFIG_CERTS[city]}"
    CERT_VALIDITY_DAYS="${CONFIG_CERTS[validity_days]}"
    
    return 0
}

get_config_path() {
    local path_key="$1"
    echo "${CONFIG_PATHS[$path_key]}"
}

get_config_network() {
    local network_key="$1"
    echo "${CONFIG_NETWORK[$network_key]}"
}

get_config_default() {
    local default_key="$1"
    echo "${CONFIG_DEFAULTS[$default_key]}"
}

load_paths_from_config() {
    local config_file="${CONFIG_FILE:-/etc/cachepilot/system.yaml}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    eval $(parse_yaml "$config_file" "CONFIG_")
    
    export BASE_DIR="${BASE_DIR:-${CONFIG_paths_base_dir:-/opt/cachepilot}}"
    export TENANTS_DIR="${TENANTS_DIR:-${CONFIG_paths_tenants_dir:-/var/cachepilot/tenants}}"
    export CA_DIR="${CA_DIR:-${CONFIG_paths_ca_dir:-/var/cachepilot/ca}}"
    export BACKUPS_DIR="${BACKUPS_DIR:-${CONFIG_paths_backups_dir:-/var/cachepilot/backups}}"
    export LOGS_DIR="${LOGS_DIR:-${CONFIG_paths_logs_dir:-/var/log/cachepilot}}"
    export CLI_DIR="${CLI_DIR:-${CONFIG_paths_cli_dir:-/opt/cachepilot/cli}}"
    export API_DIR="${API_DIR:-${CONFIG_paths_api_dir:-/opt/cachepilot/api}}"
    export FRONTEND_DIR="${FRONTEND_DIR:-${CONFIG_paths_frontend_dir:-/opt/cachepilot/frontend}}"
    export CONFIG_DIR="${CONFIG_DIR:-${CONFIG_paths_config_dir:-/etc/cachepilot}}"
    export SCRIPTS_DIR="${SCRIPTS_DIR:-${CONFIG_paths_scripts_dir:-/opt/cachepilot/scripts}}"
    
    return 0
}

validate_directory_structure() {
    local exit_code=0
    local required_dirs=(
        "$BASE_DIR:Application base directory"
        "/etc/cachepilot:Configuration directory"
        "$TENANTS_DIR:Tenants data directory"
        "$CA_DIR:Certificate Authority directory"
        "$BACKUPS_DIR:Backups directory"
        "$LOGS_DIR:Logs directory"
    )
    
    for dir_info in "${required_dirs[@]}"; do
        local dir="${dir_info%%:*}"
        local desc="${dir_info#*:}"
        
        if [[ ! -d "$dir" ]]; then
            echo "WARNING: $desc does not exist: $dir" >&2
            exit_code=1
        elif [[ ! -r "$dir" ]] || [[ ! -w "$dir" ]]; then
            echo "WARNING: $desc is not accessible: $dir" >&2
            exit_code=1
        fi
    done
    
    return $exit_code
}

ensure_directory_permissions() {
    local user="${1:-root}"
    local group="${2:-root}"
    
    mkdir -p "$TENANTS_DIR" "$CA_DIR" "$BACKUPS_DIR" "$LOGS_DIR" 2>/dev/null || true
    
    if command -v chown &>/dev/null; then
        chown -R "$user:$group" "$TENANTS_DIR" 2>/dev/null || true
        chown -R "$user:$group" "$CA_DIR" 2>/dev/null || true
        chown -R "$user:$group" "$BACKUPS_DIR" 2>/dev/null || true
        chown -R "$user:$group" "$LOGS_DIR" 2>/dev/null || true
    fi
    
    chmod 750 "$TENANTS_DIR" 2>/dev/null || true
    chmod 750 "$BACKUPS_DIR" 2>/dev/null || true
    chmod 700 "$CA_DIR" 2>/dev/null || true
    chmod 755 "$LOGS_DIR" 2>/dev/null || true
    
    return 0
}

load_system_config

if [[ -f "${LIB_DIR}/logger.sh" ]]; then
    source "${LIB_DIR}/logger.sh"
    STRUCTURED_LOGGING=true
else
    STRUCTURED_LOGGING=false
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        log_info "common" "$*"
    else
        echo -e "${GREEN}[INFO]${NC} $*"
    fi
}

warn() {
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        log_warn "common" "$*"
    else
        echo -e "${YELLOW}[WARN]${NC} $*" >&2
    fi
}

error() {
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        log_error "common" "$*"
    else
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
    exit 1
}

success() {
    if [[ "$STRUCTURED_LOGGING" == "true" ]]; then
        log_info "common" "✓ $*"
    else
        echo -e "${GREEN}[SUCCESS]${NC} $*"
    fi
}

validate_tenant_name() {
    local tenant="$1"
    if [[ ! "$tenant" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
        error "Invalid tenant name. Use lowercase alphanumeric and hyphens only."
    fi
}

tenant_exists() {
    local tenant="$1"
    [[ -d "${TENANTS_DIR}/${tenant}" ]]
}

require_tenant() {
    local tenant="$1"
    if ! tenant_exists "$tenant"; then
        error "Tenant '$tenant' does not exist"
    fi
}

get_next_port() {
    local start_port="${REDIS_PORT_START:-7300}"
    local end_port="${REDIS_PORT_END:-7399}"
    local used_ports=$(find "${TENANTS_DIR}" -name "config.env" -exec grep -h "^PORT=" {} \; 2>/dev/null | cut -d= -f2 | sort -n)
    
    for port in $(seq $start_port $end_port); do
        if ! echo "$used_ports" | grep -q "^${port}$"; then
            echo "$port"
            return 0
        fi
    done
    
    error "No available ports in range ${start_port}-${end_port}"
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

format_bytes() {
    local bytes="${1:-0}"
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    else
        echo "${bytes}B"
    fi
}

format_uptime() {
    local seconds="${1:-0}"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

init_system() {
    log "Initializing CachePilot system..."
    
    mkdir -p "${BASE_DIR}"
    mkdir -p "${TENANTS_DIR}"
    mkdir -p "${CA_DIR}"
    mkdir -p "${BACKUPS_DIR}"
    mkdir -p "${LOGS_DIR}"
    
    ensure_directory_permissions
    
    if [[ ! -f "${CA_DIR}/ca.key" ]]; then
        log "Generating CA certificate..."
        generate_ca
        success "CA certificate generated"
    else
        log "CA certificate already exists"
    fi
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker network inspect cachepilot-net &> /dev/null; then
        log "Creating Docker network..."
        docker network create cachepilot-net
    fi
    
    success "System initialized successfully"
}
