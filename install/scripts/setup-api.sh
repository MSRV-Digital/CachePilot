#!/bin/bash
#
# CachePilot - API Setup Script
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Setting up CachePilot API..."

BASE_DIR="/opt/cachepilot"
API_DIR="$BASE_DIR/api"
VENV_DIR="$BASE_DIR/venv"
REQUIREMENTS_FILE="$API_DIR/requirements.txt"
SYSTEMD_SERVICE="$BASE_DIR/install/systemd/cachepilot-api.service"
SYSTEMD_TARGET="/etc/systemd/system/cachepilot-api.service"

if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
    echo -e "${RED}✗${NC} Python3 or pip3 not found"
    exit 1
fi

echo -e "${GREEN}✓${NC} Python3 found"

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✓${NC} Virtual environment created"
else
    VENV_PIP="$VENV_DIR/bin/pip"
    if [ ! -f "$VENV_PIP" ]; then
        rm -rf "$VENV_DIR"
        python3 -m venv "$VENV_DIR"
        echo -e "${GREEN}✓${NC} Virtual environment recreated"
    fi
fi

echo "Installing dependencies..."

VENV_PIP="$VENV_DIR/bin/pip"

if [ ! -f "$VENV_PIP" ]; then
    echo -e "${RED}✗${NC} Failed to create virtual environment"
    exit 1
fi

"$VENV_PIP" install --upgrade pip > /dev/null 2>&1 || true

if [ -f "$REQUIREMENTS_FILE" ]; then
    set +e
    "$VENV_PIP" install -r "$REQUIREMENTS_FILE" --disable-pip-version-check > /tmp/pip_install.log 2>&1
    PIP_EXIT_CODE=$?
    set -e
    
    if [ $PIP_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Dependencies installed"
    elif grep -qE "(error|ERROR|failed|FAILED)" /tmp/pip_install.log; then
        echo -e "${RED}✗${NC} Failed to install dependencies"
        tail -n 10 /tmp/pip_install.log
        rm -f /tmp/pip_install.log
        exit 1
    else
        echo -e "${YELLOW}⚠${NC} Dependencies installed with warnings"
    fi
    rm -f /tmp/pip_install.log
else
    echo -e "${RED}✗${NC} Requirements file not found"
    exit 1
fi

CONFIG_FILE="/etc/cachepilot/api.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗${NC} API configuration not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} Configuration found"

API_KEYS_FILE="/etc/cachepilot/api-keys.json"

mkdir -p "/etc/cachepilot"

if [ ! -f "$API_KEYS_FILE" ]; then
    API_KEY=$(openssl rand -hex 32)
    API_KEY_HASH=$(echo -n "$API_KEY" | sha256sum | awk '{print $1}')
    
    cat > "$API_KEYS_FILE" << EOF
{
  "$API_KEY_HASH": {
    "name": "admin",
    "permissions": ["*"],
    "created": $(date +%s.%N),
    "last_used": null,
    "request_count": 0
  }
}
EOF
    
    chmod 600 "$API_KEYS_FILE"
    echo -e "${GREEN}✓${NC} API key generated"
    
    # Save API key to secure temporary file as backup
    KEY_FILE="/root/.cachepilot-api-key"
    echo "$API_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    
    echo ""
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}⚠  SECURITY: API Key Information${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "Your API key: ${GREEN}$API_KEY${NC}"
    echo ""
    echo -e "${RED}IMPORTANT SECURITY NOTES:${NC}"
    echo "  1. Copy this key to a secure password manager NOW"
    echo "  2. Also saved to: $KEY_FILE (for backup)"
    echo "  3. NEVER share installation logs or screenshots publicly"
    echo "  4. Delete key file after copying: rm $KEY_FILE"
    echo "  5. Consider rotating the key after initial setup"
    echo ""
    echo -e "To rotate the key: ${BLUE}cachepilot api key generate <name>${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
else
    chmod 600 "$API_KEYS_FILE"
fi

echo "Setting permissions..."
chmod 600 "$API_KEYS_FILE" 2>/dev/null || true
chmod 640 /etc/cachepilot/*.yaml 2>/dev/null || true
[ -d "$BASE_DIR/data/logs" ] && chmod 755 "$BASE_DIR/data/logs"
[ -d "$BASE_DIR/data/ca" ] && chmod 700 "$BASE_DIR/data/ca"
[ -d "$BASE_DIR/data/ca" ] && find "$BASE_DIR/data/ca" -type f -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
[ -d "$BASE_DIR/data/ca" ] && find "$BASE_DIR/data/ca" -type f -name "*.crt" -exec chmod 644 {} \; 2>/dev/null || true
[ -d "$VENV_DIR" ] && chmod -R 755 "$VENV_DIR"
echo -e "${GREEN}✓${NC} Permissions set"
echo ""

if [ -f "$SYSTEMD_SERVICE" ]; then
    cp "$SYSTEMD_SERVICE" "$SYSTEMD_TARGET"
    systemctl daemon-reload
    systemctl enable cachepilot-api.service
    echo -e "${GREEN}✓${NC} Service installed"
    
    read -p "Start service now? (Y/n): " REPLY
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl start cachepilot-api.service
        sleep 2
        if systemctl is-active --quiet cachepilot-api.service; then
            echo -e "${GREEN}✓${NC} Service running"
            echo ""
            echo -e "${YELLOW}Note:${NC} API keys are cached for 30 seconds."
            echo "      The initial API key is immediately available."
            echo "      New keys generated later may need: cachepilot api restart"
        else
            echo -e "${RED}✗${NC} Service failed to start"
            echo "Logs: journalctl -u cachepilot-api.service -n 50"
        fi
    fi
else
    echo -e "${RED}✗${NC} Service file not found"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ API Setup Complete${NC}"
echo ""
echo "Manage: systemctl {start|stop|restart|status} cachepilot-api"
echo "Logs: journalctl -u cachepilot-api.service -f"
echo ""
