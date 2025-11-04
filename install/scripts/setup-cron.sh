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

# Run maintenance tasks every 6 hours
0 */6 * * * root $MAINTENANCE_SCRIPT >> $BASE_DIR/data/logs/cron-maintenance.log 2>&1

# Health check every hour
0 * * * * root $BASE_DIR/cli/cachepilot health check-system --quiet >> $BASE_DIR/data/logs/health-check.log 2>&1

# Backup rotation weekly (Sunday at 3 AM)
0 3 * * 0 root $BASE_DIR/cli/cachepilot backup cleanup --days 30 >> $BASE_DIR/data/logs/backup-cleanup.log 2>&1

# Certificate expiry check daily (2 AM)
0 2 * * * root $BASE_DIR/cli/cachepilot certs check-expiry --quiet >> $BASE_DIR/data/logs/cert-check.log 2>&1

# Log rotation monthly (first day at 1 AM)
0 1 1 * * root $BASE_DIR/cli/cachepilot logs rotate >> $BASE_DIR/data/logs/log-rotation.log 2>&1
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
echo "  - Maintenance tasks: Every 6 hours"
echo "  - Health checks: Every hour"
echo "  - Backup cleanup: Weekly (Sunday 3 AM)"
echo "  - Certificate check: Daily (2 AM)"
echo "  - Log rotation: Monthly (1st day 1 AM)"

echo
echo -e "${GREEN}Cron jobs configured successfully!${NC}"
