#!/usr/bin/env bash
#
# CachePilot - Tenant Migration Script for Dual-Mode Support
#
# Migrates existing tenants from legacy PORT configuration to new
# security_mode-based configuration with PORT_TLS and PORT_PLAIN.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.2.0-beta
# License: MIT
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "CachePilot Tenant Migration (v2.2)"
echo "========================================"
echo ""

# Load configuration
CONFIG_FILE="/etc/cachepilot/system.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Configuration file not found: $CONFIG_FILE${NC}" >&2
    exit 1
fi

# Simple YAML parser for tenants_dir
TENANTS_DIR=$(grep "tenants_dir:" "$CONFIG_FILE" | awk '{print $2}' || echo "/var/cachepilot/tenants")

if [ ! -d "$TENANTS_DIR" ]; then
    echo "No tenants directory found: $TENANTS_DIR"
    exit 0
fi

MIGRATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

echo "Migrating tenants in: $TENANTS_DIR"
echo ""

for tenant_dir in "$TENANTS_DIR"/*; do
    if [ ! -d "$tenant_dir" ]; then
        continue
    fi
    
    tenant=$(basename "$tenant_dir")
    config_file="$tenant_dir/config.env"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠${NC} Skipping $tenant: config.env not found"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # Check if already migrated
    if grep -q "^SECURITY_MODE=" "$config_file" 2>/dev/null; then
        echo -e "${BLUE}→${NC} Already migrated: $tenant"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    echo -e "${BLUE}Migrating tenant: $tenant${NC}"
    
    # Read current PORT value
    if grep -q "^PORT=" "$config_file"; then
        CURRENT_PORT=$(grep "^PORT=" "$config_file" | cut -d= -f2)
        
        # Migrate: PORT -> PORT_TLS
        if sed -i.backup "s/^PORT=/PORT_TLS=/" "$config_file" 2>/dev/null; then
            # Add new fields
            {
                echo ""
                echo "# Dual-Mode Support (added during v2.2 migration)"
                echo "SECURITY_MODE=tls-only"
                echo "PORT_PLAIN="
            } >> "$config_file"
            
            # Remove backup file if migration succeeded
            rm -f "$config_file.backup"
            
            echo -e "  ${GREEN}✓${NC} Migrated: PORT=$CURRENT_PORT → PORT_TLS=$CURRENT_PORT"
            echo -e "  ${GREEN}✓${NC} Added: SECURITY_MODE=tls-only"
            echo -e "  ${GREEN}✓${NC} Added: PORT_PLAIN= (empty, TLS-only mode)"
            ((MIGRATED_COUNT++))
        else
            echo -e "  ${RED}✗${NC} Failed to migrate config file"
            ((FAILED_COUNT++))
        fi
    else
        # No PORT field found - might be corrupted
        echo -e "  ${YELLOW}⚠${NC} No PORT field found, adding defaults"
        
        # Add new fields with empty values (admin will need to fix)
        {
            echo ""
            echo "# Dual-Mode Support (added during v2.2 migration - NEEDS CONFIGURATION)"
            echo "SECURITY_MODE=tls-only"
            echo "PORT_TLS="
            echo "PORT_PLAIN="
        } >> "$config_file"
        
        echo -e "  ${YELLOW}⚠${NC} Added security fields, but PORT_TLS is empty - tenant may need reconfiguration"
        ((FAILED_COUNT++))
    fi
done

echo ""
echo "========================================"
echo -e "${GREEN}Migration Complete${NC}"
echo "========================================"
echo "Migrated:  $MIGRATED_COUNT tenant(s)"
echo "Skipped:   $SKIPPED_COUNT tenant(s) (already migrated)"

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Warnings:  $FAILED_COUNT tenant(s) (may need manual review)${NC}"
fi

echo ""
echo "All existing tenants remain in TLS-only mode (default, most secure)"
echo "To enable dual-mode or plain-text for a tenant:"
echo "  cachepilot set-access <tenant> dual-mode"
echo "  cachepilot set-access <tenant> plain-only"
echo ""

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Note: Some tenants may need manual review. Check:${NC}"
    echo "  /var/cachepilot/tenants/<tenant>/config.env"
    echo ""
    exit 1
fi

exit 0
