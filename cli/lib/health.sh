#!/usr/bin/env bash
#
# CachePilot - Health Check Library
#
# System and tenant health monitoring with comprehensive checks for Docker,
# disk space, certificates, and Redis instance health.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

HEALTH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_CONFIG="${CONFIG_DIR:-/etc/cachepilot}/monitoring-config.yaml"
_HEALTH_INITIALIZED=false

HEALTH_STATUS_HEALTHY="healthy"
HEALTH_STATUS_DEGRADED="degraded"
HEALTH_STATUS_UNHEALTHY="unhealthy"

DISK_SPACE_WARNING_PERCENT=${DISK_SPACE_WARNING_PERCENT:-80}
DISK_SPACE_CRITICAL_PERCENT=${DISK_SPACE_CRITICAL_PERCENT:-90}
CERT_EXPIRY_WARNING_DAYS=${CERT_EXPIRY_WARNING_DAYS:-30}
CERT_EXPIRY_CRITICAL_DAYS=${CERT_EXPIRY_CRITICAL_DAYS:-7}
MEMORY_WARNING_PERCENT=${MEMORY_WARNING_PERCENT:-85}
MEMORY_CRITICAL_PERCENT=${MEMORY_CRITICAL_PERCENT:-95}

health_init() {
    if [ "${_HEALTH_INITIALIZED}" = true ]; then
        return 0
    fi
    
    log_debug "health" "Initializing health system"
    
    if [ -f "${MONITORING_CONFIG}" ]; then
        log_debug "health" "Monitoring configuration found"
    fi
    
    _HEALTH_INITIALIZED=true
    log_info "health" "Health system initialized"
    return 0
}

health_check_system() {
    log_debug "health" "Starting system health check" >&2
    
    local issues=()
    local warnings=()
    local status="${HEALTH_STATUS_HEALTHY}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local docker_status=$(health_check_docker 2>&1)
    local docker_code=$?
    if [ $docker_code -ne 0 ]; then
        issues+=("Docker daemon: ${docker_status}")
        status="${HEALTH_STATUS_UNHEALTHY}"
    fi
    
    local disk_status=$(health_check_disk_space 2>&1)
    local disk_code=$?
    if [ $disk_code -eq 2 ]; then
        issues+=("Disk space critical: ${disk_status}")
        status="${HEALTH_STATUS_UNHEALTHY}"
    elif [ $disk_code -eq 1 ]; then
        warnings+=("Disk space warning: ${disk_status}")
        if [ "${status}" = "${HEALTH_STATUS_HEALTHY}" ]; then
            status="${HEALTH_STATUS_DEGRADED}"
        fi
    fi
    
    local cert_status=$(health_check_certificates 2>&1)
    local cert_code=$?
    if [ $cert_code -eq 2 ]; then
        issues+=("Certificates critical: ${cert_status}")
        status="${HEALTH_STATUS_UNHEALTHY}"
    elif [ $cert_code -eq 1 ]; then
        warnings+=("Certificates warning: ${cert_status}")
        if [ "${status}" = "${HEALTH_STATUS_HEALTHY}" ]; then
            status="${HEALTH_STATUS_DEGRADED}"
        fi
    fi
    
    local total_tenants=0
    local running_tenants=0
    local unhealthy_tenants=()
    
    if [ -d "${TENANTS_DIR}" ]; then
        for tenant_dir in "${TENANTS_DIR}"/*; do
            if [ -d "${tenant_dir}" ]; then
                ((total_tenants++))
                local tenant_name=$(basename "${tenant_dir}")
                
                if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant_name}$"; then
                    ((running_tenants++))
                    
                    local tenant_health=$(health_check_tenant "${tenant_name}" 2>&1)
                    local tenant_code=$?
                    if [ $tenant_code -ne 0 ]; then
                        unhealthy_tenants+=("${tenant_name}")
                        warnings+=("Tenant ${tenant_name}: ${tenant_health}")
                        if [ "${status}" = "${HEALTH_STATUS_HEALTHY}" ]; then
                            status="${HEALTH_STATUS_DEGRADED}"
                        fi
                    fi
                fi
            fi
        done
    fi
    
    local docker_json_status="unhealthy"
    [ $docker_code -eq 0 ] && docker_json_status="healthy"
    
    local disk_json_status="critical"
    [ $disk_code -eq 0 ] && disk_json_status="healthy"
    [ $disk_code -eq 1 ] && disk_json_status="warning"
    
    local cert_json_status="critical"
    [ $cert_code -eq 0 ] && cert_json_status="healthy"
    [ $cert_code -eq 1 ] && cert_json_status="warning"
    
    local services_json="{"
    services_json+="\"docker\":\"${docker_json_status}\","
    services_json+="\"disk_space\":\"${disk_json_status}\","
    services_json+="\"certificates\":\"${cert_json_status}\""
    services_json+="}"
    
    local all_issues=("${issues[@]}" "${warnings[@]}")
    local issues_json="["
    local first=true
    for issue in "${all_issues[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            issues_json+=","
        fi
        issues_json+="\"${issue//\"/\\\"}\""
    done
    issues_json+="]"
    
    cat <<EOF
{
  "status": "${status}",
  "timestamp": "${timestamp}",
  "services": ${services_json},
  "total_tenants": ${total_tenants},
  "running_tenants": ${running_tenants},
  "unhealthy_tenants": ${#unhealthy_tenants[@]},
  "issues": ${issues_json}
}
EOF
    
    log_info "health" "System health check completed: ${status}" "" "{\"total_tenants\":${total_tenants},\"running_tenants\":${running_tenants},\"issues\":${#all_issues[@]}}" >&2
    
    case "${status}" in
        "${HEALTH_STATUS_HEALTHY}") return 0 ;;
        "${HEALTH_STATUS_DEGRADED}") return 1 ;;
        "${HEALTH_STATUS_UNHEALTHY}") return 2 ;;
    esac
}

health_check_tenant() {
    local tenant_name="$1"
    
    if [ -z "${tenant_name}" ]; then
        echo "Tenant name required"
        return 1
    fi
    
    log_debug "health" "Checking tenant health" "${tenant_name}"
    
    local tenant_dir="${TENANTS_DIR}/${tenant_name}"
    if [ ! -d "${tenant_dir}" ]; then
        echo "Tenant not found"
        return 1
    fi
    
    local container_name="redis-${tenant_name}"
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "Container not found"
        return 1
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo "Container not running"
        return 1
    fi
    
    local config_file="${tenant_dir}/config.env"
    if [ ! -f "${config_file}" ]; then
        echo "Configuration file missing"
        return 1
    fi
    
    source "${config_file}"
    
    if ! docker exec "${container_name}" redis-cli -a "${PASSWORD}" --no-auth-warning ping >/dev/null 2>&1; then
        echo "Redis not responding to ping"
        return 1
    fi
    
    local memory_info=$(docker exec "${container_name}" redis-cli -a "${PASSWORD}" --no-auth-warning INFO memory 2>/dev/null | grep "used_memory:")
    local used_memory=$(echo "${memory_info}" | cut -d':' -f2 | tr -d '\r\n')
    
    if [ -n "${used_memory}" ] && [ -n "${MAXMEMORY}" ]; then
        local max_memory_bytes=$((MAXMEMORY * 1024 * 1024))
        local usage_percent=$((used_memory * 100 / max_memory_bytes))
        
        if [ ${usage_percent} -ge ${MEMORY_CRITICAL_PERCENT} ]; then
            echo "Memory usage critical: ${usage_percent}%"
            return 1
        elif [ ${usage_percent} -ge ${MEMORY_WARNING_PERCENT} ]; then
            echo "Memory usage high: ${usage_percent}%"
            return 1
        fi
    fi
    
    local container_health=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "none")
    if [ "${container_health}" = "unhealthy" ]; then
        echo "Container health check failed"
        return 1
    fi
    
    log_debug "health" "Tenant health check passed" "${tenant_name}"
    echo "healthy"
    return 0
}

health_check_certificates() {
    log_debug "health" "Checking certificate expiries"
    
    local ca_cert="${CA_DIR}/ca.crt"
    local issues=()
    local warnings=()
    local return_code=0
    
    if [ -f "${ca_cert}" ]; then
        local expiry_date=$(openssl x509 -in "${ca_cert}" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "${expiry_date}" ]; then
            local expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${expiry_date}" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))
            
            if [ ${days_until_expiry} -le ${CERT_EXPIRY_CRITICAL_DAYS} ]; then
                issues+=("CA certificate expires in ${days_until_expiry} days")
                return_code=2
            elif [ ${days_until_expiry} -le ${CERT_EXPIRY_WARNING_DAYS} ]; then
                warnings+=("CA certificate expires in ${days_until_expiry} days")
                if [ ${return_code} -eq 0 ]; then
                    return_code=1
                fi
            fi
        fi
    else
        issues+=("CA certificate not found")
        return_code=2
    fi
    
    if [ -d "${TENANTS_DIR}" ]; then
        for tenant_dir in "${TENANTS_DIR}"/*; do
            if [ -d "${tenant_dir}" ]; then
                local tenant_name=$(basename "${tenant_dir}")
                local tenant_cert="${tenant_dir}/certs/redis.crt"
                
                if [ -f "${tenant_cert}" ]; then
                    local expiry_date=$(openssl x509 -in "${tenant_cert}" -noout -enddate 2>/dev/null | cut -d= -f2)
                    if [ -n "${expiry_date}" ]; then
                        local expiry_epoch=$(date -d "${expiry_date}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${expiry_date}" +%s 2>/dev/null)
                        local now_epoch=$(date +%s)
                        local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))
                        
                        if [ ${days_until_expiry} -le ${CERT_EXPIRY_CRITICAL_DAYS} ]; then
                            issues+=("${tenant_name} certificate expires in ${days_until_expiry} days")
                            return_code=2
                        elif [ ${days_until_expiry} -le ${CERT_EXPIRY_WARNING_DAYS} ]; then
                            warnings+=("${tenant_name} certificate expires in ${days_until_expiry} days")
                            if [ ${return_code} -eq 0 ]; then
                                return_code=1
                            fi
                        fi
                    fi
                fi
            fi
        done
    fi
    
    if [ ${#issues[@]} -gt 0 ]; then
        echo "${issues[*]}"
    elif [ ${#warnings[@]} -gt 0 ]; then
        echo "${warnings[*]}"
    else
        echo "All certificates valid"
    fi
    
    return ${return_code}
}

health_check_disk_space() {
    log_debug "health" "Checking disk space"
    
    local work_dir="${TENANTS_DIR}"
    local usage=$(df -h "${work_dir}" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ -z "${usage}" ]; then
        echo "Unable to determine disk usage"
        return 2
    fi
    
    if [ ${usage} -ge ${DISK_SPACE_CRITICAL_PERCENT} ]; then
        echo "Disk usage at ${usage}% (critical threshold: ${DISK_SPACE_CRITICAL_PERCENT}%)"
        return 2
    elif [ ${usage} -ge ${DISK_SPACE_WARNING_PERCENT} ]; then
        echo "Disk usage at ${usage}% (warning threshold: ${DISK_SPACE_WARNING_PERCENT}%)"
        return 1
    else
        echo "Disk usage at ${usage}%"
        return 0
    fi
}

health_check_docker() {
    log_debug "health" "Checking Docker daemon"
    
    if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon not responding"
        return 1
    fi
    
    if ! docker network inspect cachepilot-net >/dev/null 2>&1; then
        echo "cachepilot-net network missing"
        return 1
    fi
    
    echo "Docker daemon healthy"
    return 0
}

health_generate_report() {
    log_info "health" "Generating comprehensive health report"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local system_health=$(health_check_system)
    local tenants_json="["
    local first=true
    
    if [ -d "${TENANTS_DIR}" ]; then
        for tenant_dir in "${TENANTS_DIR}"/*; do
            if [ -d "${tenant_dir}" ]; then
                local tenant_name=$(basename "${tenant_dir}")
                
                if [ "$first" = true ]; then
                    first=false
                else
                    tenants_json+=","
                fi
                
                local running="false"
                if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant_name}$"; then
                    running="true"
                fi
                
                local health_status="unknown"
                local health_message=""
                if [ "${running}" = "true" ]; then
                    health_message=$(health_check_tenant "${tenant_name}" 2>&1)
                    if [ $? -eq 0 ]; then
                        health_status="healthy"
                    else
                        health_status="unhealthy"
                    fi
                else
                    health_message="Container not running"
                    health_status="stopped"
                fi
                
                tenants_json+="{"
                tenants_json+="\"name\":\"${tenant_name}\","
                tenants_json+="\"running\":${running},"
                tenants_json+="\"health_status\":\"${health_status}\","
                tenants_json+="\"health_message\":\"${health_message//\"/\\\"}\""
                tenants_json+="}"
            fi
        done
    fi
    tenants_json+="]"
    
    cat <<EOF
{
  "report_timestamp": "${timestamp}",
  "system_health": ${system_health},
  "tenants": ${tenants_json}
}
EOF
    
    log_info "health" "Health report generated successfully"
    return 0
}

export -f health_init
export -f health_check_system
export -f health_check_tenant
export -f health_check_certificates
export -f health_check_disk_space
export -f health_check_docker
export -f health_generate_report
