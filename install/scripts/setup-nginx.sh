#!/bin/bash
#
# CachePilot - nginx Setup Script
#
# Configures nginx as reverse proxy for API and frontend
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.0-beta
#

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to wait for apt/dpkg lock to be released
wait_for_apt_lock() {
    local max_wait=300  # 5 minutes maximum wait time
    local waited=0
    local check_interval=5
    local shown_details=false
    
    # Only check for actual lock files, not just running processes
    # This is more accurate - unattended-upgrades may run but not hold locks
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        
        if [ $waited -eq 0 ]; then
            echo -e "${YELLOW}⏳${NC} Waiting for other package management processes to complete..."
            echo "  (This may be automatic system updates running in the background)"
        fi
        
        # Show details after 10 seconds
        if [ $waited -eq 10 ] && [ "$shown_details" = false ]; then
            echo ""
            echo "  Checking what's blocking..."
            
            # Check which locks are held
            if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
                echo "  • Lock file: /var/lib/dpkg/lock-frontend"
                fuser -v /var/lib/dpkg/lock-frontend 2>&1 | grep -v "USER" || true
            fi
            
            # Check for running processes
            local blocking_procs=""
            pgrep -x unattended-upgr >/dev/null 2>&1 && blocking_procs="${blocking_procs}unattended-upgrades "
            pgrep -x apt >/dev/null 2>&1 && blocking_procs="${blocking_procs}apt "
            pgrep -x apt-get >/dev/null 2>&1 && blocking_procs="${blocking_procs}apt-get "
            pgrep -x dpkg >/dev/null 2>&1 && blocking_procs="${blocking_procs}dpkg "
            
            if [ -n "$blocking_procs" ]; then
                echo "  • Blocking processes: $blocking_procs"
            fi
            echo ""
            shown_details=true
        fi
        
        if [ $waited -ge $max_wait ]; then
            echo -e "${RED}✗${NC} Timeout waiting for package management lock (waited ${max_wait}s)"
            echo ""
            echo "Blocking processes still active:"
            ps aux | grep -E 'apt|dpkg|unattended' | grep -v grep || echo "  (none visible)"
            echo ""
            echo "You can try one of these options:"
            echo "  1. Wait longer and run the script again"
            echo "  2. Kill the blocking process manually:"
            echo "     sudo killall apt apt-get dpkg unattended-upgr"
            echo "     sudo rm /var/lib/dpkg/lock-frontend"
            echo "     sudo rm /var/lib/dpkg/lock"
            echo "     sudo dpkg --configure -a"
            return 1
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
        
        # Show progress every 30 seconds
        if [ $((waited % 30)) -eq 0 ]; then
            echo "  Still waiting... (${waited}s elapsed)"
        fi
    done
    
    if [ $waited -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Package management lock released (waited ${waited}s)"
    fi
    
    return 0
}

echo "Setting up nginx reverse proxy..."

# Base directory
BASE_DIR="/opt/cachepilot"
FRONTEND_DIST="$BASE_DIR/frontend/dist"
NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/redis-manager"
NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/redis-manager"

# Get parameters (can be passed from install script or prompted)
SERVER_NAME="${1:-}"
ENABLE_SSL="${2:-}"

# Check if nginx is installed
if ! command -v nginx &> /dev/null; then
    echo -e "${YELLOW}nginx not found. Installing...${NC}"
    
    # Wait for any existing apt/dpkg processes to complete
    if ! wait_for_apt_lock; then
        echo -e "${RED}✗${NC} Cannot proceed with nginx installation"
        exit 1
    fi
    
    apt-get update -qq
    apt-get install -y nginx
    echo -e "${GREEN}✓${NC} nginx installed"
else
    echo -e "${GREEN}✓${NC} nginx already installed"
fi

# Check if frontend is built
if [ ! -d "$FRONTEND_DIST" ]; then
    echo -e "${RED}✗${NC} Frontend not built. Please run setup-frontend.sh first."
    exit 1
fi

echo -e "${GREEN}✓${NC} Frontend dist found"

# Ensure /var/www/html exists for ACME challenges (create early, before nginx config)
if [ ! -d "/var/www/html" ]; then
    mkdir -p /var/www/html
    chmod 755 /var/www/html
    echo -e "${GREEN}✓${NC} Created /var/www/html for ACME challenges"
fi

# Get server configuration if not provided
if [ -z "$SERVER_NAME" ]; then
    read -p "Enter server domain (or press Enter for localhost): " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-localhost}
fi

if [ -z "$ENABLE_SSL" ]; then
    read -p "Enable SSL/HTTPS? (y/N): " ENABLE_SSL
    ENABLE_SSL=${ENABLE_SSL:-N}
fi

# Create nginx configuration
echo "Creating nginx configuration..."

cat > "$NGINX_SITE_AVAILABLE" << EOF
# CachePilot nginx Configuration
# Generated: $(date)

server {
    listen 80;
    server_name $SERVER_NAME;
    
    # Frontend root
    root $FRONTEND_DIST;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
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

# No SSL placeholder needed - will be configured by certbot

echo -e "${GREEN}✓${NC} nginx configuration created"

# Enable site
if [ -L "$NGINX_SITE_ENABLED" ]; then
    rm "$NGINX_SITE_ENABLED"
fi
ln -s "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
echo -e "${GREEN}✓${NC} Site enabled"

# Test nginx configuration
if nginx -t 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✓${NC} nginx configuration valid"
else
    echo -e "${RED}✗${NC} nginx configuration invalid"
    nginx -t
    exit 1
fi

# Restart nginx
systemctl restart nginx
echo -e "${GREEN}✓${NC} nginx restarted"

# Enable nginx on boot
systemctl enable nginx
echo -e "${GREEN}✓${NC} nginx enabled on boot"

echo ""
echo "========================================"
echo -e "${GREEN}nginx Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Server: http://$SERVER_NAME"
echo "  Frontend: http://$SERVER_NAME/"
echo "  API: http://$SERVER_NAME/api/"
echo ""
echo "nginx Configuration: $NGINX_SITE_AVAILABLE"
echo ""

# Setup Let's Encrypt if SSL enabled
if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    echo "Setting up Let's Encrypt SSL..."
    echo ""
    
    # Ensure /var/www/html exists for ACME challenges
    if [ ! -d "/var/www/html" ]; then
        mkdir -p /var/www/html
        chmod 755 /var/www/html
        echo -e "${GREEN}✓${NC} Created /var/www/html for ACME challenges"
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        echo "Installing certbot..."
        
        # Wait for any existing apt/dpkg processes to complete
        if ! wait_for_apt_lock; then
            echo -e "${RED}✗${NC} Cannot proceed with certbot installation"
            echo "You can install certbot manually later:"
            echo "  sudo apt-get update && sudo apt-get install -y certbot python3-certbot-nginx"
            echo ""
            echo "Continuing with HTTP-only configuration..."
            return 0
        fi
        
        apt-get update -qq
        apt-get install -y certbot python3-certbot-nginx
        echo -e "${GREEN}✓${NC} certbot installed"
    else
        echo -e "${GREEN}✓${NC} certbot already installed"
    fi
    
    echo ""
    echo "Obtaining SSL certificate for $SERVER_NAME..."
    echo ""
    
    # Run certbot
    read -p "Enter email address for Let's Encrypt notifications (or press Enter to skip): " LE_EMAIL
    
    if [ -z "$LE_EMAIL" ]; then
        echo ""
        echo -e "${YELLOW}⚠${NC} No email provided - Let's Encrypt requires a valid email address"
        echo ""
        read -p "Create self-signed certificate instead? (Y/n): " USE_SELFSIGNED
        USE_SELFSIGNED=${USE_SELFSIGNED:-Y}
        
        if [[ "$USE_SELFSIGNED" =~ ^[Yy]$ ]]; then
            echo "Creating self-signed certificate..."
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
        if certbot certonly --webroot -w /var/www/html -d "$SERVER_NAME" --non-interactive --agree-tos --email "$LE_EMAIL"; then
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
