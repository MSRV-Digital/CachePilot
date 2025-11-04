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

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "CachePilot v2.1.0-beta Uninstallation"
echo "========================================"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

INSTALL_DIR="/opt/cachepilot"

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}CachePilot not installed${NC}"
    exit 1
fi

echo -e "${YELLOW}This will remove:${NC}"
echo "  • Application files ($INSTALL_DIR)"
echo "  • System symlinks, cron jobs, services"
echo ""

HAS_OLD_DATA=false
HAS_NEW_DATA=false

if [ -d "$INSTALL_DIR/data" ] && [ "$(ls -A $INSTALL_DIR/data 2>/dev/null)" ]; then
    HAS_OLD_DATA=true
    echo "Data found: $INSTALL_DIR/data/"
fi

if [ -d "/var/cachepilot" ] && [ "$(ls -A /var/cachepilot 2>/dev/null)" ]; then
    HAS_NEW_DATA=true
    echo "Data found: /var/cachepilot/, /var/log/cachepilot/"
fi

echo ""

if [ "$HAS_OLD_DATA" = true ] || [ "$HAS_NEW_DATA" = true ]; then
    read -p "Remove all tenant data and backups? (y/N): " REMOVE_DATA
    REMOVE_DATA=${REMOVE_DATA:-N}
    
    if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${RED}WARNING: All data will be PERMANENTLY DELETED!${NC}"
        read -p "Type 'DELETE' to confirm: " CONFIRM
        if [ "$CONFIRM" != "DELETE" ]; then
            REMOVE_DATA="N"
        fi
    fi
else
    REMOVE_DATA="N"
fi

echo ""
read -p "Proceed? (y/N): " PROCEED
if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

echo -e "${BLUE}[1/7]${NC} Stopping services..."

systemctl is-active --quiet cachepilot-api.service 2>/dev/null && systemctl stop cachepilot-api.service
systemctl is-enabled --quiet cachepilot-api.service 2>/dev/null && systemctl disable cachepilot-api.service
echo -e "${GREEN}✓${NC} Services stopped"

echo -e "${BLUE}[2/7]${NC} Stopping tenants..."

if [ -x "$INSTALL_DIR/cli/cachepilot" ]; then
    TENANTS=$("$INSTALL_DIR/cli/cachepilot" list --quiet 2>/dev/null | awk '{print $1}' || true)
    [ -n "$TENANTS" ] && for tenant in $TENANTS; do
        "$INSTALL_DIR/cli/cachepilot" stop "$tenant" 2>/dev/null || true
    done
fi
echo -e "${GREEN}✓${NC} Tenants stopped"

echo -e "${BLUE}[3/7]${NC} Removing system files..."
[ -f "/etc/systemd/system/cachepilot-api.service" ] && rm /etc/systemd/system/cachepilot-api.service && systemctl daemon-reload
[ -f "/etc/cron.d/cachepilot" ] && rm /etc/cron.d/cachepilot
[ -f "/etc/logrotate.d/cachepilot" ] && rm /etc/logrotate.d/cachepilot
[ -L "/usr/local/bin/cachepilot" ] && rm /usr/local/bin/cachepilot
echo -e "${GREEN}✓${NC} System files removed"

echo -e "${BLUE}[4/7]${NC} Removing application..."

if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    [ -d "/var/cachepilot" ] && rm -rf /var/cachepilot
    [ -d "/var/log/cachepilot" ] && rm -rf /var/log/cachepilot
    [ -d "/etc/cachepilot" ] && rm -rf /etc/cachepilot
    echo -e "${GREEN}✓${NC} All files and data removed"
else
    rm -rf "$INSTALL_DIR"/{cli,api,frontend,install,scripts,docs,config} 2>/dev/null || true
    rm -f "$INSTALL_DIR"/{README.md,LICENSE,CHANGELOG.md,.gitignore} 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Application removed (data preserved)"
fi

if [ -f "/etc/nginx/sites-enabled/redis-manager" ]; then
    rm /etc/nginx/sites-enabled/redis-manager
    rm /etc/nginx/sites-available/redis-manager 2>/dev/null || true
    nginx -t && systemctl reload nginx 2>/dev/null || true
fi

echo ""
echo "========================================"
echo -e "${GREEN}✓ Uninstallation Complete${NC}"
echo "========================================"
echo ""

if [[ ! "$REMOVE_DATA" =~ ^[Yy]$ ]] && { [ "$HAS_OLD_DATA" = true ] || [ "$HAS_NEW_DATA" = true ]; }; then
    echo "Data preserved. To remove manually:"
    [ "$HAS_OLD_DATA" = true ] && echo "  rm -rf $INSTALL_DIR/data"
    [ "$HAS_NEW_DATA" = true ] && echo "  rm -rf /var/cachepilot /var/log/cachepilot /etc/cachepilot"
fi
echo ""
