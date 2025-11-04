#!/bin/bash
# setup-api.sh - Install and configure the CachePilot API

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Setting up CachePilot API..."

# Base directory
BASE_DIR="/opt/cachepilot"
API_DIR="$BASE_DIR/api"
VENV_DIR="$BASE_DIR/venv"
REQUIREMENTS_FILE="$API_DIR/requirements.txt"
SYSTEMD_SERVICE="$BASE_DIR/install/systemd/cachepilot-api.service"
SYSTEMD_TARGET="/etc/systemd/system/cachepilot-api.service"

# Check if Python3 and pip are available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗${NC} Python3 not found"
    exit 1
fi

if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}✗${NC} pip3 not found"
    exit 1
fi

echo -e "${GREEN}✓${NC} Python3 and pip3 found"

# Create virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✓${NC} Virtual environment created"
else
    echo -e "${YELLOW}⚠${NC} Virtual environment already exists"
    
    # Check if pip exists in the venv, recreate if missing
    VENV_PIP="$VENV_DIR/bin/pip"
    if [ ! -f "$VENV_PIP" ]; then
        echo -e "${YELLOW}⚠${NC} Virtual environment appears corrupted (pip not found)"
        echo "Recreating virtual environment..."
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        echo -e "${GREEN}✓${NC} Virtual environment recreated"
    fi
fi

# Install dependencies using virtual environment's pip directly
echo "Installing Python dependencies..."

# Use the virtual environment's pip directly without activation
VENV_PIP="$VENV_DIR/bin/pip"

if [ ! -f "$VENV_PIP" ]; then
    echo -e "${RED}✗${NC} Failed to create virtual environment properly"
    echo "Please check Python3 installation and try again"
    exit 1
fi

# Upgrade pip (ignore errors if already up to date)
echo "  Upgrading pip..."
"$VENV_PIP" install --upgrade pip > /dev/null 2>&1 || true

# Install requirements
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "  Installing requirements (this may take a minute)..."
    # Temporarily disable exit on error for pip install
    set +e
    "$VENV_PIP" install -r "$REQUIREMENTS_FILE" --disable-pip-version-check > /tmp/pip_install.log 2>&1
    PIP_EXIT_CODE=$?
    set -e
    
    if [ $PIP_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Dependencies installed successfully"
    else
        # Check if it's just warnings or real errors
        if grep -qE "(error|ERROR|failed|FAILED)" /tmp/pip_install.log; then
            echo -e "${RED}✗${NC} Failed to install dependencies"
            echo "Last few lines of installation log:"
            tail -n 10 /tmp/pip_install.log
            rm -f /tmp/pip_install.log
            exit 1
        else
            # Only warnings, continue
            echo -e "${YELLOW}⚠${NC} Dependencies installed with warnings (this is usually okay)"
        fi
    fi
    rm -f /tmp/pip_install.log
else
    echo -e "${RED}✗${NC} Requirements file not found: $REQUIREMENTS_FILE"
    exit 1
fi

# Check if API configuration exists in /etc/cachepilot
CONFIG_FILE="/etc/cachepilot/api.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗${NC} API configuration not found: $CONFIG_FILE"
    echo "The installation script should have copied configuration files to /etc/cachepilot/"
    echo "Please run the main installation script first: $BASE_DIR/install/install.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} API configuration found: $CONFIG_FILE"

# Generate API key if not exists in /etc/cachepilot
API_KEYS_FILE="/etc/cachepilot/api-keys.json"

# Ensure the directory exists
mkdir -p "/etc/cachepilot"

if [ ! -f "$API_KEYS_FILE" ]; then
    echo "Generating initial API key..."
    
    # Generate a random API key
    API_KEY=$(openssl rand -hex 32)
    
    # Create API keys file
    cat > "$API_KEYS_FILE" << EOF
{
  "keys": {
    "$API_KEY": {
      "name": "admin",
      "created": "$(date -Iseconds)",
      "permissions": ["read", "write", "admin"]
    }
  }
}
EOF
    
    chmod 600 "$API_KEYS_FILE"
    echo -e "${GREEN}✓${NC} API key generated"
    echo
    echo "================================================"
    echo "Your API Key (save this securely):"
    echo "$API_KEY"
    echo "================================================"
    echo
else
    echo -e "${YELLOW}⚠${NC} API keys file already exists"
    # Verify permissions on existing keys file
    chmod 600 "$API_KEYS_FILE"
fi

# Verify and set secure file permissions
echo "Verifying file permissions..."

# API keys file - must be 600 (rw-------)
if [ -f "$API_KEYS_FILE" ]; then
    chmod 600 "$API_KEYS_FILE"
    echo -e "${GREEN}✓${NC} API keys file permissions: 600"
fi

# Configuration files in /etc/cachepilot - should be 640 (rw-r-----)
CONFIG_FILES=(
    "/etc/cachepilot/api.yaml"
    "/etc/cachepilot/system.yaml"
    "/etc/cachepilot/frontend.yaml"
    "/etc/cachepilot/logging-config.yaml"
    "/etc/cachepilot/monitoring-config.yaml"
)

for config_file in "${CONFIG_FILES[@]}"; do
    if [ -f "$config_file" ]; then
        chmod 640 "$config_file"
        echo -e "${GREEN}✓${NC} $(basename $config_file) permissions: 640"
    fi
done

# Ensure log directories have proper permissions
if [ -d "$BASE_DIR/data/logs" ]; then
    chmod 755 "$BASE_DIR/data/logs"
    echo -e "${GREEN}✓${NC} Log directory permissions: 755"
fi

# Ensure CA directory has restricted permissions
if [ -d "$BASE_DIR/data/ca" ]; then
    chmod 700 "$BASE_DIR/data/ca"
    echo -e "${GREEN}✓${NC} CA directory permissions: 700"
    
    # Secure all certificate files
    find "$BASE_DIR/data/ca" -type f -name "*.key" -exec chmod 600 {} \;
    find "$BASE_DIR/data/ca" -type f -name "*.crt" -exec chmod 644 {} \;
    echo -e "${GREEN}✓${NC} Certificate files secured"
fi

# Verify Python venv permissions
if [ -d "$VENV_DIR" ]; then
    chmod -R 755 "$VENV_DIR"
    echo -e "${GREEN}✓${NC} Virtual environment permissions verified"
fi

echo -e "${GREEN}✓${NC} All file permissions verified and secured"
echo

# Install systemd service
if [ -f "$SYSTEMD_SERVICE" ]; then
    echo "Installing systemd service..."
    cp "$SYSTEMD_SERVICE" "$SYSTEMD_TARGET"
    
    # Reload systemd
    systemctl daemon-reload
    echo -e "${GREEN}✓${NC} Systemd service installed"
    
    # Enable service
    systemctl enable cachepilot-api.service
    echo -e "${GREEN}✓${NC} Service enabled"
    
    # Ask if user wants to start now
    read -p "Start API service now? (Y/n): " -r REPLY
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl start cachepilot-api.service
        echo -e "${GREEN}✓${NC} Service started"
        
        # Wait a moment and check status
        sleep 2
        if systemctl is-active --quiet cachepilot-api.service; then
            echo -e "${GREEN}✓${NC} Service is running"
        else
            echo -e "${RED}✗${NC} Service failed to start"
            echo "Check logs with: journalctl -u cachepilot-api.service -n 50"
        fi
    else
        echo "You can start the service later with: systemctl start cachepilot-api.service"
    fi
else
    echo -e "${RED}✗${NC} Systemd service file not found: $SYSTEMD_SERVICE"
    exit 1
fi

echo
echo -e "${GREEN}API setup completed successfully!${NC}"
echo
echo "Service management:"
echo "  Start:   systemctl start cachepilot-api.service"
echo "  Stop:    systemctl stop cachepilot-api.service"
echo "  Restart: systemctl restart cachepilot-api.service"
echo "  Status:  systemctl status cachepilot-api.service"
echo "  Logs:    journalctl -u cachepilot-api.service -f"
