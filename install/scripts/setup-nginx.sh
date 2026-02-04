#!/bin/bash
#
# CachePilot - nginx Setup Script
#
# Configures nginx as reverse proxy for API and frontend
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

wait_for_apt_lock() {
    local max_wait=300
    local waited=0
    local check_interval=5
    local shown_details=false
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        [ $waited -eq 0 ] && echo -e "${YELLOW}⏳${NC} Waiting for package manager..."
        
        if [ $waited -ge $max_wait ]; then
            echo -e "${RED}✗${NC} Timeout (${max_wait}s)"
            return 1
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
        [ $((waited % 30)) -eq 0 ] && echo "  Waiting... (${waited}s)"
    done
    
    [ $waited -gt 0 ] && echo -e "${GREEN}✓${NC} Lock released (${waited}s)"
    return 0
}

echo "Setting up nginx..."

BASE_DIR="/opt/cachepilot"
FRONTEND_DIST="$BASE_DIR/frontend/dist"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/redis-manager"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/redis-manager"

SERVER_NAME="${1:-}"
ENABLE_SSL="${2:-}"

if ! command -v nginx &> /dev/null; then
    wait_for_apt_lock || exit 1
    apt-get update -qq && apt-get install -y nginx
    echo -e "${GREEN}✓${NC} nginx installed"
fi

[ ! -d "$FRONTEND_DIST" ] && echo -e "${RED}✗${NC} Frontend not built" && exit 1

mkdir -p /var/www/html
chmod 755 /var/www/html

[ -z "$SERVER_NAME" ] && read -p "Server domain (default: localhost): " SERVER_NAME && SERVER_NAME=${SERVER_NAME:-localhost}
[ -z "$ENABLE_SSL" ] && read -p "Enable SSL? (y/N): " ENABLE_SSL && ENABLE_SSL=${ENABLE_SSL:-N}


cat > "$NGINX_SITE_AVAILABLE" << EOF
# CachePilot nginx Configuration

server {
    listen 80;
    server_name $SERVER_NAME;
    
    root $FRONTEND_DIST;
    index index.html;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' http://localhost:8000 https://localhost:8000;" always;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }
    
    location / {
        try_files \$uri \$uri/ /index.html;
        
        location = /index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            expires 0;
        }
    }
    
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Pass through API authentication headers
        proxy_set_header X-API-Key \$http_x_api_key;
        
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types text/plain text/css text/javascript application/javascript application/json application/xml application/xml+rss image/svg+xml;
    
    access_log /var/log/nginx/cachepilot-access.log;
    error_log /var/log/nginx/cachepilot-error.log;
}
EOF

[ -L "$NGINX_SITE_ENABLED" ] && rm "$NGINX_SITE_ENABLED"
ln -s "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"

nginx -t 2>&1 | grep -q "successful" || { echo -e "${RED}✗${NC} Invalid config"; nginx -t; exit 1; }

systemctl restart nginx
systemctl enable nginx
echo -e "${GREEN}✓${NC} nginx configured"
echo ""

if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    echo "Setting up SSL..."
    
    if ! command -v certbot &> /dev/null; then
        wait_for_apt_lock || { echo "Continuing without SSL..."; return 0; }
        apt-get update -qq && apt-get install -y certbot python3-certbot-nginx
    fi
    
    read -p "Email for Let's Encrypt (or Enter to skip): " LE_EMAIL
    
    if [ -z "$LE_EMAIL" ]; then
        read -p "Create self-signed certificate? (Y/n): " USE_SELFSIGNED
        if [[ "${USE_SELFSIGNED:-Y}" =~ ^[Yy]$ ]]; then
            CERT_DIR="/etc/ssl/certs"
            KEY_DIR="/etc/ssl/private"
            CERT_NAME="cachepilot-$SERVER_NAME"
            
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$KEY_DIR/$CERT_NAME.key" \
                -out "$CERT_DIR/$CERT_NAME.crt" \
                -subj "/C=DE/ST=State/L=City/O=CachePilot/CN=$SERVER_NAME" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                cat > "$NGINX_SITE_AVAILABLE" << 'EOF_NGINX'
# CachePilot nginx Configuration
# Generated: $(date)

# HTTP Server - Redirect to HTTPS
server {
    listen 80;
    server_name SERVER_NAME_PLACEHOLDER;
    
    return 301 https://$server_name$request_uri;
}

# HTTPS Server with Self-Signed Certificate
server {
    listen 443 ssl http2;
    server_name SERVER_NAME_PLACEHOLDER;
    
    # SSL Configuration - Self-Signed Certificate
    ssl_certificate CERT_DIR_PLACEHOLDER/CERT_NAME_PLACEHOLDER.crt;
    ssl_certificate_key KEY_DIR_PLACEHOLDER/CERT_NAME_PLACEHOLDER.key;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Frontend root
    root FRONTEND_DIST_PLACEHOLDER;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' http://localhost:8000 https://localhost:8000;" always;
    
    # Let's Encrypt ACME Challenge - Must be before SPA routing
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files $uri =404;
    }
    
    # Frontend - SPA routing
    location / {
        try_files $uri $uri/ /index.html;
        
        # Disable caching for index.html
        location = /index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            expires 0;
        }
    }
    
    # API Reverse Proxy
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass $http_upgrade;
        
        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts - Increased for long-running operations like tenant creation
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/xml
        application/xml+rss
        image/svg+xml;
    
    # Logs
    access_log /var/log/nginx/cachepilot-access.log;
    error_log /var/log/nginx/cachepilot-error.log;
}
EOF_NGINX
                
                # Replace placeholders
                sed -i "s|SERVER_NAME_PLACEHOLDER|$SERVER_NAME|g" "$NGINX_SITE_AVAILABLE"
                sed -i "s|CERT_DIR_PLACEHOLDER|$CERT_DIR|g" "$NGINX_SITE_AVAILABLE"
                sed -i "s|KEY_DIR_PLACEHOLDER|$KEY_DIR|g" "$NGINX_SITE_AVAILABLE"
                sed -i "s|CERT_NAME_PLACEHOLDER|$CERT_NAME|g" "$NGINX_SITE_AVAILABLE"
                sed -i "s|FRONTEND_DIST_PLACEHOLDER|$FRONTEND_DIST|g" "$NGINX_SITE_AVAILABLE"
                
                # Test and reload nginx
                if nginx -t 2>&1 | grep -q "successful"; then
                    systemctl reload nginx
                    echo -e "${GREEN}✓${NC} nginx reloaded with self-signed certificate"
                    echo ""
                    echo -e "${YELLOW}⚠${NC} Using self-signed certificate"
                    echo "  Certificate: $CERT_DIR/$CERT_NAME.crt"
                    echo "  Key: $KEY_DIR/$CERT_NAME.key"
                    echo ""
                    echo -e "${YELLOW}⚠${NC} Browser will show security warning for self-signed certificates"
                    echo "  You can replace with Let's Encrypt certificate later:"
                    echo "  certbot --nginx -d $SERVER_NAME --email your@email.com"
                    echo ""
                    echo -e "${GREEN}Frontend now available at: https://$SERVER_NAME/${NC}"
                    echo -e "${GREEN}API now available at: https://$SERVER_NAME/api/${NC}"
                else
                    echo -e "${RED}✗${NC} nginx configuration test failed"
                    nginx -t
                fi
            else
                echo -e "${RED}✗${NC} Failed to create self-signed certificate"
                echo "Continuing with HTTP only"
            fi
        else
            echo "Continuing with HTTP only"
            echo "You can setup SSL manually later:"
            echo "  certbot --nginx -d $SERVER_NAME --email your@email.com"
        fi
    elif [ -n "$LE_EMAIL" ]; then
        echo "Running certbot with email: $LE_EMAIL"
        echo "Using webroot mode to avoid nginx config conflicts..."
        
        # Use webroot mode instead of nginx mode to avoid conflicts with SPA routing
        if certbot certonly --webroot -w /var/www/html -d "$SERVER_NAME" --non-interactive --agree-tos --email "$LE_EMAIL" --deploy-hook "systemctl reload nginx"; then
            echo -e "${GREEN}✓${NC} SSL certificate obtained!"
            
            # Now manually configure nginx for SSL
            CERT_PATH="/etc/letsencrypt/live/$SERVER_NAME/fullchain.pem"
            KEY_PATH="/etc/letsencrypt/live/$SERVER_NAME/privkey.pem"
            
            cat > "$NGINX_SITE_AVAILABLE" << EOF
# CachePilot nginx Configuration
# Generated: $(date)
# SSL Certificate from Let's Encrypt

# HTTP Server - Redirect to HTTPS
server {
    listen 80;
    server_name $SERVER_NAME;
    
    # Let's Encrypt ACME Challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS Server with Let's Encrypt Certificate
server {
    listen 443 ssl http2;
    server_name $SERVER_NAME;
    
    # SSL Configuration - Let's Encrypt
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Frontend root
    root $FRONTEND_DIST;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' http://localhost:8000 https://localhost:8000;" always;
    
    # Frontend - SPA routing
    location / {
        try_files \$uri \$uri/ /index.html;
        
        # Disable caching for index.html
        location = /index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            expires 0;
        }
    }
    
    # API Reverse Proxy
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/xml
        application/xml+rss
        image/svg+xml;
    
    # Logs
    access_log /var/log/nginx/cachepilot-access.log;
    error_log /var/log/nginx/cachepilot-error.log;
}
EOF
            
            # Test and reload nginx
            if nginx -t 2>&1 | grep -q "successful"; then
                systemctl reload nginx
                echo -e "${GREEN}✓${NC} nginx configured with Let's Encrypt certificate"
                echo ""
                echo "Certificate details:"
                certbot certificates
                echo ""
                echo -e "${GREEN}Frontend now available at: https://$SERVER_NAME/${NC}"
                echo -e "${GREEN}API now available at: https://$SERVER_NAME/api/${NC}"
            else
                echo -e "${RED}✗${NC} nginx configuration test failed"
                nginx -t
            fi
        else
            echo -e "${YELLOW}⚠${NC} Let's Encrypt certificate failed."
            echo "Creating self-signed certificate as fallback..."
            echo ""
            
            # Create self-signed certificate
            CERT_DIR="/etc/ssl/certs"
            KEY_DIR="/etc/ssl/private"
            CERT_NAME="cachepilot-$SERVER_NAME"
            
            # Generate self-signed certificate (valid for 365 days)
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$KEY_DIR/$CERT_NAME.key" \
                -out "$CERT_DIR/$CERT_NAME.crt" \
                -subj "/C=DE/ST=State/L=City/O=CachePilot/CN=$SERVER_NAME" \
                2>/dev/null
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓${NC} Self-signed certificate created"
                
                # Replace the entire HTTP server block with HTTP redirect + HTTPS server
                cat > "$NGINX_SITE_AVAILABLE" << EOF
# CachePilot nginx Configuration
# Generated: $(date)

# HTTP Server - Redirect to HTTPS
server {
    listen 80;
    server_name $SERVER_NAME;
    
    return 301 https://\$server_name\$request_uri;
}

# HTTPS Server with Self-Signed Certificate
server {
    listen 443 ssl http2;
    server_name $SERVER_NAME;
    
    # SSL Configuration - Self-Signed Certificate
    ssl_certificate $CERT_DIR/$CERT_NAME.crt;
    ssl_certificate_key $KEY_DIR/$CERT_NAME.key;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Frontend root
    root $FRONTEND_DIST;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' http://localhost:8000 https://localhost:8000;" always;
    
    # Let's Encrypt ACME Challenge - Must be before SPA routing
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }
    
    # Frontend - SPA routing
    location / {
        try_files \$uri \$uri/ /index.html;
        
        # Disable caching for index.html
        location = /index.html {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            expires 0;
        }
    }
    
    # API Reverse Proxy
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts - Increased for long-running operations like tenant creation
        proxy_connect_timeout 120s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
    
    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/javascript
        application/javascript
        application/json
        application/xml
        application/xml+rss
        image/svg+xml;
    
    # Logs
    access_log /var/log/nginx/cachepilot-access.log;
    error_log /var/log/nginx/cachepilot-error.log;
}
EOF
                
                # Test and reload nginx
                if nginx -t 2>&1 | grep -q "successful"; then
                    systemctl reload nginx
                    echo -e "${GREEN}✓${NC} nginx reloaded with self-signed certificate"
                    echo ""
                    echo -e "${YELLOW}⚠${NC} Using self-signed certificate"
                    echo "  Certificate: $CERT_DIR/$CERT_NAME.crt"
                    echo "  Key: $KEY_DIR/$CERT_NAME.key"
                    echo ""
                    echo -e "${YELLOW}⚠${NC} Browser will show security warning for self-signed certificates"
                    echo "  You can replace with Let's Encrypt certificate later:"
                    echo "  certbot --nginx -d $SERVER_NAME"
                    echo ""
                    echo -e "${GREEN}Frontend now available at: https://$SERVER_NAME/${NC}"
                    echo -e "${GREEN}API now available at: https://$SERVER_NAME/api/${NC}"
                else
                    echo -e "${RED}✗${NC} nginx configuration test failed"
                    nginx -t
                fi
            else
                echo -e "${RED}✗${NC} Failed to create self-signed certificate"
                echo "You can setup SSL manually:"
                echo "  certbot --nginx -d $SERVER_NAME"
            fi
        fi
    else
        echo "No email provided. You can setup SSL manually:"
        echo "  certbot --nginx -d $SERVER_NAME"
    fi
    echo ""
else
    echo "Test the setup:"
    echo "  curl http://$SERVER_NAME/api/v1/health"
    echo "  Visit: http://$SERVER_NAME/"
    echo ""
fi
