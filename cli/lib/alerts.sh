#!/usr/bin/env bash
#
# CachePilot - Alert and Notification Library
#
# Alert generation, storage, notification (email/webhook), and alert lifecycle
# management with history tracking.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

ALERTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERTS_DIR="${LOGS_DIR:-/var/log/cachepilot}/alerts"
ALERTS_HISTORY="${ALERTS_DIR}/history.json"
MONITORING_CONFIG="/etc/cachepilot/monitoring-config.yaml"

ALERT_SEVERITY_INFO="info"
ALERT_SEVERITY_WARNING="warning"
ALERT_SEVERITY_CRITICAL="critical"

EMAIL_ENABLED=${EMAIL_ENABLED:-false}
EMAIL_FROM=${EMAIL_FROM:-"cachepilot@localhost"}
EMAIL_TO=${EMAIL_TO:-""}
WEBHOOK_ENABLED=${WEBHOOK_ENABLED:-false}
WEBHOOK_URL=${WEBHOOK_URL:-""}

alert_init() {
    log_debug "alerts" "Initializing alert system"
    
    if [ ! -d "${ALERTS_DIR}" ]; then
        mkdir -p "${ALERTS_DIR}"
        log_info "alerts" "Created alerts directory"
    fi
    
    if [ ! -f "${ALERTS_HISTORY}" ]; then
        echo "[]" > "${ALERTS_HISTORY}"
        log_info "alerts" "Created alerts history file"
    fi
    
    if [ -f "${MONITORING_CONFIG}" ]; then
        if grep -q "email_enabled:" "${MONITORING_CONFIG}"; then
            EMAIL_ENABLED=$(grep "email_enabled:" "${MONITORING_CONFIG}" | awk '{print $2}')
        fi
        if grep -q "email_to:" "${MONITORING_CONFIG}"; then
            EMAIL_TO=$(grep "email_to:" "${MONITORING_CONFIG}" | awk '{print $2}')
        fi
        if grep -q "webhook_enabled:" "${MONITORING_CONFIG}"; then
            WEBHOOK_ENABLED=$(grep "webhook_enabled:" "${MONITORING_CONFIG}" | awk '{print $2}')
        fi
        if grep -q "webhook_url:" "${MONITORING_CONFIG}"; then
            WEBHOOK_URL=$(grep "webhook_url:" "${MONITORING_CONFIG}" | awk '{print $2}')
        fi
    fi
    
    log_info "alerts" "Alert system initialized" "" "{\"email_enabled\":${EMAIL_ENABLED},\"webhook_enabled\":${WEBHOOK_ENABLED}}"
    return 0
}

alert_create() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local tenant="${4:-}"
    
    if [ "${severity}" != "${ALERT_SEVERITY_INFO}" ] && \
       [ "${severity}" != "${ALERT_SEVERITY_WARNING}" ] && \
       [ "${severity}" != "${ALERT_SEVERITY_CRITICAL}" ]; then
        log_error "alerts" "Invalid alert severity: ${severity}"
        return 1
    fi
    
    if [ -z "${title}" ] || [ -z "${message}" ]; then
        log_error "alerts" "Alert title and message are required"
        return 1
    fi
    
    alert_init >/dev/null 2>&1
    
    local alert_id="alert_$(date +%s)_$$_${RANDOM}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local alert_json="{"
    alert_json+="\"id\":\"${alert_id}\","
    alert_json+="\"severity\":\"${severity}\","
    alert_json+="\"title\":\"${title//\"/\\\"}\","
    alert_json+="\"message\":\"${message//\"/\\\"}\","
    alert_json+="\"timestamp\":\"${timestamp}\","
    alert_json+="\"resolved\":false,"
    alert_json+="\"resolved_at\":null"
    
    if [ -n "${tenant}" ]; then
        alert_json+=",\"tenant\":\"${tenant}\""
    else
        alert_json+=",\"tenant\":null"
    fi
    
    alert_json+="}"
    
    if [ -f "${ALERTS_HISTORY}" ]; then
        local existing=$(cat "${ALERTS_HISTORY}")
        
        if [ "${existing}" = "[]" ]; then
            echo "[${alert_json}]" > "${ALERTS_HISTORY}"
        else
            local updated="${existing%]}"
            if [ "${updated: -1}" != "[" ]; then
                updated="${updated},"
            fi
            echo "${updated}${alert_json}]" > "${ALERTS_HISTORY}"
        fi
    fi
    
    log_warn "alerts" "Alert created: ${title}" "${tenant}" "{\"alert_id\":\"${alert_id}\",\"severity\":\"${severity}\"}"
    
    if [ "${severity}" = "${ALERT_SEVERITY_CRITICAL}" ] || [ "${severity}" = "${ALERT_SEVERITY_WARNING}" ]; then
        if [ "${EMAIL_ENABLED}" = "true" ]; then
            alert_send_email "${alert_id}" &
        fi
        
        if [ "${WEBHOOK_ENABLED}" = "true" ] && [ -n "${WEBHOOK_URL}" ]; then
            alert_send_webhook "${alert_id}" "${WEBHOOK_URL}" &
        fi
    fi
    
    echo "${alert_id}"
    return 0
}

alert_send_email() {
    local alert_id="$1"
    
    if [ -z "${alert_id}" ]; then
        log_error "alerts" "Alert ID required for email notification"
        return 1
    fi
    
    if [ "${EMAIL_ENABLED}" != "true" ] || [ -z "${EMAIL_TO}" ]; then
        log_debug "alerts" "Email notifications not configured"
        return 1
    fi
    
    local alert=$(alert_get "${alert_id}")
    if [ -z "${alert}" ]; then
        log_error "alerts" "Alert not found: ${alert_id}"
        return 1
    fi
    
    local severity=$(echo "${alert}" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4)
    local title=$(echo "${alert}" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
    local message=$(echo "${alert}" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    local timestamp=$(echo "${alert}" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
    local tenant=$(echo "${alert}" | grep -o '"tenant":"[^"]*"' | cut -d'"' -f4)
    
    local email_body="CachePilot Alert

Severity: ${severity}
Alert ID: ${alert_id}
Time: ${timestamp}
Tenant: ${tenant:-N/A}

Title: ${title}

Message:
${message}

---
This is an automated alert from CachePilot.
"
    
    if command -v mail >/dev/null 2>&1; then
        echo "${email_body}" | mail -s "[CachePilot] ${severity}: ${title}" -r "${EMAIL_FROM}" "${EMAIL_TO}"
        local result=$?
        
        if [ ${result} -eq 0 ]; then
            log_info "alerts" "Email notification sent" "" "{\"alert_id\":\"${alert_id}\",\"to\":\"${EMAIL_TO}\"}"
            return 0
        else
            log_error "alerts" "Failed to send email notification" "" "{\"alert_id\":\"${alert_id}\",\"error_code\":${result}}"
            return 1
        fi
    else
        log_warn "alerts" "mail command not available, cannot send email"
        return 1
    fi
}

alert_send_webhook() {
    local alert_id="$1"
    local webhook_url="$2"
    
    if [ -z "${alert_id}" ] || [ -z "${webhook_url}" ]; then
        log_error "alerts" "Alert ID and webhook URL required"
        return 1
    fi
    
    local alert=$(alert_get "${alert_id}")
    if [ -z "${alert}" ]; then
        log_error "alerts" "Alert not found: ${alert_id}"
        return 1
    fi
    
    if command -v curl >/dev/null 2>&1; then
        local response=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "${alert}" \
            "${webhook_url}" 2>&1)
        local result=$?
        
        if [ ${result} -eq 0 ]; then
            log_info "alerts" "Webhook notification sent" "" "{\"alert_id\":\"${alert_id}\",\"url\":\"${webhook_url}\"}"
            return 0
        else
            log_error "alerts" "Failed to send webhook notification" "" "{\"alert_id\":\"${alert_id}\",\"error\":\"${response}\"}"
            return 1
        fi
    else
        log_warn "alerts" "curl command not available, cannot send webhook"
        return 1
    fi
}

alert_resolve() {
    local alert_id="$1"
    
    if [ -z "${alert_id}" ]; then
        log_error "alerts" "Alert ID required"
        return 1
    fi
    
    if [ ! -f "${ALERTS_HISTORY}" ]; then
        log_error "alerts" "Alert history not found"
        return 1
    fi
    
    if ! grep -q "\"id\":\"${alert_id}\"" "${ALERTS_HISTORY}"; then
        log_error "alerts" "Alert not found: ${alert_id}"
        return 1
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local temp_file="${ALERTS_HISTORY}.tmp"
    
    python3 -c "
import json
import sys

try:
    with open('${ALERTS_HISTORY}', 'r') as f:
        alerts = json.load(f)
    
    for alert in alerts:
        if alert['id'] == '${alert_id}':
            alert['resolved'] = True
            alert['resolved_at'] = '${timestamp}'
            break
    
    with open('${temp_file}', 'w') as f:
        json.dump(alerts, f, indent=2)
    
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        mv "${temp_file}" "${ALERTS_HISTORY}"
        log_info "alerts" "Alert resolved" "" "{\"alert_id\":\"${alert_id}\"}"
        return 0
    else
        sed -i.bak "s/\"id\":\"${alert_id}\",\"severity\":\([^,]*\),\"title\":\([^,]*\),\"message\":\([^,]*\),\"timestamp\":\([^,]*\),\"resolved\":false,\"resolved_at\":null/\"id\":\"${alert_id}\",\"severity\":\1,\"title\":\2,\"message\":\3,\"timestamp\":\4,\"resolved\":true,\"resolved_at\":\"${timestamp}\"/g" "${ALERTS_HISTORY}"
        
        log_info "alerts" "Alert resolved (fallback method)" "" "{\"alert_id\":\"${alert_id}\"}"
        return 0
    fi
}

alert_list() {
    local severity_filter="${1:-}"
    local tenant_filter="${2:-}"
    local resolved_filter="${3:-all}"
    
    if [ ! -f "${ALERTS_HISTORY}" ]; then
        echo "[]"
        return 0
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import sys

try:
    with open('${ALERTS_HISTORY}', 'r') as f:
        alerts = json.load(f)
    
    filtered = alerts
    
    if '${severity_filter}':
        filtered = [a for a in filtered if a.get('severity') == '${severity_filter}']
    
    if '${tenant_filter}':
        filtered = [a for a in filtered if a.get('tenant') == '${tenant_filter}']
    
    if '${resolved_filter}' == 'true':
        filtered = [a for a in filtered if a.get('resolved') == True]
    elif '${resolved_filter}' == 'false':
        filtered = [a for a in filtered if a.get('resolved') == False]
    
    print(json.dumps(filtered, indent=2))
    sys.exit(0)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi
    
    cat "${ALERTS_HISTORY}"
    return 0
}

alert_get() {
    local alert_id="$1"
    
    if [ -z "${alert_id}" ]; then
        return 1
    fi
    
    if [ ! -f "${ALERTS_HISTORY}" ]; then
        return 1
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
import sys

try:
    with open('${ALERTS_HISTORY}', 'r') as f:
        alerts = json.load(f)
    
    for alert in alerts:
        if alert['id'] == '${alert_id}':
            print(json.dumps(alert))
            sys.exit(0)
    
    sys.exit(1)
except Exception as e:
    sys.exit(1)
" 2>/dev/null
        
        return $?
    fi
    
    if grep -q "\"id\":\"${alert_id}\"" "${ALERTS_HISTORY}"; then
        grep -A 10 "\"id\":\"${alert_id}\"" "${ALERTS_HISTORY}" | head -n 8
        return 0
    fi
    
    return 1
}

alert_cleanup() {
    local days_to_keep="${1:-30}"
    
    if [ ! -f "${ALERTS_HISTORY}" ]; then
        return 0
    fi
    
    log_info "alerts" "Cleaning up alerts older than ${days_to_keep} days"
    
    local cutoff_date=$(date -u -d "${days_to_keep} days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-${days_to_keep}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    
    if command -v python3 >/dev/null 2>&1; then
        local temp_file="${ALERTS_HISTORY}.tmp"
        
        python3 -c "
import json
from datetime import datetime, timedelta

try:
    with open('${ALERTS_HISTORY}', 'r') as f:
        alerts = json.load(f)
    
    cutoff = datetime.fromisoformat('${cutoff_date}'.replace('Z', '+00:00'))
    
    filtered = []
    for alert in alerts:
        if not alert.get('resolved'):
            filtered.append(alert)
        else:
            resolved_at = alert.get('resolved_at')
            if resolved_at:
                resolved_date = datetime.fromisoformat(resolved_at.replace('Z', '+00:00'))
                if resolved_date > cutoff:
                    filtered.append(alert)
    
    with open('${temp_file}', 'w') as f:
        json.dump(filtered, f, indent=2)
    
    print(f'Cleaned up {len(alerts) - len(filtered)} old alerts')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
" 2>/dev/null
        
        if [ $? -eq 0 ] && [ -f "${temp_file}" ]; then
            mv "${temp_file}" "${ALERTS_HISTORY}"
            log_info "alerts" "Alert cleanup completed"
            return 0
        fi
    fi
    
    log_warn "alerts" "Alert cleanup skipped (python3 not available)"
    return 0
}

export -f alert_init
export -f alert_create
export -f alert_send_email
export -f alert_send_webhook
export -f alert_resolve
export -f alert_list
export -f alert_get
export -f alert_cleanup
