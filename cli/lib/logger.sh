#!/usr/bin/env bash
#
# CachePilot - Structured Logging Library
#
# Provides JSON-formatted logs, audit trails, and metric collection with
# automatic log rotation and configurable output formats.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.2-Beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

if [[ -n "${LOGGER_SOURCED:-}" ]]; then
    return 0
fi
readonly LOGGER_SOURCED=true

if [[ -z "${LOG_COLOR_RED:-}" ]]; then
    readonly LOG_COLOR_RED='\033[0;31m'
    readonly LOG_COLOR_GREEN='\033[0;32m'
    readonly LOG_COLOR_YELLOW='\033[1;33m'
    readonly LOG_COLOR_BLUE='\033[0;34m'
    readonly LOG_COLOR_CYAN='\033[0;36m'
    readonly LOG_COLOR_NC='\033[0m'
fi

if [[ -z "${LOG_LEVEL_DEBUG:-}" ]]; then
    readonly LOG_LEVEL_DEBUG=0
    readonly LOG_LEVEL_INFO=1
    readonly LOG_LEVEL_WARN=2
    readonly LOG_LEVEL_ERROR=3
fi

LOGGER_INITIALIZED=false
LOGGER_CONFIG_FILE="/etc/cachepilot/logging-config.yaml"
LOGGER_DEFAULT_LEVEL="INFO"
LOGGER_JSON_FORMAT=true
LOGGER_COLORED_CONSOLE=true
LOGGER_LOG_FILE="${LOGS_DIR:-/var/log/cachepilot}/cachepilot.log"
LOGGER_AUDIT_FILE="${LOGS_DIR:-/var/log/cachepilot}/audit.log"
LOGGER_METRICS_FILE="${LOGS_DIR:-/var/log/cachepilot}/metrics.log"

_logger_parse_yaml() {
    local yaml_file="$1"
    local key="$2"
    local default="$3"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "$default"
        return
    fi
    
    local value=$(grep -E "^\s*${key}:" "$yaml_file" | head -1 | sed 's/.*:\s*//' | sed 's/#.*//' | xargs)
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

log_init() {
    if [[ "$LOGGER_INITIALIZED" == "true" ]]; then
        return 0
    fi
    
    LOGS_DIR="${LOGS_DIR:-/var/log/cachepilot}"
    
    mkdir -p "$LOGS_DIR" 2>/dev/null || true
    chmod 755 "$LOGS_DIR" 2>/dev/null || true
    
    if [[ -f "$LOGGER_CONFIG_FILE" ]]; then
        LOGGER_DEFAULT_LEVEL=$(_logger_parse_yaml "$LOGGER_CONFIG_FILE" "default_level" "INFO")
        local json_format=$(_logger_parse_yaml "$LOGGER_CONFIG_FILE" "json_format" "true")
        [[ "$json_format" == "true" ]] && LOGGER_JSON_FORMAT=true || LOGGER_JSON_FORMAT=false
        local colored=$(_logger_parse_yaml "$LOGGER_CONFIG_FILE" "colored_console" "true")
        [[ "$colored" == "true" ]] && LOGGER_COLORED_CONSOLE=true || LOGGER_COLORED_CONSOLE=false
        
        local file_path=$(_logger_parse_yaml "$LOGGER_CONFIG_FILE" "path" "${LOGS_DIR}/cachepilot.log")
        file_path="${file_path//\$LOGS_DIR/$LOGS_DIR}"
        file_path="${file_path//\${LOGS_DIR}/$LOGS_DIR}"
        [[ -n "$file_path" ]] && LOGGER_LOG_FILE="$file_path"
        
        LOGGER_AUDIT_FILE="${LOGS_DIR}/audit.log"
        LOGGER_METRICS_FILE="${LOGS_DIR}/metrics.log"
    fi
    
    touch "$LOGGER_LOG_FILE" "$LOGGER_AUDIT_FILE" "$LOGGER_METRICS_FILE" 2>/dev/null || true
    chmod 640 "$LOGGER_LOG_FILE" "$LOGGER_AUDIT_FILE" "$LOGGER_METRICS_FILE" 2>/dev/null || true
    
    LOGGER_INITIALIZED=true
}

_logger_level_to_num() {
    case "${1^^}" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

_logger_should_log() {
    local level="$1"
    local level_num=$(_logger_level_to_num "$level")
    local default_num=$(_logger_level_to_num "$LOGGER_DEFAULT_LEVEL")
    [[ $level_num -ge $default_num ]]
}

_logger_sanitize() {
    local message="$1"
    
    message=$(echo "$message" | sed -E 's/(password|passwd|pwd)=[^ ]*/\1=[REDACTED]/gi')
    message=$(echo "$message" | sed -E 's/(secret|token|key|credential)=[^ ]*/\1=[REDACTED]/gi')
    message=$(echo "$message" | sed -E 's/(redis:\/\/:[^@]+@)/redis:\/\/:[REDACTED]@/gi')
    
    echo "$message"
}

_logger_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    echo "$str"
}

log_to_json() {
    local level="$1"
    local component="$2"
    local message="$3"
    local tenant="${4:-}"
    local details="${5:-}"
    
    message=$(_logger_sanitize "$message")
    
    local level_esc=$(_logger_escape_json "$level")
    local component_esc=$(_logger_escape_json "$component")
    local message_esc=$(_logger_escape_json "$message")
    local tenant_esc=$(_logger_escape_json "$tenant")
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    local json="{\"timestamp\":\"$timestamp\",\"level\":\"$level_esc\",\"component\":\"$component_esc\",\"message\":\"$message_esc\""
    
    if [[ -n "$tenant" ]]; then
        json="${json},\"tenant\":\"$tenant_esc\""
    fi
    
    if [[ -n "$details" ]]; then
        if [[ "$details" =~ ^\{.*\}$ ]]; then
            json="${json},\"details\":$details"
        else
            local details_esc=$(_logger_escape_json "$details")
            json="${json},\"details\":\"$details_esc\""
        fi
    fi
    
    json="${json},\"hostname\":\"$(hostname)\",\"pid\":$$}"
    json="${json}}"
    echo "$json"
}

_logger_write_file() {
    local json_log="$1"
    local file="$2"
    
    if [[ -f "$file" ]]; then
        echo "$json_log" >> "$file"
        
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        if [[ $file_size -gt 104857600 ]]; then
            local rotated="${file}.$(date +%Y%m%d-%H%M%S)"
            mv "$file" "$rotated"
            gzip "$rotated" 2>/dev/null || true
            touch "$file"
            chmod 640 "$file" 2>/dev/null || true
        fi
    fi
}

_logger_console_output() {
    local level="$1"
    local component="$2"
    local message="$3"
    local tenant="$4"
    
    local color=""
    local stream="1"
    
    case "$level" in
        DEBUG)
            color="$LOG_COLOR_CYAN"
            ;;
        INFO)
            color="$LOG_COLOR_GREEN"
            ;;
        WARN)
            color="$LOG_COLOR_YELLOW"
            stream="2"
            ;;
        ERROR)
            color="$LOG_COLOR_RED"
            stream="2"
            ;;
    esac
    
    local prefix="[${level}]"
    if [[ "$LOGGER_COLORED_CONSOLE" == "true" ]]; then
        prefix="${color}[${level}]${LOG_COLOR_NC}"
    fi
    
    local output="$prefix"
    if [[ -n "$component" ]]; then
        output="${output} [${component}]"
    fi
    if [[ -n "$tenant" ]]; then
        output="${output} [${tenant}]"
    fi
    output="${output} ${message}"
    
    if [[ "$stream" == "2" ]]; then
        echo -e "$output" >&2
    else
        echo -e "$output"
    fi
}

_logger_log() {
    local level="$1"
    local component="$2"
    local message="$3"
    local tenant="${4:-}"
    local details="${5:-}"
    
    [[ "$LOGGER_INITIALIZED" == "false" ]] && log_init
    
    if ! _logger_should_log "$level"; then
        return 0
    fi
    
    local json_log=$(log_to_json "$level" "$component" "$message" "$tenant" "$details")
    
    _logger_write_file "$json_log" "$LOGGER_LOG_FILE"
    _logger_console_output "$level" "$component" "$message" "$tenant"
}

log_debug() {
    local component="$1"
    local message="$2"
    local tenant="${3:-}"
    local details="${4:-}"
    
    _logger_log "DEBUG" "$component" "$message" "$tenant" "$details"
}

log_info() {
    local component="$1"
    local message="$2"
    local tenant="${3:-}"
    local details="${4:-}"
    
    _logger_log "INFO" "$component" "$message" "$tenant" "$details"
}

log_warn() {
    local component="$1"
    local message="$2"
    local tenant="${3:-}"
    local details="${4:-}"
    
    _logger_log "WARN" "$component" "$message" "$tenant" "$details"
}

log_error() {
    local component="$1"
    local message="$2"
    local tenant="${3:-}"
    local details="${4:-}"
    
    _logger_log "ERROR" "$component" "$message" "$tenant" "$details"
}

log_audit() {
    local user="$1"
    local action="$2"
    local tenant="$3"
    local details="$4"
    
    [[ "$LOGGER_INITIALIZED" == "false" ]] && log_init
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    
    local user_esc=$(_logger_escape_json "$user")
    local action_esc=$(_logger_escape_json "$action")
    local tenant_esc=$(_logger_escape_json "$tenant")
    
    local audit_json="{\"timestamp\":\"$timestamp\",\"user\":\"$user_esc\",\"action\":\"$action_esc\",\"tenant\":\"$tenant_esc\""
    
    if [[ -n "$details" ]]; then
        if [[ "$details" =~ ^\{.*\}$ ]]; then
            audit_json="${audit_json},\"details\":$details"
        else
            local details_esc=$(_logger_escape_json "$details")
            audit_json="${audit_json},\"details\":\"$details_esc\""
        fi
    fi
    
    audit_json="${audit_json},\"hostname\":\"$(hostname)\",\"pid\":$$}"
    audit_json="${audit_json}}"
    
    _logger_write_file "$audit_json" "$LOGGER_AUDIT_FILE"
    log_info "audit" "User '$user' performed '$action' on tenant '$tenant'" "$tenant"
}

log_metric() {
    local tenant="$1"
    local metric_name="$2"
    local value="$3"
    local unit="${4:-}"
    
    [[ "$LOGGER_INITIALIZED" == "false" ]] && log_init
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S%z")
    
    local tenant_esc=$(_logger_escape_json "$tenant")
    local metric_esc=$(_logger_escape_json "$metric_name")
    local unit_esc=$(_logger_escape_json "$unit")
    
    local metric_json="{\"timestamp\":\"$timestamp\",\"tenant\":\"$tenant_esc\",\"metric\":\"$metric_esc\",\"value\":$value"
    
    if [[ -n "$unit" ]]; then
        metric_json="${metric_json},\"unit\":\"$unit_esc\""
    fi
    
    metric_json="${metric_json}}"
    
    _logger_write_file "$metric_json" "$LOGGER_METRICS_FILE"
}

log_query() {
    local log_type="${1:-main}"
    local filter="${2:-}"
    local lines="${3:-100}"
    
    local log_file="$LOGGER_LOG_FILE"
    case "$log_type" in
        audit)   log_file="$LOGGER_AUDIT_FILE" ;;
        metrics) log_file="$LOGGER_METRICS_FILE" ;;
    esac
    
    if [[ ! -f "$log_file" ]]; then
        echo "[]"
        return
    fi
    
    if [[ -n "$filter" ]]; then
        tail -n "$lines" "$log_file" | grep "$filter" || echo "[]"
    else
        tail -n "$lines" "$log_file"
    fi
}

log_get_errors() {
    local lines="${1:-50}"
    log_query "main" "\"level\":\"ERROR\"" "$lines"
}

log_get_audit_trail() {
    local tenant="$1"
    local lines="${2:-100}"
    log_query "audit" "\"tenant\":\"$tenant\"" "$lines"
}

log_init
