#!/bin/bash
# setup-logrotate.sh - Configure log rotation for CachePilot

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Setting up log rotation..."

LOGROTATE_FILE="/etc/logrotate.d/cachepilot"

# Create logrotate configuration
cat > "$LOGROTATE_FILE" << 'EOF'
/var/log/cachepilot/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload cachepilot-api.service > /dev/null 2>&1 || true
    endscript
}
EOF

# Set permissions
chmod 644 "$LOGROTATE_FILE"

echo -e "${GREEN}✓${NC} Log rotation configured: $LOGROTATE_FILE"

# Test configuration
if command -v logrotate &> /dev/null; then
    if logrotate -d "$LOGROTATE_FILE" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Log rotation configuration validated"
    else
        echo -e "${YELLOW}⚠${NC} Log rotation validation failed, but configuration is installed"
    fi
else
    echo -e "${YELLOW}⚠${NC} logrotate not found - configuration installed but cannot be validated"
fi

echo ""
echo "Log rotation settings:"
echo "  - Logs rotated: daily"
echo "  - Keep: 30 days"
echo "  - Compression: enabled (delayed)"
echo "  - Files: /var/log/cachepilot/*.log"
echo ""
