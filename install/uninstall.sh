#!/usr/bin/env bash
#
# CachePilot - Uninstallation Script
#
# Removes CachePilot and optionally data
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
echo "CachePilot v2.0 Uninstallation"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

INSTALL_DIR="/opt/cachepilot"

# Check if CachePilot is installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}CachePilot is not installed at $INSTALL_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will remove CachePilot from your system!${NC}"
echo ""
echo "The following will be removed:"
echo "  - CachePilot application files ($INSTALL_DIR)"
echo "  - System symlinks"
echo "  - Cron jobs"
echo "  - Systemd services"
echo ""

# Check for data locations
HAS_OLD_DATA=false
HAS_NEW_DATA=false

if [ -d "$INSTALL_DIR/data" ] && [ "$(ls -A $INSTALL_DIR/data 2>/dev/null)" ]; then
    HAS_OLD_DATA=true
    echo "Legacy data structure detected:"
    echo "  - $INSTALL_DIR/data/"
fi

if [ -d "/var/cachepilot" ] && [ "$(ls -A /var/cachepilot 2>/dev/null)" ]; then
    HAS_NEW_DATA=true
    echo "FHS-compliant data structure detected:"
    echo "  - /var/cachepilot/"
fi

if [ -d "/var/log/cachepilot" ] && [ "$(ls -A /var/log/cachepilot 2>/dev/null)" ]; then
    echo "  - /var/log/cachepilot/"
fi

echo ""

# Ask about data removal
if [ "$HAS_OLD_DATA" = true ] || [ "$HAS_NEW_DATA" = true ]; then
    read -p "Do you want to also remove all tenant data and backups? (y/N): " REMOVE_DATA
    REMOVE_DATA=${REMOVE_DATA:-N}
    echo ""
    
    if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
        echo -e "${RED}WARNING: All tenant data, backups, and certificates will be PERMANENTLY DELETED!${NC}"
        echo "This includes:"
        if [ "$HAS_OLD_DATA" = true ]; then
            echo "  - $INSTALL_DIR/data/"
        fi
        if [ "$HAS_NEW_DATA" = true ]; then
            echo "  - /var/cachepilot/"
            echo "  - /var/log/cachepilot/"
        fi
        read -p "Are you absolutely sure? Type 'DELETE' to confirm: " CONFIRM
        if [ "$CONFIRM" != "DELETE" ]; then
            echo "Data removal cancelled."
            REMOVE_DATA="N"
        fi
    else
        echo "Data will be preserved at:"
        if [ "$HAS_OLD_DATA" = true ]; then
            echo "  - $INSTALL_DIR/data/"
        fi
        if [ "$HAS_NEW_DATA" = true ]; then
            echo "  - /var/cachepilot/"
            echo "  - /var/log/cachepilot/"
        fi
    fi
else
    REMOVE_DATA="N"
    echo "No data directories found."
fi

echo ""
read -p "Proceed with uninstallation? (y/N): " PROCEED
PROCEED=${PROCEED:-N}

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Beginning uninstallation..."
echo ""

# Step 1: Stop and disable services
echo -e "${BLUE}[1/7]${NC} Stopping services..."

if systemctl is-active --quiet cachepilot-api.service 2>/dev/null; then
    systemctl stop cachepilot-api.service
    echo -e "${GREEN}✓${NC} Stopped cachepilot-api service"
fi

if systemctl is-enabled --quiet cachepilot-api.service 2>/dev/null; then
    systemctl disable cachepilot-api.service
    echo -e "${GREEN}✓${NC} Disabled cachepilot-api service"
fi

# Step 2: Stop all tenant containers
echo -e "${BLUE}[2/7]${NC} Stopping tenant containers..."

if [ -x "$INSTALL_DIR/cli/cachepilot" ]; then
    TENANTS=$("$INSTALL_DIR/cli/cachepilot" list --quiet 2>/dev/null | awk '{print $1}' || true)
    
    if [ -n "$TENANTS" ]; then
        for tenant in $TENANTS; do
            echo "Stopping tenant: $tenant"
            "$INSTALL_DIR/cli/cachepilot" stop "$tenant" 2>/dev/null || true
        done
        echo -e "${GREEN}✓${NC} All tenants stopped"
    else
        echo "No active tenants found"
    fi
else
    echo -e "${YELLOW}⚠${NC} cachepilot command not found, skipping tenant shutdown"
fi

# Step 3: Remove systemd service
echo -e "${BLUE}[3/7]${NC} Removing systemd service..."

if [ -f "/etc/systemd/system/cachepilot-api.service" ]; then
    rm /etc/systemd/system/cachepilot-api.service
    systemctl daemon-reload
    echo -e "${GREEN}✓${NC} Removed systemd service"
else
    echo "Systemd service not found"
fi

# Step 4: Remove cron jobs
echo -e "${BLUE}[4/7]${NC} Removing cron jobs..."

if [ -f "/etc/cron.d/cachepilot" ]; then
    rm /etc/cron.d/cachepilot
    echo -e "${GREEN}✓${NC} Removed cron jobs"
else
    echo "Cron jobs not found"
fi

# Step 5: Remove log rotation
echo -e "${BLUE}[5/7]${NC} Removing log rotation..."

if [ -f "/etc/logrotate.d/cachepilot" ]; then
    rm /etc/logrotate.d/cachepilot
    echo -e "${GREEN}✓${NC} Removed log rotation configuration"
else
    echo "Log rotation configuration not found"
fi

# Step 6: Remove symlinks
echo -e "${BLUE}[6/7]${NC} Removing symlinks..."

if [ -L "/usr/local/bin/cachepilot" ]; then
    rm /usr/local/bin/cachepilot
    echo -e "${GREEN}✓${NC} Removed /usr/local/bin/cachepilot"
else
    echo "Symlink not found"
fi

# Step 7: Remove application files
echo -e "${BLUE}[7/7]${NC} Removing application files..."

if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    echo "Removing entire installation directory including data..."
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}✓${NC} Removed $INSTALL_DIR"
    
    # Remove FHS-compliant directories
    if [ -d "/var/cachepilot" ]; then
        rm -rf /var/cachepilot
        echo -e "${GREEN}✓${NC} Removed /var/cachepilot/"
    fi
    
    if [ -d "/var/log/cachepilot" ]; then
        rm -rf /var/log/cachepilot
        echo -e "${GREEN}✓${NC} Removed /var/log/cachepilot/"
    fi
    
    # Remove FHS-compliant configuration directory
    if [ -d "/etc/cachepilot" ]; then
        rm -rf /etc/cachepilot
        echo -e "${GREEN}✓${NC} Removed /etc/cachepilot/"
    fi
    
    # Remove nginx configuration if exists
    if [ -f "/etc/nginx/sites-enabled/redis-manager" ]; then
        rm /etc/nginx/sites-enabled/redis-manager
        rm /etc/nginx/sites-available/redis-manager 2>/dev/null || true
        nginx -t && systemctl reload nginx
        echo -e "${GREEN}✓${NC} Removed nginx configuration"
    fi
else
    echo "Removing application files but preserving data..."
    
    # Remove application directories
    rm -rf "$INSTALL_DIR/cli" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/api" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/frontend" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/install" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/scripts" 2>/dev/null || true
    rm -rf "$INSTALL_DIR/docs" 2>/dev/null || true
    
    # Remove nginx configuration if exists
    if [ -f "/etc/nginx/sites-enabled/redis-manager" ]; then
        echo "Removing nginx configuration..."
        rm /etc/nginx/sites-enabled/redis-manager
        rm /etc/nginx/sites-available/redis-manager 2>/dev/null || true
        nginx -t && systemctl reload nginx
        echo -e "${GREEN}✓${NC} Removed nginx configuration"
    fi
    
    # Note: Configuration files in /etc/cachepilot are preserved
    # Only remove old config directory references
    rm -rf "$INSTALL_DIR/config" 2>/dev/null || true
    
    # Remove root files
    rm -f "$INSTALL_DIR/README.md" 2>/dev/null || true
    rm -f "$INSTALL_DIR/LICENSE" 2>/dev/null || true
    rm -f "$INSTALL_DIR/CHANGELOG.md" 2>/dev/null || true
    rm -f "$INSTALL_DIR/.gitignore" 2>/dev/null || true
    
    echo -e "${GREEN}✓${NC} Removed application files"
    echo ""
    echo -e "${YELLOW}Data preserved in:${NC}"
    if [ "$HAS_OLD_DATA" = true ]; then
        echo "  - $INSTALL_DIR/data/tenants/"
        echo "  - $INSTALL_DIR/data/backups/"
        echo "  - $INSTALL_DIR/data/ca/"
        echo "  - $INSTALL_DIR/data/logs/"
    fi
    if [ "$HAS_NEW_DATA" = true ]; then
        echo "  - /var/cachepilot/tenants/"
        echo "  - /var/cachepilot/backups/"
        echo "  - /var/cachepilot/ca/"
        echo "  - /var/log/cachepilot/"
    fi
    if [ -d "/etc/cachepilot" ]; then
        echo "  - /etc/cachepilot/ (configuration)"
    fi
fi

echo ""
echo "========================================"
echo -e "${GREEN}Uninstallation Complete!${NC}"
echo "========================================"
echo ""

if [[ ! "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    echo "CachePilot has been removed but your data is preserved."
    echo ""
    echo "To reinstall CachePilot:"
    echo "  1. Download the latest version"
    echo "  2. Run the installation script"
    echo "  3. Your tenants and backups will be automatically detected"
    echo ""
    echo "To manually remove all data:"
    if [ "$HAS_OLD_DATA" = true ]; then
        echo "  rm -rf $INSTALL_DIR"
    fi
    if [ "$HAS_NEW_DATA" = true ]; then
        echo "  rm -rf /var/cachepilot"
        echo "  rm -rf /var/log/cachepilot"
        echo "  rm -rf /etc/cachepilot"
    fi
else
    echo "CachePilot and all data have been completely removed."
fi
echo ""
