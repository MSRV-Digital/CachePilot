#!/usr/bin/env bash
#
# CachePilot - Cronjob Validation Script
#
# Tests all cron commands to ensure they work correctly
# before they are scheduled to run automatically.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_DIR="/opt/cachepilot"
CRON_FILE="/etc/cron.d/cachepilot"
MAINTENANCE_SCRIPT="$BASE_DIR/scripts/cron-maintenance.sh"
CACHEPILOT_CLI="$BASE_DIR/cli/cachepilot"

PASSED=0
FAILED=0

echo "========================================"
echo "CachePilot Cronjob Validation"
echo "========================================"
echo ""

#######################################
# Test a command and report results
# Arguments:
#   $1 - Test name
#   $2 - Command to test
#######################################
test_command() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Testing: $test_name ... "
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Command: $command"
        ((FAILED++))
        return 1
    fi
}

#######################################
# Test a command and show output
# Arguments:
#   $1 - Test name
#   $2 - Command to test
#######################################
test_command_verbose() {
    local test_name="$1"
    local command="$2"
    
    echo ""
    echo -e "${BLUE}Testing: $test_name${NC}"
    echo "Command: $command"
    echo "----------------------------------------"
    
    if eval "$command" 2>&1; then
        echo "----------------------------------------"
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
        echo ""
        return 0
    else
        echo "----------------------------------------"
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
        echo ""
        return 1
    fi
}

# 1. Check if cron file exists
echo -e "${BLUE}[1/6]${NC} Checking cron configuration file..."
if [ -f "$CRON_FILE" ]; then
    echo -e "${GREEN}✓${NC} Cron file exists: $CRON_FILE"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Cron file not found: $CRON_FILE"
    echo "Run: sudo bash $BASE_DIR/install/scripts/setup-cron.sh"
    ((FAILED++))
    exit 1
fi
echo ""

# 2. Check if maintenance script exists and is executable
echo -e "${BLUE}[2/6]${NC} Checking maintenance script..."
if [ -f "$MAINTENANCE_SCRIPT" ]; then
    echo -e "${GREEN}✓${NC} Maintenance script exists"
    if [ -x "$MAINTENANCE_SCRIPT" ]; then
        echo -e "${GREEN}✓${NC} Maintenance script is executable"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} Maintenance script is not executable"
        echo "Run: sudo chmod +x $MAINTENANCE_SCRIPT"
        ((FAILED++))
    fi
else
    echo -e "${RED}✗${NC} Maintenance script not found: $MAINTENANCE_SCRIPT"
    ((FAILED++))
fi
echo ""

# 3. Check if CLI exists
echo -e "${BLUE}[3/6]${NC} Checking CachePilot CLI..."
if [ -f "$CACHEPILOT_CLI" ] && [ -x "$CACHEPILOT_CLI" ]; then
    echo -e "${GREEN}✓${NC} CLI exists and is executable"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} CLI not found or not executable: $CACHEPILOT_CLI"
    ((FAILED++))
fi
echo ""

# 4. Test CLI commands used in cron
echo -e "${BLUE}[4/6]${NC} Testing CLI commands..."
test_command "health command" "$CACHEPILOT_CLI health --json"
test_command "check-certs command" "$CACHEPILOT_CLI check-certs"
echo ""

# 5. Verify cron service status
echo -e "${BLUE}[5/6]${NC} Checking cron service..."
if systemctl is-active --quiet cron 2>/dev/null || service cron status > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Cron service is running"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Cron service is not running"
    echo "Run: sudo systemctl start cron"
    ((FAILED++))
fi
echo ""

# 6. Display current cron configuration
echo -e "${BLUE}[6/6]${NC} Current cron configuration:"
echo "----------------------------------------"
if [ -f "$CRON_FILE" ]; then
    grep -v '^#' "$CRON_FILE" | grep -v '^$' || echo "(no active cron jobs)"
    ((PASSED++))
else
    echo "No cron file found"
    ((FAILED++))
fi
echo "----------------------------------------"
echo ""

# Summary
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo ""
echo -e "Tests Passed: ${GREEN}$PASSED${NC}"
echo -e "Tests Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo ""
    echo "Cronjobs are properly configured and ready to run."
    echo ""
    echo "Scheduled tasks:"
    echo "  - Comprehensive maintenance: Every 6 hours"
    echo "  - Quick health check: Every hour"
    echo "  - Certificate expiry check: Daily at 2 AM"
    echo ""
    echo "You can manually test the maintenance script with:"
    echo "  sudo bash $MAINTENANCE_SCRIPT"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some validation checks failed!${NC}"
    echo ""
    echo "Please fix the issues above before relying on automated tasks."
    echo ""
    exit 1
fi
