#!/usr/bin/env bash
#
# CachePilot - Tenant Management Library
#
# Manages tenant lifecycle including creation, removal, start/stop operations,
# configuration updates, and password rotation.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
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
    local user="${AUDIT_USER:-${USER:-system}}"
    
    validate_tenant_name "$tenant"
    
    if tenant_exists "$tenant"; then
        error "Tenant '$tenant' already exists"
    fi
    
    log_audit "$user" "tenant_create" "$tenant" "{\"status\":\"started\"}"
    
    log "Creating new tenant: $tenant"
    
    local port=$(get_next_port)
    local password=$(generate_password)
    local maxmemory=256
    local docker_limit=512
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    mkdir -p "${tenant_dir}"/{data,certs,handover}
    
    cat > "${tenant_dir}/config.env" << EOF
TENANT=${tenant}
PORT=${port}
PASSWORD=${password}
MAXMEMORY=${maxmemory}
DOCKER_LIMIT=${docker_limit}
CREATED=$(date -Iseconds)
INSIGHT_PORT=0
BACKUP_ENABLED=true
BACKUP_SCHEDULE=daily
EOF
    
    log "Generating TLS certificates..."
    generate_tenant_cert "$tenant"
    cp "${CA_DIR}/ca.crt" "${tenant_dir}/certs/"
    
    log "Creating Redis configuration..."
    create_redis_config "$tenant" "$password" "$maxmemory"
    
    log "Creating Docker Compose configuration..."
    create_docker_compose "$tenant" "$port" "$password" "$maxmemory" "$docker_limit"
    
    log "Starting container..."
    if start_container "$tenant"; then
        log "Generating handover package..."
        generate_handover "$tenant"
        
        log_audit "$user" "tenant_create" "$tenant" "{\"status\":\"success\",\"port\":$port}"
        
        echo ""
        success "Tenant created successfully: $tenant"
        echo ""
        echo "Connection Details:"
        echo "  Host: ${INTERNAL_IP}"
        echo "  Port: $port"
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
    
    create_docker_compose "$tenant" "$PORT" "$PASSWORD" "$maxmemory" "$docker_limit"
    
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
    
    create_docker_compose "$tenant" "$PORT" "$new_password" "$MAXMEMORY" "$DOCKER_LIMIT"
    
    log "Restarting container..."
    restart_container "$tenant"
    
    log "Regenerating handover package..."
    generate_handover "$tenant"
    
    log_audit "$user" "password_rotate" "$tenant" "{\"status\":\"success\"}"
    
    success "Password rotated for tenant: $tenant"
    echo "New password: $new_password"
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
