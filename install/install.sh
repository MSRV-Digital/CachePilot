#!/usr/bin/env bash
#
# CachePilot - Installation Script
#
# Interactive installation script that sets up the CachePilot system
# with automatic configuration, dependency checks, and initialization.
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
echo "CachePilot v2.1.0-beta Installation"
echo "========================================"
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

INSTALL_DIR="/opt/cachepilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Installation will use Git-based deployment"
echo "Repository: https://github.com/MSRV-Digital/CachePilot"
echo "Target directory: $INSTALL_DIR"
echo ""

echo "=================================================="
echo -e "${RED}⚠️  SYSTEM-WIDE INSTALLATION WARNING${NC}"
echo "=================================================="
echo ""
echo -e "${YELLOW}This installation will modify your system:${NC}"
echo ""
echo "  • Package installation (Node.js, nginx, certbot, Python packages)"
echo "  • System services (cachepilot-api, nginx, cron jobs)"
echo "  • File system changes ($INSTALL_DIR, /etc/cachepilot, /usr/local/bin/cachepilot)"
echo "  • Network ports (80, 443, 8000)"
echo "  • Docker containers for Redis tenants"
echo ""
echo -e "${RED}Note:${NC} Existing nginx configurations may be affected"
echo ""
read -p "Type 'yes' to proceed: " CONTINUE

if [ "$CONTINUE" != "yes" ]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""

echo -e "${BLUE}[0/10]${NC} Cloning CachePilot from Git..."

# Use git-setup.sh to handle Git-based installation
if [ -x "$SCRIPT_DIR/install/scripts/git-setup.sh" ]; then
    # Select branch
    echo ""
    echo "Select installation branch:"
    echo "  1) main    - Stable releases (recommended)"
    echo "  2) develop - Beta versions"
    read -p "Choice [1]: " BRANCH_CHOICE
    
    case $BRANCH_CHOICE in
        2) GIT_BRANCH="develop" ;;
        *) GIT_BRANCH="main" ;;
    esac
    
    bash "$SCRIPT_DIR/install/scripts/git-setup.sh" install "$GIT_BRANCH"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Git installation failed${NC}"
        exit 1
    fi
    
    # Switch to the newly cloned installation directory
    SCRIPT_DIR="$INSTALL_DIR"
    echo -e "${GREEN}✓${NC} Switched to installation directory: $INSTALL_DIR"
else
    echo -e "${RED}Error: git-setup.sh not found${NC}"
    exit 1
fi
echo ""

echo -e "${BLUE}[0.5/10]${NC} Setting up configuration..."

mkdir -p "/etc/cachepilot"

if [ -d "$INSTALL_DIR/config" ]; then
    cp -r "$INSTALL_DIR/config"/* "/etc/cachepilot/" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Configuration files copied"
else
    echo -e "${RED}✗${NC} Configuration source not found"
    exit 1
fi

chmod 755 "/etc/cachepilot"
chmod 640 "/etc/cachepilot"/*.yaml 2>/dev/null || true
echo -e "${GREEN}✓${NC} Permissions set"

echo -e "${BLUE}[1/8]${NC} Installing system dependencies..."
if [ -x "$SCRIPT_DIR/install/scripts/install-deps.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/install-deps.sh"
else
    echo -e "${RED}Error: install-deps.sh not found${NC}"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Dependency installation failed.${NC}"
    exit 1
fi
echo ""

if [ -x "$SCRIPT_DIR/install/scripts/check-deps.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/check-deps.sh"
fi
echo ""

echo -e "${BLUE}[2/8]${NC} Creating directory structure..."
if [ -x "$SCRIPT_DIR/install/scripts/setup-dirs.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/setup-dirs.sh"
else
    echo -e "${RED}Error: setup-dirs.sh not found${NC}"
    exit 1
fi

echo ""

# Step 3: Set permissions (files already cloned from Git)
echo -e "${BLUE}[3/8]${NC} Setting file permissions..."

chmod +x "$INSTALL_DIR/cli/cachepilot"
chmod +x "$INSTALL_DIR/cli/lib"/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/scripts"/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/install/scripts"/*.sh 2>/dev/null || true

echo -e "${GREEN}✓${NC} Permissions set"
echo ""

# Step 4: Create symlink
echo -e "${BLUE}[4/8]${NC} Creating system symlink..."
if [ -L /usr/local/bin/cachepilot ]; then
    rm /usr/local/bin/cachepilot
fi
ln -sf "$INSTALL_DIR/cli/cachepilot" /usr/local/bin/cachepilot
echo -e "${GREEN}✓${NC} Symlink created: /usr/local/bin/cachepilot → $INSTALL_DIR/cli/cachepilot"
echo ""

# Step 5: Initialize configuration
echo -e "${BLUE}[5/8]${NC} Initializing configuration..."

if [ ! -f "/etc/cachepilot/system.yaml" ]; then
    echo -e "${RED}✗${NC} Configuration not found"
    exit 1
fi

echo ""
echo "=========================================="
echo "NETZWERK KONFIGURATION"
echo "=========================================="
echo ""
echo -e "${YELLOW}WICHTIG: Redis wird über das interne Netzwerk genutzt!${NC}"
echo ""
echo "Internal IP (Redis Binding):"
echo "  • Für Netzwerk-Zugriff: Geben Sie die interne Server-IP ein"
echo "    Beispiele: 10.0.0.5, 192.168.1.100, 172.16.0.10"
echo "  • Für alle Interfaces: 0.0.0.0"
echo "  • NUR für lokale Tests: 127.0.0.1"
echo ""
read -p "Internal IP (Netzwerk-Zugriff empfohlen): " INTERNAL_IP

# Validierung und Warnung
if [[ -z "$INTERNAL_IP" ]] || [[ "$INTERNAL_IP" == "127.0.0.1" ]]; then
    echo ""
    echo -e "${RED}⚠️  WARNUNG: 127.0.0.1 erlaubt NUR lokalen Zugriff!${NC}"
    echo -e "${YELLOW}Redis wird NICHT über das Netzwerk erreichbar sein.${NC}"
    echo ""
    read -p "Wirklich fortfahren mit 127.0.0.1? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        read -p "Geben Sie die interne Server-IP ein: " INTERNAL_IP
        if [[ -z "$INTERNAL_IP" ]]; then
            echo "Installation abgebrochen."
            exit 1
        fi
    fi
fi

INTERNAL_IP=${INTERNAL_IP:-127.0.0.1}
echo ""
echo "Public IP/Domain (für RedisInsight und externe URLs):"
read -p "Public IP/domain (default: 127.0.0.1): " PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-127.0.0.1}

sed -i "s/internal_ip: localhost/internal_ip: $INTERNAL_IP/g" "/etc/cachepilot/system.yaml"
sed -i "s/public_ip: localhost/public_ip: $PUBLIC_IP/g" "/etc/cachepilot/system.yaml"
echo -e "${GREEN}✓${NC} Configuration updated"
echo ""

echo -e "${BLUE}[6/9]${NC} Setting up log rotation..."
if [ -x "$INSTALL_DIR/install/scripts/setup-logrotate.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-logrotate.sh"
else
    echo -e "${RED}Error: setup-logrotate.sh not found${NC}"
    exit 1
fi
echo ""

# Step 7: Setup cron jobs
echo -e "${BLUE}[7/10]${NC} Setting up cron jobs..."
if [ -x "$INSTALL_DIR/install/scripts/setup-cron.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-cron.sh"
else
    echo -e "${RED}Error: setup-cron.sh not found${NC}"
    exit 1
fi
echo ""

# Step 7.5: Optional Network Tuning
echo -e "${BLUE}[7.5/10]${NC} Network Performance Tuning (Optional)..."
echo ""
echo "Apply system-level network optimizations for maximum Redis performance?"
echo "  • Higher connection capacity (65k connections)"
echo "  • Lower latency (tcp-nodelay, optimized timeouts)"
echo "  • Better throughput (optimized TCP buffers)"
echo "  • Disables Transparent Huge Pages (THP)"
echo ""
read -p "Apply network tuning? (Y/n): " APPLY_TUNING
APPLY_TUNING=${APPLY_TUNING:-Y}

if [[ "$APPLY_TUNING" =~ ^[Yy]$ ]]; then
    if [ -x "$INSTALL_DIR/install/scripts/setup-network-tuning.sh" ]; then
        bash "$INSTALL_DIR/install/scripts/setup-network-tuning.sh"
        TUNING_APPLIED=true
    else
        echo -e "${YELLOW}⚠${NC} Network tuning script not found, skipping"
        TUNING_APPLIED=false
    fi
else
    echo "Network tuning skipped (can be applied later with: sudo bash $INSTALL_DIR/install/scripts/setup-network-tuning.sh)"
    TUNING_APPLIED=false
fi
echo ""

# Step 8: Setup REST API
echo -e "${BLUE}[8/10]${NC} REST API Setup..."
read -p "Install REST API? (Y/n): " INSTALL_API
INSTALL_API=${INSTALL_API:-Y}

if [[ "$INSTALL_API" =~ ^[Yy]$ ]]; then
    if [ -x "$INSTALL_DIR/install/scripts/setup-api.sh" ]; then
        bash "$INSTALL_DIR/install/scripts/setup-api.sh"
        API_INSTALLED=true
    else
        echo -e "${RED}Error: setup-api.sh not found${NC}"
        exit 1
    fi
else
    API_INSTALLED=false
fi
echo ""

echo -e "${BLUE}[9/10]${NC} Server Configuration..."

read -p "Server domain/IP (default: localhost): " SERVER_DOMAIN
SERVER_DOMAIN=${SERVER_DOMAIN:-localhost}

read -p "Use SSL/HTTPS? (y/N): " USE_SSL
USE_SSL=${USE_SSL:-N}

if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
    SERVER_URL="https://$SERVER_DOMAIN"
else
    SERVER_URL="http://$SERVER_DOMAIN"
fi

sed -i "s|url: http://localhost|url: $SERVER_URL|g" "/etc/cachepilot/frontend.yaml" 2>/dev/null || true
sed -i "s|http://localhost|$SERVER_URL|g" "/etc/cachepilot/api.yaml" 2>/dev/null || true
sed -i "s|http://localhost:3000|$SERVER_URL|g" "/etc/cachepilot/api.yaml" 2>/dev/null || true

export SERVER_DOMAIN SERVER_URL USE_SSL
echo ""

echo -e "${BLUE}[10/10]${NC} Frontend Setup..."

if command -v node &> /dev/null && command -v npm &> /dev/null; then
    read -p "Install Frontend with nginx? (Y/n): " INSTALL_FRONTEND
    INSTALL_FRONTEND=${INSTALL_FRONTEND:-Y}
    
    if [[ "$INSTALL_FRONTEND" =~ ^[Yy]$ ]]; then
        if [ -x "$INSTALL_DIR/install/scripts/setup-frontend.sh" ]; then
            bash "$INSTALL_DIR/install/scripts/setup-frontend.sh"
            FRONTEND_INSTALLED=true
        else
            FRONTEND_INSTALLED=false
        fi
        
        if [ "$FRONTEND_INSTALLED" = true ] && [ -x "$INSTALL_DIR/install/scripts/setup-nginx.sh" ]; then
            bash "$INSTALL_DIR/install/scripts/setup-nginx.sh" "$SERVER_DOMAIN" "$USE_SSL"
            NGINX_INSTALLED=true
        else
            NGINX_INSTALLED=false
        fi
    else
        FRONTEND_INSTALLED=false
        NGINX_INSTALLED=false
    fi
else
    FRONTEND_INSTALLED=false
    NGINX_INSTALLED=false
fi
echo ""

echo "========================================"
echo -e "${GREEN}✓ CachePilot v2.1.0-beta Installed${NC}"
echo "========================================"
echo ""
echo "Quick Start:"
echo "  cachepilot new customer01"
echo "  cachepilot list"
echo "  cachepilot health"
echo ""

if [ "$API_INSTALLED" = true ]; then
echo "API: http://localhost:8000/docs"
fi

if [ "$FRONTEND_INSTALLED" = true ]; then
echo "Frontend: $SERVER_URL/"
fi

echo ""
echo "Configuration: /etc/cachepilot/"
echo "Logs: /var/log/cachepilot/"
echo ""
echo "Documentation: $INSTALL_DIR/README.md"
echo ""
