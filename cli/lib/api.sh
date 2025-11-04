#!/usr/bin/env bash
#
# CachePilot - API Management Library
#
# Manages the REST API service lifecycle, API key generation, and service monitoring.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

API_SERVICE="cachepilot-api"
API_DIR="${CACHEPILOT_DIR}/api"
API_KEY_FILE="${CONFIG_DIR:-/etc/cachepilot}/api-keys.json"

api_start() {
    log_info "api" "Starting API service"
    
    if ! systemctl is-active --quiet ${API_SERVICE}; then
        systemctl start ${API_SERVICE}
        sleep 2
        
        if systemctl is-active --quiet ${API_SERVICE}; then
            success "API service started successfully"
            echo "  Access API: http://localhost:8000"
            echo "  Documentation: http://localhost:8000/docs"
        else
            error "Failed to start API service"
        fi
    else
        warn "API service is already running"
        api_status
    fi
}

api_stop() {
    log_info "api" "Stopping API service"
    
    if systemctl is-active --quiet ${API_SERVICE}; then
        systemctl stop ${API_SERVICE}
        success "API service stopped"
    else
        warn "API service is not running"
    fi
}

api_restart() {
    log_info "api" "Restarting API service"
    systemctl restart ${API_SERVICE}
    sleep 2
    
    if systemctl is-active --quiet ${API_SERVICE}; then
        success "API service restarted successfully"
        echo "  Access API: http://localhost:8000"
    else
        error "API service failed to restart"
    fi
}

api_status() {
    log_info "api" "Checking API service status"
    
    if systemctl is-enabled --quiet ${API_SERVICE} 2>/dev/null; then
        local enabled="enabled"
    else
        local enabled="disabled"
    fi
    
    if systemctl is-active --quiet ${API_SERVICE}; then
        echo ""
        echo -e "API Service Status: \033[0;32mRUNNING\033[0m (${enabled})"
        echo ""
        echo "Service Details:"
        echo "  Status: Active"
        echo "  URL: http://localhost:8000"
        echo "  Documentation: http://localhost:8000/docs"
        echo "  ReDoc: http://localhost:8000/redoc"
        echo ""
        
        local key_count=$(cat "${API_KEY_FILE}" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
        echo "API Keys: ${key_count} active"
        echo ""
        
        systemctl status ${API_SERVICE} --no-pager -l | head -15
    else
        echo ""
        echo -e "API Service Status: \033[0;31mSTOPPED\033[0m (${enabled})"
        echo ""
        echo "To start: cachepilot api start"
        echo ""
    fi
}

api_logs() {
    local lines="${1:-50}"
    log_info "api" "Displaying API service logs (last ${lines} lines)"
    
    echo ""
    journalctl -u ${API_SERVICE} -n ${lines} --no-pager
}

api_key_generate() {
    local key_name="$1"
    
    if [ -z "${key_name}" ]; then
        error "Usage: cachepilot api key generate <name>"
    fi
    
    log_info "api" "Generating new API key" "" "{\"key_name\":\"${key_name}\"}"
    
    if [ ! -d "${CACHEPILOT_DIR}/venv" ] && [ ! -d "${CACHEPILOT_DIR}/api" ]; then
        error "API not installed. Run install.sh to install the API."
    fi
    
    mkdir -p "$(dirname "${API_KEY_FILE}")"
    if [ ! -f "${API_KEY_FILE}" ]; then
        echo "{}" > "${API_KEY_FILE}"
    fi
    
    if [ -d "${CACHEPILOT_DIR}/venv" ] && [ -f "${CACHEPILOT_DIR}/venv/bin/python" ]; then
        local PYTHON="${CACHEPILOT_DIR}/venv/bin/python"
    else
        local PYTHON="python3"
    fi
    
    cd "${CACHEPILOT_DIR}"
    local API_KEY=$($PYTHON -c "
import sys
sys.path.insert(0, '${CACHEPILOT_DIR}')
from api.auth import api_key_manager
key = api_key_manager.generate_key('${key_name}', ['*'])
print(key)
" 2>/dev/null)
    
    if [ -z "${API_KEY}" ]; then
        error "Failed to generate API key"
    fi
    
    echo ""
    echo "API Key Generated Successfully!"
    echo "================================"
    echo ""
    echo "Key Name: ${key_name}"
    echo "API Key:  ${API_KEY}"
    echo ""
    echo "Store this key securely. It will not be shown again."
    echo ""
    echo "To use this key, include it in the X-API-Key header:"
    echo "  curl -H 'X-API-Key: ${API_KEY}' http://localhost:8000/api/v1/tenants"
    echo ""
    
    log_audit "system" "api_key_generated" "system" "{\"key_name\":\"${key_name}\"}"
}

api_key_list() {
    log_info "api" "Listing API keys"
    
    if [ ! -f "${API_KEY_FILE}" ]; then
        echo "No API keys found. Generate one with: cachepilot api key generate <name>"
        return 0
    fi
    
    echo ""
    echo "CachePilot API Keys"
    echo "==================="
    echo ""
    
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import sys
from datetime import datetime

try:
    with open('${API_KEY_FILE}', 'r') as f:
        keys = json.load(f)
    
    if not keys:
        print('No API keys found.')
        sys.exit(0)
    
    print('Key Name          Created                  Last Used                Requests')
    print('----------------- ------------------------ ------------------------ --------')
    for key_hash, data in keys.items():
        name = data.get('name', 'unknown').ljust(17)
        created = datetime.fromtimestamp(data.get('created', 0)).strftime('%Y-%m-%d %H:%M:%S')
        last_used = data.get('last_used')
        if last_used:
            last_used = datetime.fromtimestamp(last_used).strftime('%Y-%m-%d %H:%M:%S')
        else:
            last_used = 'Never'.ljust(24)
        requests = str(data.get('request_count', 0))
        print(f'{name} {created} {last_used} {requests}')
    
    print('')
    print('Note: Actual API key values are not shown (only hashes are stored).')
    print('      If you lost a key, generate a new one with: cachepilot api key generate <name>')
    print('')
except Exception as e:
    print(f'Error reading API keys: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1
    else
        error "Python 3 is required to list API keys"
    fi
}

api_key_revoke() {
    local key_name="$1"
    
    if [ -z "${key_name}" ]; then
        error "Usage: cachepilot api key revoke <name>"
    fi
    
    log_info "api" "Revoking API key" "" "{\"key_name\":\"${key_name}\"}"
    
    if [ ! -f "${API_KEY_FILE}" ]; then
        error "No API keys found"
    fi
    
    local temp_file="${API_KEY_FILE}.tmp"
    
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import sys

try:
    with open('${API_KEY_FILE}', 'r') as f:
        keys = json.load(f)
    
    found = False
    new_keys = {}
    for key_hash, data in keys.items():
        if data.get('name') != '${key_name}':
            new_keys[key_hash] = data
        else:
            found = True
    
    if found:
        with open('${temp_file}', 'w') as f:
            json.dump(new_keys, f, indent=2)
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(2)
"
        local result=$?
        
        if [ $result -eq 0 ]; then
            mv "${temp_file}" "${API_KEY_FILE}"
            success "API key '${key_name}' revoked successfully"
            echo "The key will be automatically invalidated within 30 seconds."
            log_audit "system" "api_key_revoked" "system" "{\"key_name\":\"${key_name}\"}"
        elif [ $result -eq 1 ]; then
            error "API key '${key_name}' not found"
        else
            error "Failed to revoke API key"
        fi
    else
        error "Python 3 is required for key revocation"
    fi
}

api_command() {
    local subcommand="$1"
    shift
    
    case "$subcommand" in
        start)
            api_start
            ;;
        stop)
            api_stop
            ;;
        restart)
            api_restart
            ;;
        status)
            api_status
            ;;
        logs)
            local lines="${1:-50}"
            api_logs "$lines"
            ;;
        key)
            [[ $# -lt 1 ]] && error "Usage: cachepilot api key <generate|list|revoke> [args]"
            local key_action="$1"
            shift
            
            case "$key_action" in
                generate)
                    [[ $# -lt 1 ]] && error "Usage: cachepilot api key generate <name>"
                    api_key_generate "$1"
                    ;;
                list)
                    api_key_list
                    ;;
                revoke)
                    [[ $# -lt 1 ]] && error "Usage: cachepilot api key revoke <name>"
                    api_key_revoke "$1"
                    ;;
                *)
                    error "Unknown api key command: $key_action"
                    ;;
            esac
            ;;
        *)
            error "Unknown api command: $subcommand"
            echo "Usage: cachepilot api <start|stop|restart|status|logs|key>"
            ;;
    esac
}

export -f api_command
export -f api_start
export -f api_stop
export -f api_restart
export -f api_status
export -f api_logs
export -f api_key_generate
export -f api_key_list
export -f api_key_revoke
