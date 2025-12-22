#!/usr/bin/env bash
#
# CachePilot - Docker Container Management Library
#
# Manages Docker Compose configurations, container lifecycle, and health checks
# for Redis instances with TLS support and resource limits.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.2-Beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

create_docker_compose() {
    local tenant="$1"
    local port_tls="$2"
    local password="$3"
    local maxmemory="${4:-256}"
    local docker_limit="${5:-512}"
    local security_mode="${6:-tls-only}"
    local port_plain="${7:-}"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    local bind_ip="${INTERNAL_IP}"
    if [[ "${bind_ip}" == "localhost" ]]; then
        bind_ip="127.0.0.1"
    fi
    
    # Build port mappings based on security mode
    local port_mappings=""
    case "$security_mode" in
        "tls-only")
            # TLS only: Map external TLS port to internal TLS port (6380)
            port_mappings="      - \"${bind_ip}:${port_tls}:6380\""
            ;;
        "dual-mode")
            # Both modes: Map both ports
            port_mappings="      - \"${bind_ip}:${port_tls}:6380\"
      - \"${bind_ip}:${port_plain}:6379\""
            ;;
        "plain-only")
            # Plain-Text only: Map external plain port to internal plain port (6379)
            port_mappings="      - \"${bind_ip}:${port_plain}:6379\""
            ;;
    esac
    
    # Build health check command based on security mode
    local healthcheck_cmd=""
    case "$security_mode" in
        "tls-only")
            # TLS only: Connect to TLS port 6380
            healthcheck_cmd='["CMD", "redis-cli", "-p", "6380", "--tls", "--cacert", "/certs/ca.crt", "--cert", "/certs/redis.crt", "--key", "/certs/redis.key", "-a", "'"${password}"'", "PING"]'
            ;;
        "dual-mode")
            # Dual mode: Use TLS port 6380 for health check
            healthcheck_cmd='["CMD", "redis-cli", "-p", "6380", "--tls", "--cacert", "/certs/ca.crt", "--cert", "/certs/redis.crt", "--key", "/certs/redis.key", "-a", "'"${password}"'", "PING"]'
            ;;
        "plain-only")
            # Plain-Text only: Connect to plain port 6379 (no TLS)
            healthcheck_cmd='["CMD", "redis-cli", "-p", "6379", "-a", "'"${password}"'", "PING"]'
            ;;
    esac
    
    cat > "${tenant_dir}/docker-compose.yml" << EOF

services:
  redis:
    image: redis:7-alpine
    container_name: redis-${tenant}
    restart: unless-stopped
    ports:
${port_mappings}
    volumes:
      - ./data:/data
      - ./certs:/certs:ro
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
    command: redis-server /usr/local/etc/redis/redis.conf
    networks:
      - cachepilot-net
    mem_limit: ${docker_limit}m
    healthcheck:
      test: ${healthcheck_cmd}
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 10s

networks:
  cachepilot-net:
    external: true
EOF
}

create_redis_config() {
    local tenant="$1"
    local password="$2"
    local maxmemory="$3"
    local security_mode="${4:-tls-only}"
    local persistence_mode="${5:-memory-only}"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    # Generate redis.conf based on security mode
    case "$security_mode" in
        "tls-only")
            # TLS only: Disable plain-text, enable TLS on internal port 6380
            cat > "${tenant_dir}/redis.conf" << EOF
# CachePilot Redis Configuration - TLS Only Mode
# Security Mode: tls-only (default, most secure)
bind 0.0.0.0

# Plain-Text port disabled for security
port 0

# Password authentication required
requirepass ${password}

# TLS Configuration (internal container port 6380)
tls-port 6380
tls-cert-file /certs/redis.crt
tls-key-file /certs/redis.key
tls-ca-cert-file /certs/ca.crt
tls-auth-clients optional
tls-protocols "TLSv1.2 TLSv1.3"
tls-ciphers DEFAULT:@SECLEVEL=1
tls-prefer-server-ciphers yes
EOF
            ;;
        "dual-mode")
            # Both modes: Enable both plain-text (6379) and TLS (6380)
            cat > "${tenant_dir}/redis.conf" << EOF
# CachePilot Redis Configuration - Dual Mode
# Security Mode: dual-mode (both TLS and Plain-Text available)
bind 0.0.0.0

# Plain-Text port enabled (internal container port 6379)
port 6379

# Password authentication required for both modes
requirepass ${password}

# TLS Configuration (internal container port 6380)
tls-port 6380
tls-cert-file /certs/redis.crt
tls-key-file /certs/redis.key
tls-ca-cert-file /certs/ca.crt
tls-auth-clients optional
tls-protocols "TLSv1.2 TLSv1.3"
tls-ciphers DEFAULT:@SECLEVEL=1
tls-prefer-server-ciphers yes
EOF
            ;;
        "plain-only")
            # Plain-Text only: Disable TLS, use password authentication
            cat > "${tenant_dir}/redis.conf" << EOF
# CachePilot Redis Configuration - Plain-Text Only Mode
# Security Mode: plain-only (simplified, password authentication only)
# WARNING: This mode does not use TLS encryption
bind 0.0.0.0

# Plain-Text port enabled (internal container port 6379)
port 6379

# TLS disabled
tls-port 0

# Password authentication required
requirepass ${password}
EOF
            ;;
    esac
    
    # Add common configuration (applies to all modes)
    cat >> "${tenant_dir}/redis.conf" << EOF

# Memory Management
maxmemory ${maxmemory}mb
maxmemory-policy allkeys-lru
EOF
    
    # Add persistence configuration based on mode
    if [[ "$persistence_mode" == "memory-only" ]]; then
        cat >> "${tenant_dir}/redis.conf" << EOF

# Persistence Configuration: MEMORY-ONLY MODE
# All disk writes disabled for maximum performance (1-5ms latency)
# Data will be lost on restart - use on-demand backups if needed
save ""
appendonly no
EOF
    else
        cat >> "${tenant_dir}/redis.conf" << EOF

# Persistence Configuration: PERSISTENT MODE
# Traditional RDB snapshots + AOF for data durability
save 900 1
save 300 10
save 60 10000

dir /data
dbfilename dump.rdb
rdbcompression yes

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
EOF
    fi
    
    cat >> "${tenant_dir}/redis.conf" << EOF

# Security: Disable dangerous commands
rename-command KEYS ""
rename-command CONFIG ""
rename-command SHUTDOWN ""
rename-command BGSAVE ""
rename-command BGREWRITEAOF ""
rename-command DEBUG ""

# Slow Log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Network Performance Optimizations
tcp-backlog 511
timeout 60
tcp-keepalive 30

# Client Connection Limits and Buffers
maxclients 10000
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# IO Threading for better network performance (Redis 6.0+)
io-threads 4
io-threads-do-reads yes

# Latency Monitoring
latency-monitor-threshold 100
EOF
}

start_container() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    cd "$tenant_dir"
    docker-compose up -d --remove-orphans 2>&1 | grep -v "Found orphan containers"
    
    log "Waiting for container to be healthy..."
    local max_wait=60
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if docker inspect "redis-${tenant}" --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
            success "Container is healthy"
            return 0
        fi
        sleep 1
        ((waited++))
    done
    
    warn "Container did not become healthy within ${max_wait}s"
    return 1
}

stop_container() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    cd "$tenant_dir"
    docker-compose down
}

restart_container() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    cd "$tenant_dir"
    docker-compose restart
}

update_all_instances() {
    log "Starting rolling update of all Redis instances..."
    
    log "Pulling latest Redis image..."
    docker pull redis:7-alpine
    
    local updated=0
    local failed=0
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [[ -d "$tenant_dir" ]]; then
            local tenant=$(basename "$tenant_dir")
            
            if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
                log "Updating tenant: $tenant"
                
                cd "$tenant_dir"
                if docker-compose up -d --force-recreate; then
                    log "Waiting for health check..."
                    
                    local count=0
                    until docker inspect "redis-${tenant}" --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy" || [ $count -eq 60 ]; do
                        sleep 1
                        ((count++))
                    done
                    
                    if docker inspect "redis-${tenant}" --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; then
                        success "Updated: $tenant"
                        ((updated++))
                    else
                        warn "Health check failed for: $tenant (timeout after 60s)"
                        ((failed++))
                    fi
                else
                    warn "Failed to update: $tenant"
                    ((failed++))
                fi
                
                sleep 2
            fi
        fi
    done
    
    echo ""
    success "Update complete: $updated successful, $failed failed"
}

get_container_stats() {
    local tenant="$1"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        echo "STOPPED"
        return 1
    fi
    
    docker stats "redis-${tenant}" --no-stream --format "json"
}
