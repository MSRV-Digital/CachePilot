#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo "Installing system dependencies..."
echo ""

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}Cannot detect OS. Only Ubuntu/Debian supported.${NC}"
    exit 1
fi

. /etc/os-release

if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
    echo -e "${RED}Unsupported OS: $ID${NC}"
    echo "Only Ubuntu and Debian are supported."
    exit 1
fi

echo "Detected OS: $NAME $VERSION"
echo ""

echo "Updating package lists..."

# Wait for any existing apt/dpkg processes to complete
if ! wait_for_apt_lock; then
    echo -e "${RED}✗${NC} Cannot proceed with package installation"
    exit 1
fi

apt-get update -qq

PACKAGES_TO_INSTALL=()

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing docker.io...${NC}"
    PACKAGES_TO_INSTALL+=(docker.io)
fi

if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null 2>&1; then
    if [ "$ID" = "debian" ]; then
        echo -e "${YELLOW}Installing docker-compose (standalone)...${NC}"
        PACKAGES_TO_INSTALL+=(docker-compose)
    else
        echo -e "${YELLOW}Installing docker-compose-plugin...${NC}"
        PACKAGES_TO_INSTALL+=(docker-compose-plugin)
    fi
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Installing python3...${NC}"
    PACKAGES_TO_INSTALL+=(python3)
fi

if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}Installing python3-pip...${NC}"
    PACKAGES_TO_INSTALL+=(python3-pip)
fi

if ! dpkg -l | grep -q python3-venv; then
    echo -e "${YELLOW}Installing python3-venv...${NC}"
    PACKAGES_TO_INSTALL+=(python3-venv)
fi

if ! command -v nginx &> /dev/null; then
    echo -e "${YELLOW}Installing nginx...${NC}"
    PACKAGES_TO_INSTALL+=(nginx)
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    PACKAGES_TO_INSTALL+=(jq)
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${YELLOW}Installing openssl...${NC}"
    PACKAGES_TO_INSTALL+=(openssl)
fi

if ! command -v systemctl &> /dev/null; then
    echo -e "${YELLOW}Installing systemd...${NC}"
    PACKAGES_TO_INSTALL+=(systemd)
fi

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Installing curl...${NC}"
    PACKAGES_TO_INSTALL+=(curl)
fi

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    echo ""
    echo "Installing packages: ${PACKAGES_TO_INSTALL[*]}"
    echo ""
    
    # Wait for any existing apt/dpkg processes to complete
    if ! wait_for_apt_lock; then
        echo -e "${RED}✗${NC} Cannot proceed with package installation"
        exit 1
    fi
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${PACKAGES_TO_INSTALL[@]}"
    echo -e "${GREEN}✓${NC} Required packages installed"
else
    echo -e "${GREEN}✓${NC} All required packages already installed"
fi

echo ""
echo "Checking Docker service..."
if systemctl is-active --quiet docker; then
    echo -e "${GREEN}✓${NC} Docker is running"
else
    echo "Starting Docker service..."
    systemctl start docker
    systemctl enable docker
    sleep 2
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓${NC} Docker started successfully"
    else
        echo -e "${RED}✗${NC} Failed to start Docker"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Optional Dependencies:${NC}"
echo "Node.js and npm are required for:"
echo "  - Building and running the React frontend"
echo "  - Frontend development"
echo ""
echo "If you plan to use the web interface, install them now."
echo "You can also install them later if needed."
echo ""
read -p "Install Node.js and npm? (y/N): " INSTALL_OPTIONAL
INSTALL_OPTIONAL=${INSTALL_OPTIONAL:-N}

if [[ "$INSTALL_OPTIONAL" =~ ^[Yy]$ ]]; then
    OPTIONAL_PACKAGES=()
    
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}Installing nodejs...${NC}"
        OPTIONAL_PACKAGES+=(nodejs)
    fi
    
    if ! command -v npm &> /dev/null; then
        echo -e "${YELLOW}Installing npm...${NC}"
        OPTIONAL_PACKAGES+=(npm)
    fi
    
    if [ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "Installing optional packages: ${OPTIONAL_PACKAGES[*]}"
        
        # Wait for any existing apt/dpkg processes to complete
        if ! wait_for_apt_lock; then
            echo -e "${RED}✗${NC} Cannot proceed with optional package installation"
            echo "You can install Node.js manually later:"
            echo "  sudo apt-get install -y nodejs npm"
        else
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${OPTIONAL_PACKAGES[@]}"
            echo -e "${GREEN}✓${NC} Optional packages installed"
        fi
    else
        echo -e "${GREEN}✓${NC} Optional packages already installed"
    fi
fi

echo ""
echo -e "${GREEN}Dependency installation complete!${NC}"
echo ""
