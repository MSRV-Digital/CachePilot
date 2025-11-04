#!/usr/bin/env bash
#
# CachePilot - Installation Script v2.0
#
# Interactive installation script that sets up the CachePilot system
# with automatic configuration, dependency checks, and initialization.
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
echo "CachePilot v2.0 Installation"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

# Installation directory
INSTALL_DIR="/opt/cachepilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Installation directory: $INSTALL_DIR"
echo "Source directory: $SCRIPT_DIR"
echo ""

# ================================================
# SYSTEM-WIDE INSTALLATION WARNING
# ================================================
echo "=================================================="
echo -e "${RED}⚠️  SYSTEM-WIDE INSTALLATION WARNING ⚠️${NC}"
echo "=================================================="
echo ""
echo -e "${YELLOW}This installation will modify your system:${NC}"
echo ""
echo "  📦 Package Installation:"
echo "     • Node.js 18+ (if not present)"
echo "     • nginx web server"
echo "     • certbot (Let's Encrypt SSL)"
echo "     • Python packages via pip"
echo ""
echo "  🔧 System Services:"
echo "     • cachepilot-api (systemd service)"
echo "     • nginx (web server on ports 80/443)"
echo "     • Cron jobs for maintenance"
echo ""
echo "  📁 File System Changes:"
echo "     • $INSTALL_DIR (installation directory)"
echo "     • /usr/local/bin/cachepilot (symlink)"
echo "     • /etc/nginx/sites-available/redis-manager"
echo "     • /etc/cron.d/cachepilot"
echo "     • /etc/systemd/system/cachepilot-api.service"
echo ""
echo "  🌐 Network Ports:"
echo "     • Port 80 (HTTP via nginx)"
echo "     • Port 443 (HTTPS via nginx)"
echo "     • Port 8000 (API, localhost only)"
echo ""
echo -e "${RED}⚠️  IMPORTANT NOTES:${NC}"
echo "  • Existing nginx configurations may be affected"
echo "  • System packages will be installed/updated"
echo "  • Services will be added to systemd"
echo "  • Docker containers will be created for Redis tenants"
echo ""
echo -e "${BLUE}💡 You can review the installation steps before proceeding.${NC}"
echo ""
read -p "Do you understand these changes and want to continue? Type 'yes' to proceed: " CONTINUE

if [ "$CONTINUE" != "yes" ]; then
    echo ""
    echo "Installation cancelled by user."
    echo "No changes have been made to your system."
    exit 0
fi

echo ""
echo -e "${GREEN}✓${NC} Installation confirmed. Proceeding..."
echo ""

# Create backup of existing installation if it exists
if [ -d "$INSTALL_DIR" ]; then
    BACKUP_DIR="/opt/cachepilot.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Creating backup of existing installation..."
    echo "Backup location: $BACKUP_DIR"
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
    echo -e "${GREEN}✓${NC} Backup created"
    echo ""
    echo -e "${BLUE}💡 Rollback Instructions:${NC}"
    echo "  If installation fails, you can restore from backup:"
    echo "  1. Stop services: systemctl stop cachepilot-api nginx"
    echo "  2. Remove new installation: rm -rf $INSTALL_DIR"
    echo "  3. Restore backup: mv $BACKUP_DIR $INSTALL_DIR"
    echo "  4. Restart services: systemctl start cachepilot-api nginx"
    echo ""
    read -p "Press Enter to continue with installation..."
fi

# Step 1: Check dependencies
echo -e "${BLUE}[1/8]${NC} Checking system dependencies..."
if [ -x "$SCRIPT_DIR/install/scripts/check-deps.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/check-deps.sh"
else
    echo -e "${RED}Error: check-deps.sh not found${NC}"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Dependency check failed. Please install missing dependencies.${NC}"
    exit 1
fi
echo ""

# Step 2: Create directories
echo -e "${BLUE}[2/8]${NC} Creating directory structure..."
if [ -x "$SCRIPT_DIR/install/scripts/setup-dirs.sh" ]; then
    bash "$SCRIPT_DIR/install/scripts/setup-dirs.sh"
else
    echo -e "${RED}Error: setup-dirs.sh not found${NC}"
    exit 1
fi

echo ""

# Step 3: Copy files
echo -e "${BLUE}[3/8]${NC} Installing files..."

# Only copy files if script is not already running from install directory
if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    echo "Copying files from $SCRIPT_DIR to $INSTALL_DIR..."
    
    # Copy CLI
    cp -r "$SCRIPT_DIR/cli"/* "$INSTALL_DIR/cli/" 2>/dev/null || true
    
    # Copy API
    cp -r "$SCRIPT_DIR/api"/* "$INSTALL_DIR/api/" 2>/dev/null || true
    
    # Copy installation scripts
    cp -r "$SCRIPT_DIR/install"/* "$INSTALL_DIR/install/" 2>/dev/null || true
    
    # Copy utility scripts
    cp -r "$SCRIPT_DIR/scripts"/* "$INSTALL_DIR/scripts/" 2>/dev/null || true
    
    
    # Copy docs
    cp -r "$SCRIPT_DIR/docs"/* "$INSTALL_DIR/docs/" 2>/dev/null || true
    
    # Copy root files
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/CHANGELOG.md" "$INSTALL_DIR/" 2>/dev/null || true
    
    # Copy configuration files to /etc/cachepilot (FHS-compliant location)
    echo "Copying configuration files to /etc/cachepilot..."
    if [ -d "$SCRIPT_DIR/config" ]; then
        cp -r "$SCRIPT_DIR/config"/* "/etc/cachepilot/" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Configuration files copied to /etc/cachepilot"
    fi
    
    # Keep a copy in /opt/cachepilot/config for backwards compatibility reference
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
        echo -e "${GREEN}✓${NC} Created reference note in $INSTALL_DIR/config/"
    fi
    
    echo -e "${GREEN}✓${NC} Files copied"
else
    echo "Already running from installation directory..."
    # Still need to copy configs to /etc/cachepilot if not there
    if [ -d "$INSTALL_DIR/config" ] && [ ! -f "/etc/cachepilot/system.yaml" ]; then
        echo "Copying configuration files to /etc/cachepilot..."
        cp -r "$INSTALL_DIR/config"/* "/etc/cachepilot/" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Configuration files copied to /etc/cachepilot"
    fi
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/cli/cachepilot"
chmod +x "$INSTALL_DIR/cli/lib"/*.sh
chmod +x "$INSTALL_DIR/scripts"/*.sh
chmod +x "$INSTALL_DIR/install/scripts"/*.sh

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

# Check if system.yaml exists and is valid
if [ -f "$INSTALL_DIR/config/system.yaml" ]; then
    echo -e "${GREEN}✓${NC} System configuration found"
else
    echo -e "${RED}✗${NC} System configuration not found: $INSTALL_DIR/config/system.yaml"
    exit 1
fi

echo ""
echo "Network Configuration:"
echo "Configure the IP addresses for Redis tenant bindings and external access."
echo ""
echo "Internal IP: Used for Redis container port bindings (where Redis listens)"
echo "  - Use 127.0.0.1 for localhost-only access (single server setup)"
echo "  - Use an internal/private IP (e.g., 10.x.x.x, 192.168.x.x) to allow access"
echo "    from other servers in your data center or internal network"
echo "  - Use 0.0.0.0 to listen on all interfaces (allows both internal and external access)"
echo "  ⚠  WARNING: Using a public IP will expose Redis servers directly to the internet!"
echo ""
read -p "Enter internal IP address (default: 127.0.0.1): " INTERNAL_IP
INTERNAL_IP=${INTERNAL_IP:-127.0.0.1}

echo ""
echo "Public IP: Used for RedisInsight web interface and external access URLs"
echo "  - Enter your server's public IP address or domain name"
echo "  - This is used for generating access URLs shown to users"
echo "  - Use 127.0.0.1 for local development only"
echo "  Note: This setting does not affect Redis server binding, only URL generation"
echo ""
read -p "Enter public IP or domain (default: 127.0.0.1): " PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-127.0.0.1}

echo ""
echo "Network configuration:"
echo "  Internal IP: $INTERNAL_IP"
echo "  Public IP: $PUBLIC_IP"
echo ""

# Update system.yaml with the configured IPs
if [ -f "$INSTALL_DIR/config/system.yaml" ]; then
    sed -i "s/internal_ip: localhost/internal_ip: $INTERNAL_IP/g" "$INSTALL_DIR/config/system.yaml"
    sed -i "s/public_ip: not-configured/public_ip: $PUBLIC_IP/g" "$INSTALL_DIR/config/system.yaml"
    echo -e "${GREEN}✓${NC} Network configuration updated in system.yaml"
fi

# Validate configuration
if command -v cachepilot &> /dev/null; then
    if cachepilot validate-config; then
        echo -e "${GREEN}✓${NC} Configuration validated"
    else
        echo -e "${YELLOW}⚠${NC} Configuration validation failed, but continuing..."
    fi
fi
echo ""

# Step 6: Setup log rotation
echo -e "${BLUE}[6/9]${NC} Setting up log rotation..."
if [ -x "$INSTALL_DIR/install/scripts/setup-logrotate.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-logrotate.sh"
else
    echo -e "${RED}Error: setup-logrotate.sh not found${NC}"
    exit 1
fi
echo ""

# Step 7: Setup cron jobs
echo -e "${BLUE}[7/9]${NC} Setting up cron jobs..."
if [ -x "$INSTALL_DIR/install/scripts/setup-cron.sh" ]; then
    bash "$INSTALL_DIR/install/scripts/setup-cron.sh"
else
    echo -e "${RED}Error: setup-cron.sh not found${NC}"
    exit 1
fi
echo ""

# Step 8: Setup REST API
echo -e "${BLUE}[8/10]${NC} REST API Setup..."
echo ""
echo "CachePilot includes a REST API for programmatic access."
echo "The API provides full tenant management, monitoring, and backup operations."
echo ""
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
    echo "Skipping REST API installation."
    echo "You can install it later by running: $INSTALL_DIR/install/scripts/setup-api.sh"
    API_INSTALLED=false
fi
echo ""

# Step 9: Server Configuration
echo -e "${BLUE}[9/10]${NC} Server Configuration..."
echo ""
echo "Configure the server URL/domain for CachePilot."
echo "This will be used for:"
echo "  - nginx reverse proxy configuration"
echo "  - API CORS settings"
echo "  - Frontend API endpoint"
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
echo "Server configuration:"
echo "  Domain: $SERVER_DOMAIN"
echo "  URL: $SERVER_URL"
echo ""

# Update configuration files with server URL
if [ -f "$INSTALL_DIR/config/frontend.yaml" ]; then
    sed -i "s|url: http://localhost|url: $SERVER_URL|g" "$INSTALL_DIR/config/frontend.yaml"
    echo -e "${GREEN}✓${NC} Updated frontend.yaml"
fi

if [ -f "$INSTALL_DIR/config/api.yaml" ]; then
    # Update CORS origins
    sed -i "s|http://localhost|$SERVER_URL|g" "$INSTALL_DIR/config/api.yaml"
    sed -i "s|http://localhost:3000|$SERVER_URL|g" "$INSTALL_DIR/config/api.yaml"
    echo -e "${GREEN}✓${NC} Updated api.yaml"
fi

export SERVER_DOMAIN
export SERVER_URL
export USE_SSL

echo ""

# Step 10: Setup Frontend + nginx (optional)
echo -e "${BLUE}[10/10]${NC} Frontend Setup..."
echo ""
echo "CachePilot includes a React-based web frontend with nginx reverse proxy."
echo "This provides a unified interface for both frontend and API on port 80/443."
echo ""

if command -v node &> /dev/null && command -v npm &> /dev/null; then
    read -p "Install Frontend with nginx? (Y/n): " INSTALL_FRONTEND
    INSTALL_FRONTEND=${INSTALL_FRONTEND:-Y}
    
    if [[ "$INSTALL_FRONTEND" =~ ^[Yy]$ ]]; then
        # Build frontend
        if [ -x "$INSTALL_DIR/install/scripts/setup-frontend.sh" ]; then
            echo "Building frontend..."
            bash "$INSTALL_DIR/install/scripts/setup-frontend.sh"
            FRONTEND_INSTALLED=true
        else
            echo -e "${RED}Error: setup-frontend.sh not found${NC}"
            FRONTEND_INSTALLED=false
        fi
        
        # Setup nginx with server configuration
        if [ "$FRONTEND_INSTALLED" = true ] && [ -x "$INSTALL_DIR/install/scripts/setup-nginx.sh" ]; then
            echo ""
            echo "Configuring nginx reverse proxy..."
            bash "$INSTALL_DIR/install/scripts/setup-nginx.sh" "$SERVER_DOMAIN" "$USE_SSL"
            NGINX_INSTALLED=true
        else
            echo -e "${YELLOW}⚠${NC} Skipping nginx setup"
            NGINX_INSTALLED=false
        fi
    else
        echo "Skipping frontend installation."
        FRONTEND_INSTALLED=false
        NGINX_INSTALLED=false
    fi
else
    echo -e "${YELLOW}⚠${NC} Node.js/npm not found. Skipping frontend installation."
    echo "Install Node.js 18+ to enable frontend: https://nodejs.org/"
    FRONTEND_INSTALLED=false
    NGINX_INSTALLED=false
fi
echo ""

# Installation complete
echo "========================================"
echo -e "${GREEN}Installation Complete!${NC}"
echo "========================================"
echo ""
echo "CachePilot v2.0.0 has been installed successfully."
echo ""
echo -e "${BLUE}What's New in v2.0:${NC}"
echo "  ✓ Professional directory structure"
echo "  ✓ YAML-based configuration system"
echo "  ✓ Modular installation scripts"
echo "  ✓ Enhanced REST API"
if [ "$FRONTEND_INSTALLED" = true ]; then
echo "  ✓ React-based web frontend"
fi
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo "  cachepilot new customer01        # Create first tenant"
echo "  cachepilot list                  # List all tenants"
echo "  cachepilot stats                 # Show statistics"
echo "  cachepilot status customer01     # Show tenant details"
echo "  cachepilot health                # Check system health"
echo ""

if [ "$API_INSTALLED" = true ]; then
echo -e "${BLUE}API Access:${NC}"
echo "  URL: http://localhost:8000"
echo "  Docs: http://localhost:8000/docs"
echo "  Check config/api-keys.json for your API key"
echo ""
fi

if [ "$FRONTEND_INSTALLED" = true ]; then
echo -e "${BLUE}Frontend:${NC}"
echo "  URL: $SERVER_URL/"
echo "  Built files: $INSTALL_DIR/frontend/dist/"
if [ "$NGINX_INSTALLED" = true ]; then
echo "  nginx serving frontend and proxying API"
fi
echo ""
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  System: $INSTALL_DIR/config/system.yaml"
echo "  API: $INSTALL_DIR/config/api.yaml"
echo "  Frontend: $INSTALL_DIR/config/frontend.yaml"
echo ""
echo -e "${BLUE}Log Files:${NC}"
echo "  Main: /var/log/cachepilot/cachepilot.log"
echo "  Audit: /var/log/cachepilot/audit.log"
echo "  Metrics: /var/log/cachepilot/metrics.log"
echo ""
echo -e "${BLUE}Service Management:${NC}"
if [ "$API_INSTALLED" = true ]; then
echo "  systemctl status cachepilot-api    # Check API status"
echo "  systemctl restart cachepilot-api   # Restart API"
echo "  journalctl -u cachepilot-api -f    # View API logs"
fi
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  README: $INSTALL_DIR/README.md"
echo "  API Docs: $INSTALL_DIR/docs/API.md"
echo "  Configuration: $INSTALL_DIR/docs/CONFIGURATION.md"
echo "  Deployment: $INSTALL_DIR/docs/DEPLOYMENT.md"
echo ""
echo "For support or questions, check the documentation or contact:"
echo "  Patrick Schlesinger <cachepilot@msrv-digital.de>"
echo ""
