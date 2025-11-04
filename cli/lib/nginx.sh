#!/usr/bin/env bash
#
# CachePilot - Nginx Proxy Configuration Library
#
# Manages Nginx reverse proxy configurations for RedisInsight access with
# HTTPS and basic authentication.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

create_nginx_config() {
    local tenant="$1"
    local insight_port="$2"
    local nginx_port="$3"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    mkdir -p "${tenant_dir}/nginx"
    
    cat > "${tenant_dir}/nginx/nginx.conf" << EOF
events {
    worker_connections 1024;
}

http {
    upstream redisinsight {
        server redisinsight-${tenant}:5540;
    }

    server {
        listen 443 ssl;
        server_name _;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        auth_basic "RedisInsight - ${tenant}";
        auth_basic_user_file /etc/nginx/.htpasswd;

        location / {
            proxy_pass http://redisinsight;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 86400;
        }
    }
}
EOF
}

generate_nginx_cert() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    mkdir -p "${tenant_dir}/nginx/ssl"
    
    openssl req -x509 -nodes -days 1095 -newkey rsa:2048 \
        -keyout "${tenant_dir}/nginx/ssl/key.pem" \
        -out "${tenant_dir}/nginx/ssl/cert.pem" \
        -subj "/C=DE/ST=Bavaria/L=Munich/O=MSRV Digital/CN=redisinsight-${tenant}" \
        2>/dev/null
}

create_htpasswd() {
    local tenant="$1"
    local username="$2"
    local password="$3"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    mkdir -p "${tenant_dir}/nginx"
    
    echo "${username}:$(openssl passwd -apr1 ${password})" > "${tenant_dir}/nginx/.htpasswd"
}
