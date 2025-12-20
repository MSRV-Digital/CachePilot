#!/usr/bin/env bash
#
# CachePilot - Uninstallation Script
#
# Removes CachePilot and optionally data with safety mechanisms
# for Git repository and backup creation
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

# Check if this is a Git repository
IS_GIT_REPO=false
GIT_HAS_CHANGES=false
GIT_UNPUSHED=0
GIT_BRANCH=""

if [ -d "$INSTALL_DIR/.git" ]; then
    IS_GIT_REPO=true
    cd "$INSTALL_DIR"
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    # Check for uncommitted changes
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        GIT_HAS_CHANGES=true
    fi
    
    # Check for unpushed commits
    GIT_UNPUSHED=$(git log "origin/$GIT_BRANCH..HEAD" --oneline 2>/dev/null | wc -l || echo "0")
fi

# Display what will be removed
echo -e "${YELLOW}This will remove:${NC}"
echo "  • Application files ($INSTALL_DIR)"
if [ "$IS_GIT_REPO" = true ]; then
    echo "  • Git repository (branch: $GIT_BRANCH)"
    if [ "$GIT_HAS_CHANGES" = true ]; then
        echo "    ${YELLOW}⚠ Contains uncommitted changes${NC}"
    fi
    if [ "$GIT_UNPUSHED" -gt 0 ]; then
        echo "    ${YELLOW}⚠ Contains $GIT_UNPUSHED unpushed commit(s)${NC}"
    fi
fi
echo "  • System symlinks, cron jobs, services"
echo ""

# Check for data
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

# Git Repository Safety
CREATE_STASH="N"
if [ "$IS_GIT_REPO" = true ]; then
    echo ""
    echo -e "${RED}⚠️  GIT REPOSITORY DETECTED${NC}"
    echo "========================================"
    cd "$INSTALL_DIR"
    
    echo "Branch:         $GIT_BRANCH"
    echo "Last Commit:    $(git log -1 --format='%h - %s' --date=short 2>/dev/null || echo 'unknown')"
    
    if [ "$GIT_HAS_CHANGES" = true ]; then
        echo -e "${YELLOW}⚠ Uncommitted changes:${NC}"
        git status --short 2>/dev/null | head -10 || true
    fi
    
    if [ "$GIT_UNPUSHED" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Unpushed commits: $GIT_UNPUSHED${NC}"
        git log "origin/$GIT_BRANCH..HEAD" --oneline 2>/dev/null | head -5 || true
    fi
    
    echo ""
    if [ "$GIT_HAS_CHANGES" = true ] || [ "$GIT_UNPUSHED" -gt 0 ]; then
        read -p "Create Git stash before uninstalling? (Y/n): " CREATE_STASH
        CREATE_STASH=${CREATE_STASH:-Y}
    fi
fi

# Backup Option
echo ""
read -p "Create backup archive before uninstalling? (Y/n): " CREATE_BACKUP
CREATE_BACKUP=${CREATE_BACKUP:-Y}

BACKUP_FILE=""
if [[ "$CREATE_BACKUP" =~ ^[Yy]$ ]]; then
    BACKUP_FILE="/tmp/cachepilot-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
fi

# Data Removal Option
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

# Final Confirmation
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  • Remove application: Yes"
if [ "$IS_GIT_REPO" = true ]; then
    echo "  • Remove Git repository: Yes"
    if [[ "$CREATE_STASH" =~ ^[Yy]$ ]]; then
        echo "  • Create Git stash: Yes"
    fi
fi
if [[ "$CREATE_BACKUP" =~ ^[Yy]$ ]]; then
    echo "  • Create backup: Yes ($BACKUP_FILE)"
fi
if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    echo "  • Remove data: Yes (PERMANENT)"
else
    echo "  • Remove data: No (preserved)"
fi
echo ""
read -p "Proceed with uninstallation? (y/N): " PROCEED
if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# Create Git Stash
if [ "$IS_GIT_REPO" = true ] && [[ "$CREATE_STASH" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[0/8]${NC} Creating Git stash..."
    cd "$INSTALL_DIR"
    if git stash push -u -m "Pre-uninstall backup $(date +%Y%m%d_%H%M%S)" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Git stash created"
        echo "    To restore later: cd /opt/cachepilot && git stash pop"
    else
        echo -e "${YELLOW}⚠${NC} No changes to stash"
    fi
    echo ""
fi

# Create Backup
if [[ "$CREATE_BACKUP" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[1/8]${NC} Creating backup archive..."
    
    BACKUP_ITEMS=""
    [ -d "/opt/cachepilot" ] && BACKUP_ITEMS="$BACKUP_ITEMS -C /opt cachepilot"
    [ -d "/etc/cachepilot" ] && BACKUP_ITEMS="$BACKUP_ITEMS -C /etc cachepilot"
    [ -d "/var/cachepilot" ] && BACKUP_ITEMS="$BACKUP_ITEMS -C /var cachepilot"
    [ -d "/var/log/cachepilot" ] && BACKUP_ITEMS="$BACKUP_ITEMS -C /var/log cachepilot"
    
    if [ -n "$BACKUP_ITEMS" ]; then
        if tar -czf "$BACKUP_FILE" $BACKUP_ITEMS 2>/dev/null; then
            BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE ($BACKUP_SIZE)"
        else
            echo -e "${YELLOW}⚠${NC} Backup creation failed (continuing anyway)"
            BACKUP_FILE=""
        fi
    fi
    echo ""
fi

echo -e "${BLUE}[2/8]${NC} Stopping services..."

systemctl is-active --quiet cachepilot-api.service 2>/dev/null && systemctl stop cachepilot-api.service
systemctl is-enabled --quiet cachepilot-api.service 2>/dev/null && systemctl disable cachepilot-api.service
echo -e "${GREEN}✓${NC} Services stopped"

echo -e "${BLUE}[3/8]${NC} Stopping tenants..."

if [ -x "$INSTALL_DIR/cli/cachepilot" ]; then
    TENANTS=$("$INSTALL_DIR/cli/cachepilot" list --quiet 2>/dev/null | awk '{print $1}' || true)
    [ -n "$TENANTS" ] && for tenant in $TENANTS; do
        "$INSTALL_DIR/cli/cachepilot" stop "$tenant" 2>/dev/null || true
    done
fi
echo -e "${GREEN}✓${NC} Tenants stopped"

echo -e "${BLUE}[4/8]${NC} Removing system files..."
[ -f "/etc/systemd/system/cachepilot-api.service" ] && rm /etc/systemd/system/cachepilot-api.service && systemctl daemon-reload
[ -f "/etc/cron.d/cachepilot" ] && rm /etc/cron.d/cachepilot
[ -f "/etc/logrotate.d/cachepilot" ] && rm /etc/logrotate.d/cachepilot
[ -L "/usr/local/bin/cachepilot" ] && rm /usr/local/bin/cachepilot
echo -e "${GREEN}✓${NC} System files removed"

echo -e "${BLUE}[5/8]${NC} Removing nginx configuration..."
if [ -f "/etc/nginx/sites-enabled/redis-manager" ]; then
    rm /etc/nginx/sites-enabled/redis-manager
    rm /etc/nginx/sites-available/redis-manager 2>/dev/null || true
    nginx -t && systemctl reload nginx 2>/dev/null || true
    echo -e "${GREEN}✓${NC} nginx configuration removed"
else
    echo -e "${BLUE}→${NC} No nginx configuration found"
fi

echo -e "${BLUE}[6/8]${NC} Removing application..."

if [[ "$REMOVE_DATA" =~ ^[Yy]$ ]]; then
    # Full removal including data
    rm -rf "$INSTALL_DIR"
    [ -d "/var/cachepilot" ] && rm -rf /var/cachepilot
    [ -d "/var/log/cachepilot" ] && rm -rf /var/log/cachepilot
    [ -d "/etc/cachepilot" ] && rm -rf /etc/cachepilot
    echo -e "${GREEN}✓${NC} All files and data removed"
else
    # Remove only application files, preserve data
    rm -rf "$INSTALL_DIR"/{cli,api,frontend,install,scripts,docs,config} 2>/dev/null || true
    rm -f "$INSTALL_DIR"/{README.md,LICENSE,CHANGELOG.md,CONTRIBUTING.md} 2>/dev/null || true
    rm -f "$INSTALL_DIR"/.cachepilot-branch 2>/dev/null || true
    rm -rf "$INSTALL_DIR/.git" 2>/dev/null || true
    rm -f "$INSTALL_DIR/.gitignore" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Application removed (data preserved)"
fi

echo -e "${BLUE}[7/8]${NC} Cleaning up empty directories..."
# Remove empty directories
[ -d "$INSTALL_DIR" ] && [ -z "$(ls -A $INSTALL_DIR 2>/dev/null)" ] && rmdir "$INSTALL_DIR" 2>/dev/null || true
echo -e "${GREEN}✓${NC} Cleanup complete"

echo ""
echo "========================================"
echo -e "${GREEN}✓ Uninstallation Complete${NC}"
echo "========================================"
echo ""

# Show what was preserved
if [[ ! "$REMOVE_DATA" =~ ^[Yy]$ ]] && { [ "$HAS_OLD_DATA" = true ] || [ "$HAS_NEW_DATA" = true ]; }; then
    echo -e "${BLUE}Data Preserved:${NC}"
    [ "$HAS_OLD_DATA" = true ] && echo "  • $INSTALL_DIR/data/"
    [ "$HAS_NEW_DATA" = true ] && {
        echo "  • /var/cachepilot/"
        echo "  • /var/log/cachepilot/"
        echo "  • /etc/cachepilot/"
    }
    echo ""
    echo "To remove manually:"
    [ "$HAS_OLD_DATA" = true ] && echo "  rm -rf $INSTALL_DIR/data"
    [ "$HAS_NEW_DATA" = true ] && echo "  rm -rf /var/cachepilot /var/log/cachepilot /etc/cachepilot"
    echo ""
fi

# Show backup location
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    echo -e "${BLUE}Backup:${NC}"
    echo "  Location: $BACKUP_FILE"
    echo "  To restore: tar -xzf $BACKUP_FILE -C /"
    echo ""
fi

# Show Git stash info
if [ "$IS_GIT_REPO" = true ] && [[ "$CREATE_STASH" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Git Stash:${NC}"
    echo "  To restore changes: cd /opt/cachepilot && git stash pop"
    echo "  (Only works if you reinstall CachePilot in the same location)"
    echo ""
fi

echo "To reinstall CachePilot:"
echo "  git clone https://github.com/MSRV-Digital/CachePilot.git"
echo "  cd CachePilot"
echo "  sudo ./install/install.sh"
echo ""
