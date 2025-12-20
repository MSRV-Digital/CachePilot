#!/usr/bin/env bash
#
# CachePilot - Docker Container Management Library
#
# Manages Docker Compose configurations, container lifecycle, and health checks
# for Redis instances with TLS support and resource limits.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

create_docker_compose() {
    local tenant="$1"
    local port="$2"
    local password="$3"
    local maxmemory="${4:-256}"
    local docker_limit="${5:-512}"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    local bind_ip="${INTERNAL_IP}"
    if [[ "${bind_ip}" == "localhost" ]]; then
        bind_ip="127.0.0.1"
    fi
    
    cat > "${tenant_dir}/docker-compose.yml" << EOF

services:
  redis:
    image: redis:7-alpine
    container_name: redis-${tenant}
    restart: unless-stopped
    ports:
      - "${bind_ip}:${port}:6379"
    volumes:
      - ./data:/data
      - ./certs:/certs:ro
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
    command: redis-server /usr/local/etc/redis/redis.conf
    networks:
      - cachepilot-net
    mem_limit: ${docker_limit}m
    healthcheck:
      test: ["CMD", "redis-cli", "--tls", "--cacert", "/certs/ca.crt", "--cert", "/certs/redis.crt", "--key", "/certs/redis.key", "-a", "${password}", "PING"]
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
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    cat > "${tenant_dir}/redis.conf" << EOF
bind 0.0.0.0
port 0
requirepass ${password}

tls-port 6379
tls-cert-file /certs/redis.crt
tls-key-file /certs/redis.key
tls-ca-cert-file /certs/ca.crt
tls-auth-clients optional
tls-protocols "TLSv1.2 TLSv1.3"
tls-ciphers DEFAULT:@SECLEVEL=1
tls-prefer-server-ciphers yes

maxmemory ${maxmemory}mb
maxmemory-policy allkeys-lru

save 900 1
save 300 10
save 60 10000

dir /data
dbfilename dump.rdb
rdbcompression yes

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

rename-command KEYS ""
rename-command CONFIG ""
rename-command SHUTDOWN ""
rename-command BGSAVE ""
rename-command BGREWRITEAOF ""
rename-command DEBUG ""

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
