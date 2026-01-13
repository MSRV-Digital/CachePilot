#!/bin/bash
# setup-cron.sh - Configure cron jobs for CachePilot

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Setting up cron jobs..."

# Base directory
BASE_DIR="/opt/cachepilot"
CRON_FILE="/etc/cron.d/cachepilot"
MAINTENANCE_SCRIPT="$BASE_DIR/scripts/cron-maintenance.sh"

# Check if maintenance script exists
if [ ! -f "$MAINTENANCE_SCRIPT" ]; then
    echo -e "${RED}✗${NC} Maintenance script not found: $MAINTENANCE_SCRIPT"
    exit 1
fi

# Make maintenance script executable
chmod +x "$MAINTENANCE_SCRIPT"
echo -e "${GREEN}✓${NC} Made maintenance script executable"

# Create cron job file
cat > "$CRON_FILE" << EOF
# CachePilot Maintenance Tasks
# This file is managed by CachePilot installation
# Changes made here may be overwritten during upgrades

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Run comprehensive maintenance tasks every 6 hours
# This includes: health checks, certificate checks/renewal, metric collection,
# alert management, backups, cleanup tasks, statistics, and monitoring
0 */6 * * * root $MAINTENANCE_SCRIPT >> $BASE_DIR/data/logs/cron-maintenance.log 2>&1

# Quick health check every hour (JSON output for monitoring)
0 * * * * root $BASE_DIR/cli/cachepilot health --json >> $BASE_DIR/data/logs/health-check.log 2>&1

# Certificate expiry check daily (2 AM)
# Note: Certificate renewal is also handled by maintenance script
0 2 * * * root $BASE_DIR/cli/cachepilot check-certs >> $BASE_DIR/data/logs/cert-check.log 2>&1
EOF

chmod 644 "$CRON_FILE"
echo -e "${GREEN}✓${NC} Created cron configuration: $CRON_FILE"

# Restart cron service
if command -v systemctl &> /dev/null; then
    systemctl reload cron 2>/dev/null || systemctl restart cron 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Reloaded cron service"
else
    service cron reload 2>/dev/null || service cron restart 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Restarted cron service"
fi

# Verify cron jobs
echo
echo "Scheduled cron jobs:"
echo "  - Comprehensive maintenance: Every 6 hours"
echo "    (includes: health, certs, metrics, backups, cleanup)"
echo "  - Quick health check: Every hour"
echo "  - Certificate expiry check: Daily (2 AM)"
echo ""
echo "Note: Backup cleanup and log rotation are handled by maintenance script"

echo
echo -e "${GREEN}Cron jobs configured successfully!${NC}"
