#!/usr/bin/env bash
#
# CachePilot - Tenant Management Library
#
# Manages tenant lifecycle including creation, removal, start/stop operations,
# configuration updates, and password rotation.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.2-Beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

if [[ -f "${LIB_DIR}/validator.sh" ]]; then
    source "${LIB_DIR}/validator.sh"
fi

create_tenant() {
    local tenant="$1"
    local maxmemory="${2:-256}"
    local docker_limit="${3:-}"
    local security_mode="${4:-tls-only}"
    local custom_password="${5:-}"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    # Handle docker_limit - calculate default or validate
    if [[ -z "$docker_limit" ]] || [[ "$docker_limit" == "no" ]] || [[ "$docker_limit" == "yes" ]]; then
        # Calculate default: maxmemory * 2
        docker_limit=$((maxmemory * 2))
        log "Docker limit not specified or invalid, using default: ${docker_limit}MB"
    fi
    
    validate_tenant_name "$tenant"
    
    if tenant_exists "$tenant"; then
        error "Tenant '$tenant' already exists"
    fi
    
    # Validate security mode
    if [[ ! "$security_mode" =~ ^(tls-only|dual-mode|plain-only)$ ]]; then
        error "Invalid security mode: $security_mode. Valid options: tls-only, dual-mode, plain-only"
    fi
    
    log_audit "$user" "tenant_create" "$tenant" "{\"status\":\"started\",\"security_mode\":\"$security_mode\"}"
    
    log "Creating new tenant: $tenant (mode: $security_mode)"
    
    # Allocate ports based on security mode
    local port_tls=""
    local port_plain=""
    
    case "$security_mode" in
        "tls-only")
            port_tls=$(get_next_tls_port)
            log "Allocated TLS port: $port_tls"
            ;;
        "dual-mode")
            port_tls=$(get_next_tls_port)
            # Try to use paired port (+300 offset), fallback to next available
            port_plain=$(calculate_plain_port_from_tls "$port_tls")
            if port_is_in_use "$port_plain"; then
                port_plain=$(get_next_plain_port)
                warn "Paired port not available, using: $port_plain"
            fi
            log "Allocated TLS port: $port_tls, Plain-Text port: $port_plain"
            ;;
        "plain-only")
            port_plain=$(get_next_plain_port)
            log "Allocated Plain-Text port: $port_plain"
            ;;
    esac
    
    local password=$(generate_password)
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    mkdir -p "${tenant_dir}"/{data,certs,handover}
    
    # Create config.env with new format
    cat > "${tenant_dir}/config.env" << EOF
TENANT=${tenant}
SECURITY_MODE=${security_mode}
PORT_TLS=${port_tls}
PORT_PLAIN=${port_plain}
PASSWORD=${password}
MAXMEMORY=${maxmemory}
DOCKER_LIMIT=${docker_limit}
CREATED=$(date -Iseconds)
INSIGHT_PORT=0
BACKUP_ENABLED=true
BACKUP_SCHEDULE=daily
EOF
    
    # Generate TLS certificates (even for plain-only, in case mode is changed later)
    log "Generating TLS certificates..."
    generate_tenant_cert "$tenant"
    cp "${CA_DIR}/ca.crt" "${tenant_dir}/certs/"
    
    log "Creating Redis configuration..."
    create_redis_config "$tenant" "$password" "$maxmemory" "$security_mode"
    
    log "Creating Docker Compose configuration..."
    create_docker_compose "$tenant" "$port_tls" "$password" "$maxmemory" "$docker_limit" "$security_mode" "$port_plain"
    
    log "Starting container..."
    if start_container "$tenant"; then
        log "Generating handover package..."
        generate_handover "$tenant"
        
        log_audit "$user" "tenant_create" "$tenant" "{\"status\":\"success\",\"security_mode\":\"$security_mode\",\"port_tls\":\"$port_tls\",\"port_plain\":\"$port_plain\"}"
        
        echo ""
        success "Tenant created successfully: $tenant"
        echo ""
        echo "Security Mode: $security_mode"
        echo "Connection Details:"
        echo "  Host: ${INTERNAL_IP}"
        
        case "$security_mode" in
            "tls-only")
                echo "  TLS Port: $port_tls"
                echo "  Connection: rediss://:${password}@${INTERNAL_IP}:${port_tls}"
                ;;
            "dual-mode")
                echo "  TLS Port: $port_tls"
                echo "  Plain-Text Port: $port_plain"
                echo "  TLS Connection: rediss://:${password}@${INTERNAL_IP}:${port_tls}"
                echo "  Plain Connection: redis://:${password}@${INTERNAL_IP}:${port_plain}"
                ;;
            "plain-only")
                echo "  Plain-Text Port: $port_plain"
                echo "  Connection: redis://:${password}@${INTERNAL_IP}:${port_plain}"
                ;;
        esac
        
        echo "  Password: $password"
        echo ""
        echo "Handover package: ${tenant_dir}/handover/${tenant}-handover.zip"
    else
        log_audit "$user" "tenant_create" "$tenant" "{\"status\":\"failed\"}"
        error "Failed to start container for tenant: $tenant"
    fi
}

remove_tenant() {
    local tenant="$1"
    local force="${2:-}"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    log_audit "$user" "tenant_delete" "$tenant" "{\"status\":\"requested\"}"
    
    if [[ "$force" != "--force" ]]; then
        warn "This will permanently delete tenant '$tenant' and all its data!"
        read -p "Type 'yes' to confirm: " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            log_audit "$user" "tenant_delete" "$tenant" "{\"status\":\"cancelled\"}"
            error "Deletion cancelled"
        fi
    else
        warn "Force deleting tenant '$tenant' and all its data!"
    fi
    
    log "Stopping containers..."
    docker rm -f "nginx-${tenant}" 2>/dev/null || true
    docker rm -f "redisinsight-${tenant}" 2>/dev/null || true
    docker rm -f "redis-${tenant}" 2>/dev/null || true
    
    log "Removing tenant directory..."
    rm -rf "$tenant_dir"
    
    log_audit "$user" "tenant_delete" "$tenant" "{\"status\":\"success\"}"
    
    success "Tenant removed: $tenant"
}

start_tenant() {
    local tenant="$1"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    log "Starting tenant: $tenant"
    
    if ! start_container "$tenant"; then
        if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
            warn "Container started but health check timed out - may still be starting"
            log_audit "$user" "tenant_start" "$tenant" "{\"status\":\"success\",\"note\":\"health_check_timeout\"}"
            success "Tenant started: $tenant (health check pending)"
            return 0
        else
            log_audit "$user" "tenant_start" "$tenant" "{\"status\":\"failed\"}"
            error "Failed to start tenant: $tenant"
        fi
    fi
    
    log_audit "$user" "tenant_start" "$tenant" "{\"status\":\"success\"}"
    
    success "Tenant started: $tenant"
}

stop_tenant() {
    local tenant="$1"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    log "Stopping tenant: $tenant"
    stop_container "$tenant"
    
    log_audit "$user" "tenant_stop" "$tenant" "{\"status\":\"success\"}"
    
    success "Tenant stopped: $tenant"
}

restart_tenant() {
    local tenant="$1"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    log "Restarting tenant: $tenant"
    restart_container "$tenant"
    
    log_audit "$user" "tenant_restart" "$tenant" "{\"status\":\"success\"}"
    
    success "Tenant restarted: $tenant"
}

set_memory_limits() {
    local tenant="$1"
    local maxmemory="$2"
    local docker_limit="$3"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    if [[ $maxmemory -ge $docker_limit ]]; then
        error "maxmemory must be less than docker_limit"
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    source "${tenant_dir}/config.env"
    
    log "Updating memory limits for tenant: $tenant"
    log "  Redis maxmemory: ${maxmemory}MB"
    log "  Docker limit: ${docker_limit}MB"
    
    sed -i "s/^MAXMEMORY=.*/MAXMEMORY=${maxmemory}/" "${tenant_dir}/config.env"
    sed -i "s/^DOCKER_LIMIT=.*/DOCKER_LIMIT=${docker_limit}/" "${tenant_dir}/config.env"
    
    sed -i "s/^maxmemory .*/maxmemory ${maxmemory}mb/" "${tenant_dir}/redis.conf"
    
    # Use appropriate variables based on security mode
    local port_tls="${PORT_TLS:-}"
    local port_plain="${PORT_PLAIN:-}"
    local security_mode="${SECURITY_MODE:-tls-only}"
    
    create_docker_compose "$tenant" "$port_tls" "$PASSWORD" "$maxmemory" "$docker_limit" "$security_mode" "$port_plain"
    
    log "Restarting container..."
    restart_container "$tenant"
    
    log_audit "$user" "tenant_modify" "$tenant" "{\"action\":\"set_memory_limits\",\"maxmemory\":$maxmemory,\"docker_limit\":$docker_limit}"
    
    success "Memory limits updated for tenant: $tenant"
}

rotate_password() {
    local tenant="$1"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    local new_password=$(generate_password)
    
    log "Rotating password for tenant: $tenant"
    
    sed -i "s/^PASSWORD=.*/PASSWORD=${new_password}/" "${tenant_dir}/config.env"
    sed -i "s/^requirepass .*/requirepass ${new_password}/" "${tenant_dir}/redis.conf"
    
    # Use appropriate variables based on security mode
    local port_tls="${PORT_TLS:-}"
    local port_plain="${PORT_PLAIN:-}"
    local security_mode="${SECURITY_MODE:-tls-only}"
    
    create_docker_compose "$tenant" "$port_tls" "$new_password" "$MAXMEMORY" "$DOCKER_LIMIT" "$security_mode" "$port_plain"
    
    log "Restarting container..."
    restart_container "$tenant"
    
    log "Regenerating handover package..."
    generate_handover "$tenant"
    
    log_audit "$user" "password_rotate" "$tenant" "{\"status\":\"success\"}"
    
    success "Password rotated for tenant: $tenant"
    echo "New password: $new_password"
    echo "New handover package: ${tenant_dir}/handover/${tenant}-handover.zip"
}

set_access_mode() {
    local tenant="$1"
    local new_mode="$2"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    # Validate security mode
    if [[ ! "$new_mode" =~ ^(tls-only|dual-mode|plain-only)$ ]]; then
        error "Invalid security mode: $new_mode. Valid options: tls-only, dual-mode, plain-only"
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    local current_mode="${SECURITY_MODE:-tls-only}"
    
    if [[ "$current_mode" == "$new_mode" ]]; then
        warn "Tenant is already in $new_mode mode"
        return 0
    fi
    
    log "Changing security mode for tenant: $tenant"
    log "  Current mode: $current_mode"
    log "  New mode: $new_mode"
    
    # Handle port allocation based on mode change
    local port_tls="${PORT_TLS:-${PORT:-}}"
    local port_plain="${PORT_PLAIN:-}"
    
    case "$new_mode" in
        "tls-only")
            # Switching to TLS only - ensure we have TLS port
            if [[ -z "$port_tls" ]]; then
                port_tls=$(get_next_tls_port)
                log "Allocated new TLS port: $port_tls"
            fi
            port_plain=""  # Clear plain port
            ;;
        "dual-mode")
            # Switching to dual mode - ensure we have both ports
            if [[ -z "$port_tls" ]]; then
                port_tls=$(get_next_tls_port)
                log "Allocated new TLS port: $port_tls"
            fi
            if [[ -z "$port_plain" ]]; then
                port_plain=$(calculate_plain_port_from_tls "$port_tls")
                if port_is_in_use "$port_plain"; then
                    port_plain=$(get_next_plain_port)
                fi
                log "Allocated new Plain-Text port: $port_plain"
            fi
            ;;
        "plain-only")
            # Switching to plain only - ensure we have plain port
            if [[ -z "$port_plain" ]]; then
                port_plain=$(get_next_plain_port)
                log "Allocated new Plain-Text port: $port_plain"
            fi
            # Keep TLS port in config but don't use it
            ;;
    esac
    
    # Update config.env
    sed -i "s/^SECURITY_MODE=.*/SECURITY_MODE=${new_mode}/" "${tenant_dir}/config.env"
    sed -i "s/^PORT_TLS=.*/PORT_TLS=${port_tls}/" "${tenant_dir}/config.env"
    sed -i "s/^PORT_PLAIN=.*/PORT_PLAIN=${port_plain}/" "${tenant_dir}/config.env"
    
    # Regenerate Redis configuration
    log "Updating Redis configuration..."
    create_redis_config "$tenant" "$PASSWORD" "$MAXMEMORY" "$new_mode"
    
    # Regenerate Docker Compose configuration
    log "Updating Docker Compose configuration..."
    create_docker_compose "$tenant" "$port_tls" "$PASSWORD" "$MAXMEMORY" "$DOCKER_LIMIT" "$new_mode" "$port_plain"
    
    # Restart container
    log "Restarting container..."
    restart_container "$tenant"
    
    # Regenerate handover package
    log "Regenerating handover package..."
    generate_handover "$tenant"
    
    log_audit "$user" "tenant_modify" "$tenant" "{\"action\":\"set_access_mode\",\"old_mode\":\"$current_mode\",\"new_mode\":\"$new_mode\"}"
    
    echo ""
    success "Security mode updated for tenant: $tenant"
    echo ""
    echo "New Security Mode: $new_mode"
    echo "Connection Details:"
    echo "  Host: ${INTERNAL_IP}"
    
    case "$new_mode" in
        "tls-only")
            echo "  TLS Port: $port_tls"
            echo "  Connection: rediss://:${PASSWORD}@${INTERNAL_IP}:${port_tls}"
            ;;
        "dual-mode")
            echo "  TLS Port: $port_tls"
            echo "  Plain-Text Port: $port_plain"
            echo "  TLS Connection: rediss://:${PASSWORD}@${INTERNAL_IP}:${port_tls}"
            echo "  Plain Connection: redis://:${PASSWORD}@${INTERNAL_IP}:${port_plain}"
            ;;
        "plain-only")
            echo "  Plain-Text Port: $port_plain"
            echo "  Connection: redis://:${PASSWORD}@${INTERNAL_IP}:${port_plain}"
            ;;
    esac
    echo ""
    echo "New handover package: ${tenant_dir}/handover/${tenant}-handover.zip"
}

show_logs() {
    local tenant="$1"
    local lines="${2:-100}"
    
    require_tenant "$tenant"
    
    docker logs "redis-${tenant}" --tail "$lines" --follow
}

backup_tenant() {
    local tenant="$1"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    local backup_dir="${BACKUPS_DIR}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${backup_dir}/${tenant}-${timestamp}.tar.gz"
    
    mkdir -p "$backup_dir"
    
    log "Creating backup for tenant: $tenant"
    
    if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        docker exec "redis-${tenant}" redis-cli --tls --cacert /certs/ca.crt \
            --cert /certs/redis.crt --key /certs/redis.key \
            -a "$(grep PASSWORD "${tenant_dir}/config.env" | cut -d= -f2)" \
            SAVE 2>&1 | grep -v "Using a password"
    fi
    
    tar -czf "$backup_file" -C "${TENANTS_DIR}" "${tenant}/data" "${tenant}/config.env"
    
    local backup_size=$(du -b "$backup_file" | cut -f1)
    log_audit "$user" "backup_create" "$tenant" "{\"file\":\"$backup_file\",\"size\":$backup_size}"
    
    success "Backup created: $backup_file"
    echo "Size: $(du -h "$backup_file" | cut -f1)"
}

restore_tenant() {
    local tenant="$1"
    local backup_file="$2"
    local user="${AUDIT_USER:-${USER:-system}}"
    
    require_tenant "$tenant"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    log_audit "$user" "backup_restore" "$tenant" "{\"file\":\"$backup_file\",\"status\":\"requested\"}"
    
    warn "This will overwrite current data for tenant: $tenant"
    read -p "Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_audit "$user" "backup_restore" "$tenant" "{\"file\":\"$backup_file\",\"status\":\"cancelled\"}"
        log "Aborted"
        return 0
    fi
    
    log "Stopping tenant..."
    stop_tenant "$tenant"
    
    log "Restoring backup..."
    tar -xzf "$backup_file" -C "${TENANTS_DIR}"
    
    log "Starting tenant..."
    start_tenant "$tenant"
    
    log_audit "$user" "backup_restore" "$tenant" "{\"file\":\"$backup_file\",\"status\":\"success\"}"
    
    success "Backup restored for tenant: $tenant"
}
