#!/usr/bin/env bash
#
# CachePilot - RedisInsight Management Library
#
# Manages RedisInsight web interface deployment with Nginx reverse proxy,
# HTTPS, and basic authentication for tenant access.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.2-Beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

get_next_insight_port() {
    local start_port=8300
    local end_port=8399
    local used_ports=$(find "${TENANTS_DIR}" -name "config.env" -exec grep -h "^INSIGHT_PORT=" {} \; 2>/dev/null | cut -d= -f2 | sort -n)
    
    for port in $(seq $start_port $end_port); do
        if ! echo "$used_ports" | grep -q "^${port}$"; then
            echo "$port"
            return 0
        fi
    done
    
    error "No available RedisInsight ports in range ${start_port}-${end_port}"
}

enable_redisinsight() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    if [[ -n "${INSIGHT_PORT:-}" ]] && [[ "${INSIGHT_PORT:-0}" != "0" ]]; then
        warn "RedisInsight is already enabled for tenant: $tenant (Port: ${INSIGHT_PORT})"
        return 0
    fi
    
    local insight_port=$(get_next_insight_port)
    local insight_user="admin"
    local insight_pass=$(generate_password 16)
    
    log "Enabling RedisInsight for tenant: $tenant"
    log "  RedisInsight Port: ${insight_port}"
    log "  Public URL: https://${PUBLIC_IP}:${insight_port}"
    
    {
        echo "INSIGHT_PORT=${insight_port}"
        echo "INSIGHT_USER=${insight_user}"
        echo "INSIGHT_PASS=${insight_pass}"
    } >> "${tenant_dir}/config.env"
    
    mkdir -p "${tenant_dir}/redisinsight-data"
    chown -R 1000:1000 "${tenant_dir}/redisinsight-data"
    
    log "Generating HTTPS certificate..."
    generate_nginx_cert "$tenant"
    
    log "Creating authentication..."
    create_htpasswd "$tenant" "$insight_user" "$insight_pass"
    
    log "Creating nginx configuration..."
    create_nginx_config "$tenant" "$insight_port" "$insight_port"
    
    create_docker_compose_with_insight "$tenant" "$PORT" "$PASSWORD" "$MAXMEMORY" "$DOCKER_LIMIT" "$insight_port"
    
    log "Starting containers..."
    cd "$tenant_dir"
    docker-compose up -d
    
    log "Waiting for containers to start..."
    sleep 3
    
    if docker ps --format '{{.Names}}' | grep -q "^nginx-${tenant}$"; then
        success "RedisInsight enabled for tenant: $tenant"
        echo ""
        echo "Access RedisInsight:"
        echo "  Public URL: https://${PUBLIC_IP}:${insight_port}"
        echo "  Internal URL: https://${INTERNAL_IP}:${insight_port}"
        echo ""
        echo "Login Credentials:"
        echo "  Username: ${insight_user}"
        echo "  Password: ${insight_pass}"
        echo ""
        echo "Redis Connection Details (for RedisInsight):"
        echo "  Host: redis-${tenant}"
        echo "  Port: 6379"
        echo "  Password: ${PASSWORD}"
        echo "  TLS: Enabled"
        echo ""
        success "The Redis database connection is automatically configured in RedisInsight!"
        echo "Simply log in with the credentials above and start working immediately."
        echo ""
        warn "Note: The HTTPS certificate is self-signed. Accept the security warning in your browser."
        echo ""
    else
        error "Failed to start RedisInsight container"
    fi
}

disable_redisinsight() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    if [[ -z "${INSIGHT_PORT:-}" ]] || [[ "${INSIGHT_PORT:-0}" == "0" ]]; then
        warn "RedisInsight is not enabled for tenant: $tenant"
        return 0
    fi
    
    log "Disabling RedisInsight for tenant: $tenant"
    
    docker rm -f "nginx-${tenant}" 2>/dev/null || true
    docker rm -f "redisinsight-${tenant}" 2>/dev/null || true
    
    sed -i '/^INSIGHT_PORT=/d' "${tenant_dir}/config.env"
    sed -i '/^INSIGHT_USER=/d' "${tenant_dir}/config.env"
    sed -i '/^INSIGHT_PASS=/d' "${tenant_dir}/config.env"
    
    create_docker_compose "$tenant" "$PORT" "$PASSWORD" "$MAXMEMORY" "$DOCKER_LIMIT"
    
    success "RedisInsight disabled for tenant: $tenant"
}

create_docker_compose_with_insight() {
    local tenant="$1"
    local port="$2"
    local password="$3"
    local maxmemory="${4:-256}"
    local docker_limit="${5:-512}"
    local insight_port="${6}"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    local bind_ip="${INTERNAL_IP}"
    if [[ "${bind_ip}" == "localhost" ]]; then
        bind_ip="127.0.0.1"
    fi
    
    local public_ip="${PUBLIC_IP}"
    if [[ "${public_ip}" == "localhost" ]]; then
        public_ip="127.0.0.1"
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

  redisinsight:
    image: redis/redisinsight:latest
    container_name: redisinsight-${tenant}
    restart: unless-stopped
    user: "1000:1000"
    volumes:
      - ./redisinsight-data:/data
      - ./certs:/certs:ro
    networks:
      - cachepilot-net
    depends_on:
      - redis
    environment:
      - RITRUSTEDORIGINS=https://${PUBLIC_IP}:${insight_port}
      - RI_REDIS_HOST=redis-${tenant}
      - RI_REDIS_PORT=6379
      - RI_REDIS_ALIAS=${tenant}
      - RI_REDIS_PASSWORD=${password}
      - RI_REDIS_TLS=true
      - RI_REDIS_TLS_CA_PATH=/certs/ca.crt
      - RI_REDIS_TLS_CERT_PATH=/certs/redis.crt
      - RI_REDIS_TLS_KEY_PATH=/certs/redis.key

  nginx:
    image: nginx:alpine
    container_name: nginx-${tenant}
    restart: unless-stopped
    ports:
      - "${public_ip}:${insight_port}:443"
      - "${bind_ip}:${insight_port}:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/.htpasswd:/etc/nginx/.htpasswd:ro
    networks:
      - cachepilot-net
    depends_on:
      - redisinsight

networks:
  cachepilot-net:
    external: true
EOF
}

show_redisinsight_status() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    echo ""
    echo "RedisInsight Status for: $tenant"
    echo "=========================================="
    
    if [[ -z "${INSIGHT_PORT:-}" ]] || [[ "${INSIGHT_PORT:-0}" == "0" ]]; then
        echo -e "Status: ${RED}DISABLED${NC}"
        echo ""
        echo "To enable: cachepilot insight-enable $tenant"
        return 0
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "^nginx-${tenant}$"; then
        echo -e "Status: ${GREEN}RUNNING${NC}"
        echo ""
        echo "Access URLs:"
        echo "  Public: https://${PUBLIC_IP}:${INSIGHT_PORT}"
        echo "  Internal: https://${INTERNAL_IP}:${INSIGHT_PORT}"
        echo ""
        echo "Login Credentials:"
        echo "  Username: ${INSIGHT_USER:-admin}"
        echo "  Password: ${INSIGHT_PASS:-<not set>}"
        echo ""
        echo "Redis Connection (for RedisInsight):"
        echo "  Host: redis-${tenant}"
        echo "  Port: 6379"
        echo "  Password: ${PASSWORD}"
        echo "  TLS: Enabled"
        echo "  CA Certificate: Available in container at /certs/ca.crt"
    else
        echo -e "Status: ${RED}STOPPED${NC}"
        echo "Port: ${INSIGHT_PORT}"
    fi
    
    echo ""
}
