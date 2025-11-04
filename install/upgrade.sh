#!/usr/bin/env bash
#
# CachePilot - Upgrade Script
#
# Upgrades CachePilot to a new version while preserving data
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.0-beta
# License: MIT
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "CachePilot Upgrade"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

INSTALL_DIR="/opt/cachepilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/tmp/cachepilot-backup-$(date +%Y%m%d-%H%M%S)"

# Check if CachePilot is installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}CachePilot is not installed at $INSTALL_DIR${NC}"
    echo "Please run install.sh to perform a fresh installation."
    exit 1
fi

echo "Installation directory: $INSTALL_DIR"
echo "Upgrade source: $SCRIPT_DIR"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Detect current version
CURRENT_VERSION="unknown"
if [ -f "$INSTALL_DIR/CHANGELOG.md" ]; then
    CURRENT_VERSION=$(grep -m1 "^## " "$INSTALL_DIR/CHANGELOG.md" | sed 's/## \[\(.*\)\].*/\1/' || echo "unknown")
fi

echo "Current version: $CURRENT_VERSION"
echo ""

# ================================================
# SYSTEM UPGRADE WARNING
# ================================================
echo "=================================================="
echo -e "${YELLOW}⚠️  SYSTEM UPGRADE WARNING ⚠️${NC}"
echo "=================================================="
echo ""
echo -e "${RED}This upgrade will affect your running system:${NC}"
echo ""
echo "  🔄 Services Affected:"
echo "     • cachepilot-api will be stopped and restarted"
echo "     • nginx will be reloaded (if configured)"
echo "     • All running tenants remain unaffected"
echo ""
echo "  📦 System Changes:"
echo "     • Application files will be updated"
echo "     • Python dependencies will be updated"
echo "     • Frontend will be rebuilt (if Node.js available)"
echo "     • Configuration files will be updated"
echo ""
echo "  💾 Data Safety:"
echo "     • Backup will be created: $BACKUP_DIR"
echo "     • All tenant data will be preserved"
echo "     • Existing API keys will be preserved"
echo ""
echo "  ⏱️  Downtime:"
echo "     • API: ~10-30 seconds"
echo "     • Frontend: No downtime (nginx serves cached version)"
echo "     • Tenants: No downtime"
echo ""
echo -e "${BLUE}The upgrade process will:${NC}"
echo "  1. Create backup of current installation"
echo "  2. Stop API service"
echo "  3. Update all application files"
echo "  4. Rebuild frontend (if installed)"
echo "  5. Update server configuration"
echo "  6. Restart services"
echo ""
read -p "Do you understand and want to proceed? Type 'yes' to continue: " PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo ""
    echo "Upgrade cancelled by user."
    echo "No changes have been made to your system."
    exit 0
fi

echo ""
echo "Beginning upgrade process..."
echo ""

# Step 1: Create backup
echo -e "${BLUE}[1/8]${NC} Creating backup..."

mkdir -p "$BACKUP_DIR"

# Backup critical files and configurations
if [ -d "$INSTALL_DIR/config" ]; then
    cp -r "$INSTALL_DIR/config" "$BACKUP_DIR/"
    echo -e "${GREEN}✓${NC} Backed up configuration"
fi

# Check for old data structure
if [ -d "$INSTALL_DIR/data" ]; then
    echo "Legacy data directory detected at $INSTALL_DIR/data"
    echo "  This will be preserved in place (not backed up to save space)"
    HAS_OLD_DATA=true
else
    HAS_OLD_DATA=false
fi

# Backup old binaries
if [ -f "$INSTALL_DIR/cachepilot" ]; then
    cp "$INSTALL_DIR/cachepilot" "$BACKUP_DIR/cachepilot.old" 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} Backup created: $BACKUP_DIR"
echo ""

# Step 2: Stop services
echo -e "${BLUE}[2/8]${NC} Stopping services..."

if systemctl is-active --quiet cachepilot-api.service 2>/dev/null; then
    systemctl stop cachepilot-api.service
    echo -e "${GREEN}✓${NC} Stopped cachepilot-api service"
    API_WAS_RUNNING=true
else
    echo "API service not running"
    API_WAS_RUNNING=false
fi

echo ""

# Step 3: Check dependencies
echo -e "${BLUE}[3/8]${NC} Checking dependencies..."
if [ -x "$SCRIPT_DIR/install/scripts/check-deps.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/check-deps.sh"
else
    echo -e "${YELLOW}⚠${NC} check-deps.sh not found, skipping dependency check"
fi
echo ""

# Step 4: Migrate configuration to /etc/cachepilot
echo -e "${BLUE}[4/8]${NC} Checking configuration migration..."

if [ -d "/etc/cachepilot" ]; then
    echo "Configuration already migrated to /etc/cachepilot"
else
    echo "No existing configuration found, will be created during update"
fi
echo ""

# Step 5: Update application files
echo -e "${BLUE}[5/8]${NC} Updating application files..."

# Update CLI
if [ -d "$SCRIPT_DIR/cli" ]; then
    cp -r "$SCRIPT_DIR/cli"/* "$INSTALL_DIR/cli/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Updated CLI"
fi

# Update API
if [ -d "$SCRIPT_DIR/api" ]; then
    cp -r "$SCRIPT_DIR/api"/* "$INSTALL_DIR/api/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Updated API"
fi

# Update installation scripts
if [ -d "$SCRIPT_DIR/install" ]; then
    cp -r "$SCRIPT_DIR/install"/* "$INSTALL_DIR/install/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Updated installation scripts"
fi

# Update utility scripts
if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp -r "$SCRIPT_DIR/scripts"/* "$INSTALL_DIR/scripts/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Updated utility scripts"
fi

# Update docs
if [ -d "$SCRIPT_DIR/docs" ]; then
    cp -r "$SCRIPT_DIR/docs"/* "$INSTALL_DIR/docs/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Updated documentation"
fi

# Update root files
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/CHANGELOG.md" "$INSTALL_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/.gitignore" "$INSTALL_DIR/" 2>/dev/null || true

# Update configuration templates if they don't exist in /etc/cachepilot
mkdir -p /etc/cachepilot

if [ ! -f "/etc/cachepilot/system.yaml" ] && [ -f "$SCRIPT_DIR/config/system.yaml" ]; then
    cp "$SCRIPT_DIR/config/system.yaml" /etc/cachepilot/
    echo -e "${GREEN}✓${NC} Created system.yaml configuration"
fi

if [ ! -f "/etc/cachepilot/api.yaml" ] && [ -f "$SCRIPT_DIR/config/api.yaml" ]; then
    cp "$SCRIPT_DIR/config/api.yaml" /etc/cachepilot/
    echo -e "${GREEN}✓${NC} Created api.yaml configuration"
fi

if [ ! -f "/etc/cachepilot/frontend.yaml" ] && [ -f "$SCRIPT_DIR/config/frontend.yaml" ]; then
    cp "$SCRIPT_DIR/config/frontend.yaml" /etc/cachepilot/
    echo -e "${GREEN}✓${NC} Created frontend.yaml configuration"
fi

# Keep reference note in old location
mkdir -p "$INSTALL_DIR/config" 2>/dev/null || true
if [ ! -f "$INSTALL_DIR/config/README.txt" ]; then
    cat > "$INSTALL_DIR/config/README.txt" << 'EOF'
Configuration files have been moved to /etc/cachepilot/

This is part of FHS (Filesystem Hierarchy Standard) compliance.

Configuration files are now located at:
  - System config: /etc/cachepilot/system.yaml
  - API config: /etc/cachepilot/api.yaml
  - Frontend config: /etc/cachepilot/frontend.yaml
  - Logging config: /etc/cachepilot/logging-config.yaml
  - Monitoring config: /etc/cachepilot/monitoring-config.yaml
EOF
fi

# Set permissions
chmod +x "$INSTALL_DIR/cli/cachepilot"
chmod +x "$INSTALL_DIR/cli/lib"/*.sh
chmod +x "$INSTALL_DIR/scripts"/*.sh
chmod +x "$INSTALL_DIR/install/scripts"/*.sh

echo -e "${GREEN}✓${NC} Files updated and permissions set"
echo ""

# Step 6: Update Python dependencies
echo -e "${BLUE}[6/8]${NC} Updating Python dependencies..."

# Check for venv in both possible locations
if [ -d "$INSTALL_DIR/venv" ]; then
    VENV_PATH="$INSTALL_DIR/venv"
elif [ -d "$INSTALL_DIR/api/venv" ]; then
    VENV_PATH="$INSTALL_DIR/api/venv"
else
    VENV_PATH=""
fi

if [ -n "$VENV_PATH" ]; then
    echo "Using virtual environment: $VENV_PATH"
    # Use the venv's pip directly instead of relying on activation
    "$VENV_PATH/bin/pip" install --upgrade pip --quiet
    "$VENV_PATH/bin/pip" install -r "$INSTALL_DIR/api/requirements.txt" --quiet
    echo -e "${GREEN}✓${NC} Python dependencies updated"
else
    echo -e "${YELLOW}⚠${NC} Virtual environment not found, skipping Python dependencies"
    echo "Expected location: $INSTALL_DIR/venv or $INSTALL_DIR/api/venv"
fi
echo ""

# Step 7: Update systemd service
echo -e "${BLUE}[7/8]${NC} Updating systemd service..."

if [ -f "$INSTALL_DIR/install/systemd/cachepilot-api.service" ]; then
    cp "$INSTALL_DIR/install/systemd/cachepilot-api.service" /etc/systemd/system/
    systemctl daemon-reload
    echo -e "${GREEN}✓${NC} Systemd service updated"
else
    echo -e "${YELLOW}⚠${NC} Systemd service file not found"
fi
echo ""

# Step 8: Update log rotation
echo -e "${BLUE}[8/13]${NC} Updating log rotation..."

if [ -x "$INSTALL_DIR/install/scripts/setup-logrotate.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-logrotate.sh"
else
    echo -e "${YELLOW}⚠${NC} setup-logrotate.sh not found, skipping log rotation update"
fi
echo ""

# Step 9: Update cron jobs
echo -e "${BLUE}[9/13]${NC} Updating cron jobs..."

if [ -x "$INSTALL_DIR/install/scripts/setup-cron.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-cron.sh"
else
    echo -e "${YELLOW}⚠${NC} setup-cron.sh not found, skipping cron update"
fi
echo ""

# Step 10: Server Configuration Update
echo -e "${BLUE}[10/13]${NC} Checking server configuration..."

# Check if we need to prompt for server URL
NEEDS_SERVER_CONFIG=false
if [ -f "$INSTALL_DIR/config/frontend.yaml" ]; then
    if grep -q "url: http://localhost" "$INSTALL_DIR/config/frontend.yaml"; then
        NEEDS_SERVER_CONFIG=true
    fi
fi

if [ "$NEEDS_SERVER_CONFIG" = true ]; then
    echo ""
    echo "Server URL configuration detected as localhost."
    read -p "Update server URL/domain? (y/N): " UPDATE_SERVER_URL
    UPDATE_SERVER_URL=${UPDATE_SERVER_URL:-N}
    
    if [[ "$UPDATE_SERVER_URL" =~ ^[Yy]$ ]]; then
        echo ""
        read -p "Enter server domain/IP (default: localhost): " SERVER_DOMAIN
        SERVER_DOMAIN=${SERVER_DOMAIN:-localhost}
        
        read -p "Will you use SSL/HTTPS? (y/N): " USE_SSL
        USE_SSL=${USE_SSL:-N}
        
        if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
            SERVER_URL="https://$SERVER_DOMAIN"
        else
            SERVER_URL="http://$SERVER_DOMAIN"
        fi
        
        echo ""
        echo "Updating configuration with: $SERVER_URL"
        
        # Update configuration files in /etc/cachepilot
        if [ -f "/etc/cachepilot/frontend.yaml" ]; then
            sed -i "s|url: http://localhost|url: $SERVER_URL|g" /etc/cachepilot/frontend.yaml
            echo -e "${GREEN}✓${NC} Updated frontend.yaml"
        fi
        
        if [ -f "/etc/cachepilot/api.yaml" ]; then
            sed -i "s|http://localhost|$SERVER_URL|g" /etc/cachepilot/api.yaml
            sed -i "s|http://localhost:3000|$SERVER_URL|g" /etc/cachepilot/api.yaml
            echo -e "${GREEN}✓${NC} Updated api.yaml"
        fi
        
        export SERVER_DOMAIN
        export SERVER_URL
        export USE_SSL
    else
        echo "Keeping current server configuration"
    fi
else
    echo "Server configuration already customized, skipping"
fi
echo ""

# Step 11: Update Frontend
echo -e "${BLUE}[11/13]${NC} Updating frontend..."

if [ -d "$SCRIPT_DIR/frontend" ]; then
    # Copy frontend source files
    echo "Copying frontend source files..."
    cp -r "$SCRIPT_DIR/frontend"/* "$INSTALL_DIR/frontend/" 2>/dev/null || true
    
    # Check if Node.js is available
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        # Check if frontend was previously built
        if [ -d "$INSTALL_DIR/frontend/node_modules" ] || [ -d "$INSTALL_DIR/frontend/dist" ]; then
            echo "Rebuilding frontend..."
            if [ -x "$INSTALL_DIR/install/scripts/setup-frontend.sh" ]; then
                bash "$INSTALL_DIR/install/scripts/setup-frontend.sh"
                echo -e "${GREEN}✓${NC} Frontend rebuilt"
                FRONTEND_UPDATED=true
            else
                echo -e "${YELLOW}⚠${NC} setup-frontend.sh not found, skipping frontend build"
                FRONTEND_UPDATED=false
            fi
        else
            echo "Frontend not previously installed, skipping build"
            echo "To install frontend, run: $INSTALL_DIR/install/scripts/setup-frontend.sh"
            FRONTEND_UPDATED=false
        fi
    else
        echo -e "${YELLOW}⚠${NC} Node.js/npm not found, skipping frontend build"
        echo "Install Node.js 18+ to enable frontend: https://nodejs.org/"
        FRONTEND_UPDATED=false
    fi
else
    echo "Frontend source not found in upgrade package"
    FRONTEND_UPDATED=false
fi
echo ""

# Step 12: Update nginx configuration
echo -e "${BLUE}[12/13]${NC} Updating nginx configuration...

if [ "$FRONTEND_UPDATED" = true ] && [ -x "$INSTALL_DIR/install/scripts/setup-nginx.sh" ]; then
    # Check if nginx is installed and configured
    if command -v nginx &> /dev/null && [ -f "/etc/nginx/sites-available/redis-manager" ]; then
        read -p "Update nginx configuration? (Y/n): " UPDATE_NGINX
        UPDATE_NGINX=${UPDATE_NGINX:-Y}
        
        if [[ "$UPDATE_NGINX" =~ ^[Yy]$ ]]; then
            # Use server config if set, otherwise prompt
            if [ -n "${SERVER_DOMAIN:-}" ]; then
                bash "$INSTALL_DIR/install/scripts/setup-nginx.sh" "$SERVER_DOMAIN" "${USE_SSL:-N}"
            else
                bash "$INSTALL_DIR/install/scripts/setup-nginx.sh"
            fi
            echo -e "${GREEN}✓${NC} Nginx configuration updated"
        else
            echo "Skipping nginx update"
        fi
    else
        echo "Nginx not configured, skipping"
    fi
else
    echo "Frontend not updated or nginx setup script not found, skipping"
fi
echo ""

# Step 13: Fix TLS certificate permissions for existing tenants
echo -e "${BLUE}[13/13]${NC} Fixing TLS certificate permissions..."

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
echo -e "${GREEN}Upgrade Complete!${NC}"
echo "========================================"
echo ""
echo "CachePilot has been upgraded to v2.0.0"
echo ""
echo "Backup location: $BACKUP_DIR"
echo "  Keep this backup until you've verified the upgrade was successful"
echo ""
echo "Changes in v2.0:"
echo "  ✓ New directory structure with clear separation"
echo "  ✓ YAML-based configuration system"
echo "  ✓ Enhanced REST API"
echo "  ✓ React-based web frontend"
echo "  ✓ Improved installation and upgrade process"
echo ""
echo "Verify the upgrade:"
echo "  cachepilot --version"
echo "  cachepilot list"
echo "  cachepilot health"
echo ""
if [ "$API_WAS_RUNNING" = true ]; then
echo "Check API status:"
echo "  systemctl status cachepilot-api"
echo "  curl http://localhost:8000/api/v1/health"
echo ""
fi

if [ "$FRONTEND_UPDATED" = true ]; then
echo "Frontend has been updated:"
echo "  Location: $INSTALL_DIR/frontend/dist/"
echo "  If using nginx, it will serve the updated frontend automatically"
echo ""
fi
echo "If you encounter any issues:"
echo "  1. Check logs: journalctl -u cachepilot-api.service -f"
echo "  2. Review backup: $BACKUP_DIR"
echo "  3. Contact support: cachepilot@msrv-digital.de"
echo ""
echo "To remove backup after verification:"
echo "  rm -rf $BACKUP_DIR"
echo ""
