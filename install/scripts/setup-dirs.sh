#!/bin/bash
# setup-dirs.sh - Create directory structure from configuration

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "Setting up directory structure..."

# Base directory
BASE_DIR="/opt/cachepilot"
CONFIG_FILE="$BASE_DIR/config/system.yaml"

# Function to parse YAML and get value
get_yaml_value() {
    local key=$1
    local file=$2
    
    # Try using yq if available
    if command -v yq &> /dev/null; then
        yq eval ".${key}" "$file" 2>/dev/null || echo ""
    else
        # Fallback to grep/sed
        grep "^  ${key}:" "$file" | sed 's/.*: *//;s/"//g;s/'"'"'//g' | head -1
    fi
}

# Load paths from configuration
load_paths_from_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}✗${NC} Configuration file not found: $CONFIG_FILE"
        echo "Using default paths..."
        return 1
    fi
    
    echo "Loading paths from configuration..."
    
    # Load paths from system.yaml (under paths: section)
    TENANTS_DIR=$(get_yaml_value "paths.tenants_dir" "$CONFIG_FILE")
    CA_DIR=$(get_yaml_value "paths.ca_dir" "$CONFIG_FILE")
    BACKUPS_DIR=$(get_yaml_value "paths.backups_dir" "$CONFIG_FILE")
    LOGS_DIR=$(get_yaml_value "paths.logs_dir" "$CONFIG_FILE")
    
    # Use defaults if not found in config
    TENANTS_DIR=${TENANTS_DIR:-/var/cachepilot/tenants}
    CA_DIR=${CA_DIR:-/var/cachepilot/ca}
    BACKUPS_DIR=${BACKUPS_DIR:-/var/cachepilot/backups}
    LOGS_DIR=${LOGS_DIR:-/var/log/cachepilot}
    
    echo -e "${GREEN}✓${NC} Paths loaded from configuration"
}

# Function to create directory with proper permissions
create_dir() {
    local dir=$1
    local description=$2
    local perms=${3:-755}
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$perms" "$dir"
        echo -e "${GREEN}✓${NC} Created $description: $dir (perms: $perms)"
    else
        echo -e "${YELLOW}⚠${NC} Already exists $description: $dir"
        # Still set permissions on existing directories
        chmod "$perms" "$dir"
    fi
}

# Load paths from configuration
load_paths_from_config

# Create main application directories (/opt/cachepilot)
echo
echo "Creating application directories in $BASE_DIR..."
create_dir "$BASE_DIR" "base directory" 755
create_dir "$BASE_DIR/cli" "CLI directory" 755
create_dir "$BASE_DIR/cli/lib" "CLI libraries" 755
create_dir "$BASE_DIR/api" "API directory" 755
create_dir "$BASE_DIR/api/routes" "API routes" 755
create_dir "$BASE_DIR/api/services" "API services" 755
create_dir "$BASE_DIR/api/utils" "API utilities" 755
create_dir "$BASE_DIR/api/middleware" "API middleware" 755
create_dir "$BASE_DIR/frontend" "frontend directory" 755
create_dir "$BASE_DIR/config" "configuration directory" 750
create_dir "$BASE_DIR/install" "installation directory" 755
create_dir "$BASE_DIR/install/scripts" "installation scripts" 755
create_dir "$BASE_DIR/install/systemd" "systemd services" 755
create_dir "$BASE_DIR/scripts" "utility scripts" 755
create_dir "$BASE_DIR/docs" "documentation" 755

# Create FHS-compliant configuration directory (/etc/cachepilot)
echo
echo "Creating configuration directory (FHS-compliant)..."
create_dir "/etc/cachepilot" "system configuration directory" 755

# Create FHS-compliant data directories (/var/cachepilot)
echo
echo "Creating data directories (FHS-compliant)..."
create_dir "$TENANTS_DIR" "tenants data directory" 750
create_dir "$CA_DIR" "certificate authority directory" 700
create_dir "$BACKUPS_DIR" "backups directory" 750

# Create FHS-compliant log directory (/var/log/cachepilot)
echo
echo "Creating log directory (FHS-compliant)..."
create_dir "$LOGS_DIR" "logs directory" 755

# Create log files with proper permissions
echo
echo "Initializing log files..."
touch "$LOGS_DIR/cachepilot.log"
touch "$LOGS_DIR/audit.log"
touch "$LOGS_DIR/metrics.log"
chmod 640 "$LOGS_DIR"/*.log
echo -e "${GREEN}✓${NC} Log files initialized"

# Create legacy data directory for backward compatibility (if needed)
# This allows existing scripts to work during transition
if [ -d "$BASE_DIR/data" ]; then
    echo
    echo -e "${YELLOW}⚠${NC} Legacy data directory exists at $BASE_DIR/data"
    echo "FHS-compliant directory structure:"
    echo "  - Tenants: $TENANTS_DIR"
    echo "  - CA: $CA_DIR"
    echo "  - Backups: $BACKUPS_DIR"
    echo "  - Logs: $LOGS_DIR"
fi

echo
echo -e "${GREEN}Directory structure created successfully!${NC}"
