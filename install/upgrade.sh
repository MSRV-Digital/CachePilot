#!/usr/bin/env bash
#
# CachePilot - Upgrade Script
#
# Upgrades CachePilot to a new version while preserving data
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "CachePilot v2.1.2-Beta Upgrade"
echo "========================================"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

INSTALL_DIR="/opt/cachepilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/tmp/cachepilot-backup-$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}CachePilot not installed${NC}"
    exit 1
fi

echo "Directory: $INSTALL_DIR"
echo ""

# Check if Git-based installation
IS_GIT_BASED=false
if [ -d "$INSTALL_DIR/.git" ]; then
    IS_GIT_BASED=true
    cd "$INSTALL_DIR"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    echo "Git-based installation detected"
    echo "Branch: $CURRENT_BRANCH"
    echo "Current commit: $CURRENT_COMMIT"
else
    echo -e "${YELLOW}⚠${NC} Legacy installation detected (not Git-based)"
    echo "Consider converting to Git-based: sudo bash $INSTALL_DIR/install/scripts/git-setup.sh convert"
    CURRENT_VERSION="unknown"
    if [ -f "$INSTALL_DIR/CHANGELOG.md" ]; then
        CURRENT_VERSION=$(grep -m1 "^## " "$INSTALL_DIR/CHANGELOG.md" | sed 's/## \[\(.*\)\].*/\1/' || echo "unknown")
    fi
    echo "Current version: $CURRENT_VERSION"
fi
echo ""

echo "=================================================="
echo -e "${YELLOW}⚠️  UPGRADE WARNING${NC}"
echo "=================================================="
echo ""
echo "This will:"
echo "  • Stop/restart cachepilot-api (~10-30s downtime)"
echo "  • Update application files"
echo "  • Update Python dependencies"
echo "  • Rebuild frontend (if installed)"
echo "  • Create backup: $BACKUP_DIR"
echo "  • Preserve all tenant data and API keys"
echo ""
read -p "Type 'yes' to proceed: " PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo "Upgrade cancelled."
    exit 0
fi

echo ""

echo -e "${BLUE}[1/11]${NC} Creating backup..."

if [ "$IS_GIT_BASED" = true ]; then
    # Git handles backups automatically, just note current state
    cd "$INSTALL_DIR"
    git stash push -m "Pre-upgrade backup $(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Current state saved in Git stash"
else
    # Legacy backup for non-Git installations
    mkdir -p "$BACKUP_DIR"
    [ -d "$INSTALL_DIR/config" ] && cp -r "$INSTALL_DIR/config" "$BACKUP_DIR/"
    [ -f "$INSTALL_DIR/cachepilot" ] && cp "$INSTALL_DIR/cachepilot" "$BACKUP_DIR/cachepilot.old" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Backup created: $BACKUP_DIR"
fi

HAS_OLD_DATA=false
[ -d "$INSTALL_DIR/data" ] && HAS_OLD_DATA=true
echo ""

echo -e "${BLUE}[2/11]${NC} Stopping services..."

API_WAS_RUNNING=false
if systemctl is-active --quiet cachepilot-api.service 2>/dev/null; then
    systemctl stop cachepilot-api.service
    API_WAS_RUNNING=true
fi
echo -e "${GREEN}✓${NC} Services stopped"
echo ""

echo -e "${BLUE}[3/11]${NC} Checking dependencies..."
[ -x "$INSTALL_DIR/install/scripts/install-deps.sh" ] && bash "$INSTALL_DIR/install/scripts/install-deps.sh"
[ -x "$INSTALL_DIR/install/scripts/check-deps.sh" ] && bash "$INSTALL_DIR/install/scripts/check-deps.sh"
echo ""

echo -e "${BLUE}[4/11]${NC} Checking configuration..."
[ ! -d "/etc/cachepilot" ] && echo "Will create /etc/cachepilot during update"
echo ""

echo -e "${BLUE}[4.5/11]${NC} Migrating configuration..."

# Check if new port range fields exist in system.yaml
NEEDS_PORT_MIGRATION=false
if [ -f "/etc/cachepilot/system.yaml" ]; then
    if ! grep -q "redis_tls_port_end:" /etc/cachepilot/system.yaml 2>/dev/null; then
        NEEDS_PORT_MIGRATION=true
    fi
fi

# Check if persistence_mode exists in system.yaml
NEEDS_PERSISTENCE_CONFIG=false
if [ -f "/etc/cachepilot/system.yaml" ]; then
    if ! grep -q "persistence_mode:" /etc/cachepilot/system.yaml 2>/dev/null; then
        NEEDS_PERSISTENCE_CONFIG=true
    fi
fi

# Check if server_url field exists in system.yaml
NEEDS_SERVER_URL_MIGRATION=false
if [ -f "/etc/cachepilot/system.yaml" ]; then
    if ! grep -q "server_url:" /etc/cachepilot/system.yaml 2>/dev/null; then
        NEEDS_SERVER_URL_MIGRATION=true
    fi
fi

if [ "$NEEDS_SERVER_URL_MIGRATION" = true ]; then
    echo "Adding server_url field to system.yaml..."

    # Try to detect domain from CORS origins in api.yaml
    DETECTED_DOMAIN=""
    if [ -f "/etc/cachepilot/api.yaml" ]; then
        DETECTED_DOMAIN=$(grep -oP 'https?://\K[^/:]+' /etc/cachepilot/api.yaml 2>/dev/null | grep -v 'localhost' | head -1 || true)
    fi

    # Add server_url field after public_ip line
    sed -i "/public_ip:/a\  server_url: \"${DETECTED_DOMAIN}\"               # Server domain for public URLs (empty = fallback to public_ip)" /etc/cachepilot/system.yaml

    if [ -n "$DETECTED_DOMAIN" ]; then
        echo -e "${GREEN}✓${NC} server_url added: $DETECTED_DOMAIN (auto-detected from api.yaml)"
    else
        echo -e "${GREEN}✓${NC} server_url field added (empty - will fallback to public_ip)"
    fi
else
    echo "server_url field already present in system.yaml"
fi
echo ""

if [ "$NEEDS_PORT_MIGRATION" = true ]; then
    echo "Updating port range configuration for dual-mode support..."
    
    # Get current values
    CURRENT_START=$(grep "redis_port_start:" /etc/cachepilot/system.yaml | awk '{print $2}' || echo "7300")
    CURRENT_END=$(grep "redis_port_end:" /etc/cachepilot/system.yaml | awk '{print $2}' || echo "7399")
    
    # Calculate new ranges for 300 dual-mode tenants
    NEW_END=7899  # Expanded from 7399
    TLS_END=7599  # Split point
    PLAIN_START=7600  # Start of Plain-Text range
    
    echo "Current range: $CURRENT_START-$CURRENT_END"
    echo "New range:     $CURRENT_START-$NEW_END"
    
    # Update existing redis_port_end field
    sed -i "s/redis_port_end: .*/redis_port_end: $NEW_END/" /etc/cachepilot/system.yaml
    
    # Add new fields if they don't exist
    if ! grep -q "redis_tls_port_end:" /etc/cachepilot/system.yaml 2>/dev/null; then
        # Add after redis_port_end line
        sed -i "/redis_port_end:/a\  redis_tls_port_end: $TLS_END" /etc/cachepilot/system.yaml
    fi
    
    if ! grep -q "redis_plain_port_start:" /etc/cachepilot/system.yaml 2>/dev/null; then
        # Add after redis_tls_port_end line
        sed -i "/redis_tls_port_end:/a\  redis_plain_port_start: $PLAIN_START" /etc/cachepilot/system.yaml
    fi
    
    # Add default security_mode if not present
    if ! grep -q "security_mode:" /etc/cachepilot/system.yaml 2>/dev/null; then
        sed -i "/defaults:/a\  \n  # Security Mode (v2.2+)\n  # Default security mode for new tenants\n  # Options: tls-only (recommended), dual-mode, plain-only\n  security_mode: tls-only" /etc/cachepilot/system.yaml
    fi
    
    echo -e "${GREEN}✓${NC} Port ranges migrated:"
    echo "    TLS Range:        $CURRENT_START-$TLS_END (300 ports)"
    echo "    Plain-Text Range: $PLAIN_START-$NEW_END (300 ports)"
    echo "    Total capacity:   300 dual-mode tenants"
    
    echo ""
    echo -e "${YELLOW}⚠️  WICHTIG:${NC} Port-Range wurde erweitert ($CURRENT_START-$NEW_END)"
    echo "Falls Firewall aktiv, Regeln prüfen:"
    echo "  sudo ufw allow $CURRENT_START:$NEW_END/tcp"
    echo "  # oder für specific network:"
    echo "  sudo iptables -A INPUT -p tcp --dport $CURRENT_START:$NEW_END -s <trusted-network> -j ACCEPT"
    echo ""
else
    echo "Port configuration already up-to-date"
fi
echo ""

echo -e "${BLUE}[5/11]${NC} Updating files..."

if [ "$IS_GIT_BASED" = true ]; then
    # Git Pull Update
    cd "$INSTALL_DIR"
    
    echo "Fetching updates from Git..."
    git fetch origin
    
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "Pulling updates for branch: $CURRENT_BRANCH"
    
    if git pull origin "$CURRENT_BRANCH"; then
        echo -e "${GREEN}✓${NC} Git pull successful"
        NEW_COMMIT=$(git rev-parse --short HEAD)
        echo "Updated to commit: $NEW_COMMIT"
        
        # Show what changed
        echo ""
        echo "Recent changes:"
        git log --oneline -5
    else
        echo -e "${RED}✗${NC} Git pull failed"
        echo "You may have local changes. Run: git status"
        exit 1
    fi
    
    # Update configuration files if they don't exist
    mkdir -p /etc/cachepilot
    [ ! -f "/etc/cachepilot/system.yaml" ] && [ -f "$INSTALL_DIR/config/system.yaml" ] && cp "$INSTALL_DIR/config/system.yaml" /etc/cachepilot/
    [ ! -f "/etc/cachepilot/api.yaml" ] && [ -f "$INSTALL_DIR/config/api.yaml" ] && cp "$INSTALL_DIR/config/api.yaml" /etc/cachepilot/
    [ ! -f "/etc/cachepilot/frontend.yaml" ] && [ -f "$INSTALL_DIR/config/frontend.yaml" ] && cp "$INSTALL_DIR/config/frontend.yaml" /etc/cachepilot/
else
    # Legacy file copy method
    echo -e "${YELLOW}⚠${NC} Using legacy update method (copying files)"
    
    [ -d "$SCRIPT_DIR/cli" ] && cp -r "$SCRIPT_DIR/cli"/* "$INSTALL_DIR/cli/" 2>/dev/null || true
    [ -d "$SCRIPT_DIR/api" ] && cp -r "$SCRIPT_DIR/api"/* "$INSTALL_DIR/api/" 2>/dev/null || true
    [ -d "$SCRIPT_DIR/install" ] && cp -r "$SCRIPT_DIR/install"/* "$INSTALL_DIR/install/" 2>/dev/null || true
    [ -d "$SCRIPT_DIR/scripts" ] && cp -r "$SCRIPT_DIR/scripts"/* "$INSTALL_DIR/scripts/" 2>/dev/null || true
    [ -d "$SCRIPT_DIR/docs" ] && cp -r "$SCRIPT_DIR/docs"/* "$INSTALL_DIR/docs/" 2>/dev/null || true
    
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/CHANGELOG.md" "$INSTALL_DIR/" 2>/dev/null || true
    
    mkdir -p /etc/cachepilot
    [ ! -f "/etc/cachepilot/system.yaml" ] && [ -f "$SCRIPT_DIR/config/system.yaml" ] && cp "$SCRIPT_DIR/config/system.yaml" /etc/cachepilot/
    [ ! -f "/etc/cachepilot/api.yaml" ] && [ -f "$SCRIPT_DIR/config/api.yaml" ] && cp "$SCRIPT_DIR/config/api.yaml" /etc/cachepilot/
    [ ! -f "/etc/cachepilot/frontend.yaml" ] && [ -f "$SCRIPT_DIR/config/frontend.yaml" ] && cp "$SCRIPT_DIR/config/frontend.yaml" /etc/cachepilot/
    
    echo -e "${GREEN}✓${NC} Files copied"
fi

# Ensure permissions are correct
chmod +x "$INSTALL_DIR/cli/cachepilot" "$INSTALL_DIR"/cli/lib/*.sh "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/install/scripts/*.sh 2>/dev/null || true
echo -e "${GREEN}✓${NC} Permissions updated"
echo ""

echo -e "${BLUE}[6/11]${NC} Updating Python dependencies..."

VENV_PATH=""
[ -d "$INSTALL_DIR/venv" ] && VENV_PATH="$INSTALL_DIR/venv"
[ -d "$INSTALL_DIR/api/venv" ] && VENV_PATH="$INSTALL_DIR/api/venv"

if [ -n "$VENV_PATH" ]; then
    if [ ! -f "$VENV_PATH/bin/pip" ]; then
        rm -rf "$VENV_PATH"
        python3 -m venv "$VENV_PATH"
    fi
    
    if [ -f "$VENV_PATH/bin/pip" ]; then
        "$VENV_PATH/bin/pip" install --upgrade pip --quiet
        "$VENV_PATH/bin/pip" install -r "$INSTALL_DIR/api/requirements.txt" --quiet
        echo -e "${GREEN}✓${NC} Dependencies updated"
    fi
fi
echo ""

echo -e "${BLUE}[7/11]${NC} Updating system services..."

[ -f "$INSTALL_DIR/install/systemd/cachepilot-api.service" ] && cp "$INSTALL_DIR/install/systemd/cachepilot-api.service" /etc/systemd/system/ && systemctl daemon-reload
[ -x "$INSTALL_DIR/install/scripts/setup-logrotate.sh" ] && bash "$INSTALL_DIR/install/scripts/setup-logrotate.sh"
[ -x "$INSTALL_DIR/install/scripts/setup-cron.sh" ] && bash "$INSTALL_DIR/install/scripts/setup-cron.sh"
echo -e "${GREEN}✓${NC} Services updated"
echo ""

echo -e "${BLUE}[8/11]${NC} Checking server configuration..."

# Check for network configuration
NEEDS_NETWORK_CONFIG=false
if [ -f "/etc/cachepilot/system.yaml" ]; then
    CURRENT_INTERNAL_IP=$(grep "internal_ip:" /etc/cachepilot/system.yaml | awk '{print $2}')
    if [[ "$CURRENT_INTERNAL_IP" == "localhost" ]] || [[ "$CURRENT_INTERNAL_IP" == "127.0.0.1" ]]; then
        NEEDS_NETWORK_CONFIG=true
    fi
fi

if [ "$NEEDS_NETWORK_CONFIG" = true ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Netzwerk-Konfiguration prüfen${NC}"
    echo "Aktuelle Internal IP: $CURRENT_INTERNAL_IP"
    echo ""
    echo "WICHTIG: Für Netzwerk-Zugriff sollte die interne Server-IP konfiguriert sein."
    echo "  • Beispiele: 10.0.0.5, 192.168.1.100, 172.16.0.10"
    echo "  • Für alle Interfaces: 0.0.0.0"
    echo ""
    read -p "Internal IP aktualisieren? (y/N): " UPDATE_INTERNAL_IP
    if [[ "$UPDATE_INTERNAL_IP" =~ ^[Yy]$ ]]; then
        read -p "Neue Internal IP: " NEW_INTERNAL_IP
        if [[ -n "$NEW_INTERNAL_IP" ]] && [[ "$NEW_INTERNAL_IP" != "$CURRENT_INTERNAL_IP" ]]; then
            sed -i "s/internal_ip: .*/internal_ip: $NEW_INTERNAL_IP/g" /etc/cachepilot/system.yaml
            echo -e "${GREEN}✓${NC} Internal IP aktualisiert: $NEW_INTERNAL_IP"
            echo -e "${YELLOW}Hinweis: Bestehende Tenants müssen neu gestartet werden${NC}"
        fi
    fi
fi

NEEDS_SERVER_CONFIG=false
[ -f "/etc/cachepilot/frontend.yaml" ] && grep -q "url: http://localhost" "/etc/cachepilot/frontend.yaml" && NEEDS_SERVER_CONFIG=true

if [ "$NEEDS_SERVER_CONFIG" = true ]; then
    read -p "Update server URL? (y/N): " UPDATE_SERVER_URL
    if [[ "$UPDATE_SERVER_URL" =~ ^[Yy]$ ]]; then
        read -p "Server domain/IP (default: localhost): " SERVER_DOMAIN
        SERVER_DOMAIN=${SERVER_DOMAIN:-localhost}
        read -p "Use SSL/HTTPS? (y/N): " USE_SSL
        USE_SSL=${USE_SSL:-N}
        
        [[ "$USE_SSL" =~ ^[Yy]$ ]] && SERVER_URL="https://$SERVER_DOMAIN" || SERVER_URL="http://$SERVER_DOMAIN"
        
        sed -i "s|url: .*|url: $SERVER_URL|g" /etc/cachepilot/frontend.yaml 2>/dev/null || true
        sed -i "s|http://.*|$SERVER_URL|g" /etc/cachepilot/api.yaml 2>/dev/null || true
        sed -i "s|http://localhost:3000|$SERVER_URL|g" /etc/cachepilot/api.yaml 2>/dev/null || true
        
        export SERVER_DOMAIN SERVER_URL USE_SSL
    fi
fi
echo ""

echo -e "${BLUE}[9/11]${NC} Updating frontend..."

FRONTEND_UPDATED=false
if [ -d "$INSTALL_DIR/frontend" ]; then
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        if [ -d "$INSTALL_DIR/frontend/node_modules" ] || [ -d "$INSTALL_DIR/frontend/dist" ]; then
            [ -x "$INSTALL_DIR/install/scripts/setup-frontend.sh" ] && bash "$INSTALL_DIR/install/scripts/setup-frontend.sh" && FRONTEND_UPDATED=true
        fi
    fi
fi
echo ""

echo -e "${BLUE}[9.5/11]${NC} Fixing certbot renewal hook..."
# Ensure certbot reloads nginx after certificate renewal (fix for expired cert bug)
if [ -d "/etc/letsencrypt/renewal" ]; then
    HOOK_FIXED=0
    for renewal_conf in /etc/letsencrypt/renewal/*.conf; do
        [ -f "$renewal_conf" ] || continue
        if ! grep -q "post_hook\s*=\s*systemctl reload nginx" "$renewal_conf" 2>/dev/null; then
            # Add post_hook under [renewalparams] section
            if grep -q "\[renewalparams\]" "$renewal_conf"; then
                sed -i '/\[renewalparams\]/a post_hook = systemctl reload nginx' "$renewal_conf"
                ((HOOK_FIXED++))
            fi
        fi
    done
    if [ $HOOK_FIXED -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Added nginx reload hook to $HOOK_FIXED certbot renewal config(s)"
    else
        echo "Certbot renewal hooks already configured"
    fi
else
    echo "No certbot renewal configs found, skipping"
fi
echo ""

echo -e "${BLUE}[10/11]${NC} Updating nginx..."
if [ "$FRONTEND_UPDATED" = true ] && [ -x "$INSTALL_DIR/install/scripts/setup-nginx.sh" ] && command -v nginx &> /dev/null && [ -f "/etc/nginx/sites-available/redis-manager" ]; then
    read -p "Update nginx? (Y/n): " UPDATE_NGINX
    if [[ "${UPDATE_NGINX:-Y}" =~ ^[Yy]$ ]]; then
        [ -n "${SERVER_DOMAIN:-}" ] && bash "$INSTALL_DIR/install/scripts/setup-nginx.sh" "$SERVER_DOMAIN" "${USE_SSL:-N}" || bash "$INSTALL_DIR/install/scripts/setup-nginx.sh"
    fi
fi
echo ""

echo -e "${BLUE}[11/11]${NC} Fixing TLS certificate permissions..."

# Check for tenants and fix ca.crt permissions
FIXED_COUNT=0
if [ -d "/var/cachepilot/tenants" ]; then
    for tenant_dir in /var/cachepilot/tenants/*; do
        if [ -d "$tenant_dir" ]; then
            tenant=$(basename "$tenant_dir")
            # Copy and fix ca.crt permissions
            if [ -f "/var/cachepilot/ca/ca.crt" ] && [ -d "$tenant_dir/certs" ]; then
                cp /var/cachepilot/ca/ca.crt "$tenant_dir/certs/ca.crt" 2>/dev/null
                chmod 644 "$tenant_dir/certs/ca.crt" 2>/dev/null
                ((FIXED_COUNT++))
            fi
        fi
    done
    
    if [ $FIXED_COUNT -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Fixed TLS certificates for $FIXED_COUNT tenant(s)"
    else
        echo "No tenants found or certificates already correct"
    fi
elif [ -d "$INSTALL_DIR/data/tenants" ]; then
    # Legacy directory structure
    for tenant_dir in "$INSTALL_DIR/data/tenants"/*; do
        if [ -d "$tenant_dir" ]; then
            tenant=$(basename "$tenant_dir")
            if [ -f "$INSTALL_DIR/data/ca/ca.crt" ] && [ -d "$tenant_dir/certs" ]; then
                cp "$INSTALL_DIR/data/ca/ca.crt" "$tenant_dir/certs/ca.crt" 2>/dev/null
                chmod 644 "$tenant_dir/certs/ca.crt" 2>/dev/null
                ((FIXED_COUNT++))
            fi
        fi
    done
    
    if [ $FIXED_COUNT -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Fixed TLS certificates for $FIXED_COUNT tenant(s)"
    else
        echo "No tenants found or certificates already correct"
    fi
else
    echo "No tenant directory found, skipping"
fi
echo ""

echo -e "${BLUE}[11.5/11]${NC} Migrating tenants to new config format..."

# Migrate tenant config.env files to add PERSISTENCE_MODE
TENANTS_DIR="/var/cachepilot/tenants"
if [ ! -d "$TENANTS_DIR" ] && [ -d "$INSTALL_DIR/data/tenants" ]; then
    TENANTS_DIR="$INSTALL_DIR/data/tenants"
fi

if [ -d "$TENANTS_DIR" ]; then
    MIGRATED_COUNT=0
    for tenant_dir in "$TENANTS_DIR"/*; do
        if [ -d "$tenant_dir" ] && [ -f "$tenant_dir/config.env" ]; then
            tenant=$(basename "$tenant_dir")
            
            # Check if PERSISTENCE_MODE already exists
            if ! grep -q "^PERSISTENCE_MODE=" "$tenant_dir/config.env" 2>/dev/null; then
                # Add PERSISTENCE_MODE=persistent to maintain current behavior
                sed -i '/^SECURITY_MODE=/a PERSISTENCE_MODE=persistent' "$tenant_dir/config.env"
                ((MIGRATED_COUNT++))
            fi
        fi
    done
    
    if [ $MIGRATED_COUNT -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Migrated $MIGRATED_COUNT tenant(s) to include PERSISTENCE_MODE"
        echo "    (All existing tenants set to 'persistent' to maintain current behavior)"
    else
        echo "All tenants already have PERSISTENCE_MODE configured"
    fi
fi

if [ -x "$INSTALL_DIR/install/scripts/migrate-tenants-dual-mode.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/migrate-tenants-dual-mode.sh"
else
    echo "Dual-mode migration script not found, skipping"
fi
echo ""

# Restart API service (no separate step number - part of verification)
if [ -n "$VENV_PATH" ]; then
    echo "Restarting API service..."
    
    systemctl start cachepilot-api.service
    sleep 2
    
    if systemctl is-active --quiet cachepilot-api.service; then
        echo -e "${GREEN}✓${NC} API service started successfully"
    else
        echo -e "${RED}✗${NC} API service failed to start"
        echo "Check logs: journalctl -u cachepilot-api.service -n 50"
        echo ""
        echo "You can restore from backup:"
        echo "  $BACKUP_DIR"
    fi
else
    echo "API not installed (no virtual environment found), skipping service start"
fi

echo ""

# Final verification
echo "Running final verification..."

# Verify cachepilot command
if command -v cachepilot &> /dev/null; then
    echo -e "${GREEN}✓${NC} cachepilot command available"
else
    echo -e "${RED}✗${NC} cachepilot command not found"
fi

# Verify configuration
if [ -f "/etc/cachepilot/system.yaml" ]; then
    echo -e "${GREEN}✓${NC} System configuration exists"
fi

# Check directory structure
if [ -d "/var/cachepilot" ] || [ -d "/var/log/cachepilot" ]; then
    echo -e "${GREEN}✓${NC} FHS-compliant directory structure in use"
fi

echo ""
echo "========================================"
echo -e "${GREEN}✓ Upgrade Complete${NC}"
echo "========================================"
echo ""
echo "Verify:"
echo "  cachepilot --version"
echo "  cachepilot list"
echo ""

if [ "$API_WAS_RUNNING" = true ]; then
echo "API: systemctl status cachepilot-api"
fi

if [ "$FRONTEND_UPDATED" = true ]; then
echo "Frontend: Updated at $INSTALL_DIR/frontend/dist/"
fi

echo ""
if [ "$IS_GIT_BASED" = true ]; then
    echo "Git Status: git log --oneline -5"
    echo "Rollback: git reset --hard <commit>"
    echo "Stashed changes: git stash list"
else
    echo "Backup: $BACKUP_DIR"
    echo "Remove after verification: rm -rf $BACKUP_DIR"
fi
echo ""
