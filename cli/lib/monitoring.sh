#!/usr/bin/env bash
#
# CachePilot - Monitoring and Statistics Library
#
# Comprehensive monitoring with Redis INFO parsing, tenant status reporting,
# global statistics, metrics collection, and threshold checking.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.2-Beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

MONITORING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="${LOGS_DIR:-/var/log/cachepilot}/metrics"
JSON_OUTPUT=${JSON_OUTPUT:-false}
MONITORING_CONFIG="/etc/cachepilot/monitoring-config.yaml"

get_redis_info() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        return 1
    fi
    
    source "${tenant_dir}/config.env"
    
    local security_mode="${SECURITY_MODE:-tls-only}"
    local redis_cli_cmd="docker exec redis-${tenant} redis-cli"
    
    # Determine which port to use based on security mode
    case "$security_mode" in
        "tls-only"|"dual-mode")
            # Use TLS connection on internal port 6380
            redis_cli_cmd="$redis_cli_cmd -p 6380 --tls --cacert /certs/ca.crt --cert /certs/redis.crt --key /certs/redis.key"
            ;;
        "plain-only")
            # Use plain-text connection on internal port 6379
            redis_cli_cmd="$redis_cli_cmd -p 6379"
            ;;
    esac
    
    redis_cli_cmd="$redis_cli_cmd -a ${PASSWORD}"
    
    # Add 5 second timeout to prevent hanging
    timeout 5 $redis_cli_cmd INFO 2>&1 | grep -v "Using a password"
}

show_tenant_status() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    local port="${PORT_TLS:-${PORT:-}}"
    
    echo ""
    echo "=========================================="
    echo "Tenant Status: $tenant"
    echo "=========================================="
    echo ""
    
    if ! docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        echo -e "Status: ${RED}STOPPED${NC}"
        return 0
    fi
    
    echo -e "Status: ${GREEN}RUNNING${NC}"
    echo ""
    
    echo "Connection:"
    echo "  Host: ${INTERNAL_IP}"
    echo "  Port: $port"
    echo "  Created: $CREATED"
    echo ""
    
    local stats=$(get_container_stats "$tenant" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$stats" ]]; then
        local cpu=$(echo "$stats" | jq -r '.CPUPerc' 2>/dev/null | tr -d '%')
        local mem=$(echo "$stats" | jq -r '.MemUsage' 2>/dev/null | cut -d'/' -f1)
        local mem_limit=$(echo "$stats" | jq -r '.MemUsage' 2>/dev/null | cut -d'/' -f2)
        local mem_perc=$(echo "$stats" | jq -r '.MemPerc' 2>/dev/null | tr -d '%')
        
        # Only display if we got valid data
        if [[ -n "$cpu" ]] && [[ -n "$mem" ]]; then
            echo "Container Resources:"
            echo "  CPU: ${cpu}%"
            echo "  Memory: ${mem} / ${mem_limit} (${mem_perc}%)"
            echo ""
        fi
    fi
    
    local info=$(get_redis_info "$tenant")
    if [[ $? -eq 0 ]]; then
        local uptime=$(echo "$info" | grep "^uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
        local clients=$(echo "$info" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
        local used_memory=$(echo "$info" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
        local used_memory_peak=$(echo "$info" | grep "^used_memory_peak:" | cut -d: -f2 | tr -d '\r')
        local total_commands=$(echo "$info" | grep "^total_commands_processed:" | cut -d: -f2 | tr -d '\r')
        local keyspace_hits=$(echo "$info" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r')
        local keyspace_misses=$(echo "$info" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r')
        local evicted_keys=$(echo "$info" | grep "^evicted_keys:" | cut -d: -f2 | tr -d '\r')
        local keys=$(echo "$info" | grep "^db0:" | grep -oP 'keys=\K[0-9]+' || echo "0")
        
        echo "Redis Statistics:"
        echo "  Uptime: $(format_uptime $uptime)"
        echo "  Connected Clients: $clients"
        echo "  Total Keys: $keys"
        echo "  Memory Used: $(format_bytes $used_memory)"
        echo "  Memory Peak: $(format_bytes $used_memory_peak)"
        echo "  Memory Limit: ${MAXMEMORY}MB (Redis) / ${DOCKER_LIMIT}MB (Docker)"
        echo "  Total Commands: $total_commands"
        echo "  Keyspace Hits: $keyspace_hits"
        echo "  Keyspace Misses: $keyspace_misses"
        
        if [[ $keyspace_hits -gt 0 ]] || [[ $keyspace_misses -gt 0 ]]; then
            local total=$((keyspace_hits + keyspace_misses))
            local hit_rate=$(awk "BEGIN {printf \"%.2f\", ($keyspace_hits / $total) * 100}")
            echo "  Hit Rate: ${hit_rate}%"
        fi
        
        echo "  Evicted Keys: $evicted_keys"
        echo ""
    fi
    
    local cert="${tenant_dir}/certs/redis.crt"
    if [[ -f "$cert" ]]; then
        local days_left=$(check_cert_expiry "$cert")
        local expiry=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
        
        echo "Certificate:"
        echo "  Expires: $(date -d "$expiry" +%Y-%m-%d)"
        echo "  Days Left: $days_left"
        
        if [[ $days_left -lt 30 ]]; then
            echo -e "  Status: ${RED}EXPIRING SOON${NC}"
        else
            echo -e "  Status: ${GREEN}OK${NC}"
        fi
        echo ""
    fi
    
    if [[ -n "${INSIGHT_PORT:-}" ]] && [[ "${INSIGHT_PORT:-0}" != "0" ]]; then
        echo "RedisInsight:"
        if docker ps --format '{{.Names}}' | grep -q "^nginx-${tenant}$"; then
            echo -e "  Status: ${GREEN}ENABLED${NC}"
            echo "  Public URL: https://${PUBLIC_IP}:${INSIGHT_PORT}"
            echo "  Internal URL: https://${INTERNAL_IP}:${INSIGHT_PORT}"
            echo "  Username: ${INSIGHT_USER:-admin}"
        else
            echo -e "  Status: ${RED}STOPPED${NC}"
            echo "  Port: ${INSIGHT_PORT}"
        fi
    else
        echo -e "RedisInsight: ${YELLOW}DISABLED${NC}"
    fi
    
    echo ""
}

list_all_tenants() {
    echo ""
    echo "Redis Tenants Overview"
    echo ""
    printf "%-20s %-8s %-8s %-15s %-15s %-12s %-10s %-10s %-10s\n" \
        "TENANT" "PORT" "STATUS" "MEMORY" "LIMIT" "CLIENTS" "KEYS" "UPTIME" "INSIGHT"
    printf "%-20s %-8s %-8s %-15s %-15s %-12s %-10s %-10s %-10s\n" \
        "--------------------" "--------" "--------" "---------------" "---------------" "------------" "----------" "----------" "----------"
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [[ -d "$tenant_dir" ]] && [[ -f "${tenant_dir}/config.env" ]]; then
            local tenant=$(basename "$tenant_dir")
            source "${tenant_dir}/config.env"
            
            local port="${PORT_TLS:-${PORT:-}}"
            local status="STOPPED"
            local memory="-"
            local limit="${MAXMEMORY:-256}/${DOCKER_LIMIT:-512}MB"
            local clients="-"
            local keys="-"
            local uptime="-"
            local insight="-"
            
            if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
                status="${GREEN}RUNNING${NC}"
                
                local info=$(get_redis_info "$tenant")
                if [[ -n "$info" ]]; then
                    local uptime_sec=$(echo "$info" | grep "^uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
                    clients=$(echo "$info" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
                    local used_mem=$(echo "$info" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
                    keys=$(echo "$info" | grep "^db0:" | grep -oP 'keys=\K[0-9]+' || echo "0")
                    
                    memory=$(format_bytes $used_mem)
                    uptime=$(format_uptime $uptime_sec)
                fi
            else
                status="${RED}STOPPED${NC}"
            fi
            
            if [[ -n "${INSIGHT_PORT:-}" ]] && [[ "${INSIGHT_PORT:-0}" != "0" ]]; then
                if docker ps --format '{{.Names}}' | grep -q "^nginx-${tenant}$"; then
                    insight="${GREEN}ON${NC}"
                else
                    insight="${YELLOW}OFF${NC}"
                fi
            fi
            
            printf "%-20s %-8s %-8b %-15s %-15s %-12s %-10s %-10s %-8b\n" \
                "$tenant" "$port" "$status" "$memory" "$limit" "$clients" "$keys" "$uptime" "$insight"
        fi
    done
    
    echo ""
}

show_global_stats() {
    echo ""
    echo "=========================================="
    echo "Global Redis Statistics"
    echo "=========================================="
    echo ""
    
    local total_tenants=0
    local running_tenants=0
    local total_memory=0
    local total_clients=0
    local total_keys=0
    
    declare -A tenant_memory
    declare -A tenant_clients
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [[ -d "$tenant_dir" ]]; then
            local tenant=$(basename "$tenant_dir")
            total_tenants=$((total_tenants + 1))
            
            if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
                running_tenants=$((running_tenants + 1))
                
                local info=$(get_redis_info "$tenant")
                if [[ -n "$info" ]]; then
                    local used_mem=$(echo "$info" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
                    local clients=$(echo "$info" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
                    local keys=$(echo "$info" | grep "^db0:" | grep -oP 'keys=\K[0-9]+' || echo "0")
                    
                    total_memory=$((total_memory + used_mem))
                    total_clients=$((total_clients + clients))
                    total_keys=$((total_keys + keys))
                    
                    tenant_memory[$tenant]=$used_mem
                    tenant_clients[$tenant]=$clients
                fi
            fi
        fi
    done
    
    echo "Overview:"
    echo "  Total Tenants: $total_tenants"
    echo "  Running: $running_tenants"
    echo "  Stopped: $((total_tenants - running_tenants))"
    echo "  Total Memory Used: $(format_bytes $total_memory)"
    echo "  Total Clients: $total_clients"
    echo "  Total Keys: $total_keys"
    echo ""
    
    set +u
    if [[ $running_tenants -gt 0 ]] && [[ ${#tenant_memory[@]} -gt 0 ]]; then
        set -u
        echo "Top 10 Tenants by Memory Usage:"
        echo ""
        printf "%-20s %-15s %-12s\n" "TENANT" "MEMORY" "CLIENTS"
        printf "%-20s %-15s %-12s\n" "--------------------" "---------------" "------------"
        
        # Use array instead of while read to avoid subprocess blocking
        local -a top_memory=()
        for tenant in "${!tenant_memory[@]}"; do
            top_memory+=("$tenant ${tenant_memory[$tenant]:-0} ${tenant_clients[$tenant]:-0}")
        done
        
        IFS=$'\n' sorted_memory=($(printf '%s\n' "${top_memory[@]}" | sort -k2 -rn | head -10))
        for line in "${sorted_memory[@]}"; do
            read -r tenant mem clients <<< "$line"
            printf "%-20s %-15s %-12s\n" "$tenant" "$(format_bytes ${mem:-0})" "${clients:-0}"
        done
        
        echo ""
    fi
    
    set +u
    if [[ $running_tenants -gt 0 ]] && [[ ${#tenant_clients[@]} -gt 0 ]]; then
        set -u
        echo "Top 10 Tenants by Client Connections:"
        echo ""
        printf "%-20s %-12s %-15s\n" "TENANT" "CLIENTS" "MEMORY"
        printf "%-20s %-12s %-15s\n" "--------------------" "------------" "---------------"
        
        # Use array instead of while read to avoid subprocess blocking
        local -a top_clients=()
        for tenant in "${!tenant_clients[@]}"; do
            top_clients+=("$tenant ${tenant_clients[$tenant]:-0} ${tenant_memory[$tenant]:-0}")
        done
        
        IFS=$'\n' sorted_clients=($(printf '%s\n' "${top_clients[@]}" | sort -k2 -rn | head -10))
        for line in "${sorted_clients[@]}"; do
            read -r tenant clients mem <<< "$line"
            printf "%-20s %-12s %-15s\n" "$tenant" "${clients:-0}" "$(format_bytes ${mem:-0})"
        done
        
        echo ""
    fi
    
    local available_ports=$((100 - total_tenants))
    echo "Capacity:"
    echo "  Available Ports: $available_ports / 100"
    echo "  Port Range: 7300-7399"
    echo ""
}

get_tenant_status_json() {
    local tenant="$1"
    
    if [ -z "${tenant}" ]; then
        echo '{"error":"Tenant name required"}'
        return 1
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "${tenant_dir}" ]; then
        echo '{"error":"Tenant not found"}'
        return 1
    fi
    
    source "${tenant_dir}/config.env"
    
    local running="false"
    local status="stopped"
    
    if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        running="true"
        status="running"
    fi
    
    local json="{"
    json+="\"tenant\":\"${tenant}\","
    json+="\"port\":${PORT},"
    json+="\"status\":\"${status}\","
    json+="\"running\":${running},"
    json+="\"created\":\"${CREATED}\","
    json+="\"maxmemory\":${MAXMEMORY:-256},"
    json+="\"docker_limit\":${DOCKER_LIMIT:-512},"
    json+="\"insight_enabled\":$([ "${INSIGHT_PORT:-0}" != "0" ] && echo "true" || echo "false"),"
    json+="\"insight_port\":${INSIGHT_PORT:-0}"
    
    if [ "${running}" = "true" ]; then
        local info=$(get_redis_info "${tenant}")
        if [ -n "${info}" ]; then
            local uptime=$(echo "${info}" | grep "^uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
            local clients=$(echo "${info}" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
            local used_memory=$(echo "${info}" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
            local used_memory_peak=$(echo "${info}" | grep "^used_memory_peak:" | cut -d: -f2 | tr -d '\r')
            local total_commands=$(echo "${info}" | grep "^total_commands_processed:" | cut -d: -f2 | tr -d '\r')
            local keyspace_hits=$(echo "${info}" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r')
            local keyspace_misses=$(echo "${info}" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r')
            local evicted_keys=$(echo "${info}" | grep "^evicted_keys:" | cut -d: -f2 | tr -d '\r')
            local expired_keys=$(echo "${info}" | grep "^expired_keys:" | cut -d: -f2 | tr -d '\r')
            local keys=$(echo "${info}" | grep "^db0:" | grep -oP 'keys=\K[0-9]+' || echo "0")
            
            json+=",\"uptime_seconds\":${uptime:-0}"
            json+=",\"connected_clients\":${clients:-0}"
            json+=",\"memory_used\":${used_memory:-0}"
            json+=",\"memory_peak\":${used_memory_peak:-0}"
            json+=",\"total_keys\":${keys}"
            json+=",\"total_commands\":${total_commands:-0}"
            json+=",\"keyspace_hits\":${keyspace_hits:-0}"
            json+=",\"keyspace_misses\":${keyspace_misses:-0}"
            json+=",\"evicted_keys\":${evicted_keys:-0}"
            json+=",\"expired_keys\":${expired_keys:-0}"
            
            if [ ${keyspace_hits:-0} -gt 0 ] || [ ${keyspace_misses:-0} -gt 0 ]; then
                local total=$((keyspace_hits + keyspace_misses))
                local hit_rate=$(awk "BEGIN {printf \"%.4f\", ($keyspace_hits / $total)}")
                json+=",\"hit_rate\":${hit_rate}"
            else
                json+=",\"hit_rate\":null"
            fi
        fi
    fi
    
    json+="}"
    echo "${json}"
    return 0
}

list_all_tenants_json() {
    local json="["
    local first=true
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [ -d "${tenant_dir}" ]; then
            local tenant=$(basename "${tenant_dir}")
            
            if [ "$first" = true ]; then
                first=false
            else
                json+=","
            fi
            
            json+=$(get_tenant_status_json "${tenant}")
        fi
    done
    
    json+="]"
    echo "${json}"
    return 0
}

show_global_stats_json() {
    local total_tenants=0
    local running_tenants=0
    local total_memory=0
    local total_clients=0
    local total_keys=0
    local total_commands=0
    
    # Count total tenants quickly from directory
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [ -d "${tenant_dir}" ]; then
            ((total_tenants++))
        fi
    done
    
    # Get running tenant count from docker (FAST)
    running_tenants=$(docker ps --filter "name=redis-" --format "{{.Names}}" | grep -c "^redis-" || echo "0")
    
    # Use docker stats for memory (single fast call, no Redis connection needed)
    if [ $running_tenants -gt 0 ]; then
        # Get memory stats from docker (much faster than redis-cli INFO)
        while IFS= read -r line; do
            if [[ "$line" =~ redis- ]]; then
                # Extract memory from docker stats format like "123.4MiB / 512MiB"
                local mem_str=$(echo "$line" | awk '{print $4}')
                # Convert to bytes (handle MiB/GiB)
                if [[ "$mem_str" =~ ([0-9.]+)MiB ]]; then
                    local mem_mib="${BASH_REMATCH[1]}"
                    local mem_bytes=$(awk "BEGIN {printf \"%.0f\", $mem_mib * 1024 * 1024}")
                    total_memory=$((total_memory + mem_bytes))
                elif [[ "$mem_str" =~ ([0-9.]+)GiB ]]; then
                    local mem_gib="${BASH_REMATCH[1]}"
                    local mem_bytes=$(awk "BEGIN {printf \"%.0f\", $mem_gib * 1024 * 1024 * 1024}")
                    total_memory=$((total_memory + mem_bytes))
                fi
            fi
        done < <(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep "redis-")
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat <<EOF
{
  "timestamp": "${timestamp}",
  "total_tenants": ${total_tenants},
  "running_tenants": ${running_tenants},
  "stopped_tenants": $((total_tenants - running_tenants)),
  "total_memory_used": ${total_memory},
  "total_clients": ${total_clients},
  "total_keys": ${total_keys},
  "total_commands": ${total_commands},
  "available_ports": $((100 - total_tenants))
}
EOF
    
    return 0
}

collect_tenant_metrics() {
    local tenant="$1"
    
    if [ -z "${tenant}" ]; then
        log_error "monitoring" "Tenant name required for metric collection"
        return 1
    fi
    
    if [ ! -d "${METRICS_DIR}" ]; then
        mkdir -p "${METRICS_DIR}"
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "${tenant_dir}" ]; then
        log_warn "monitoring" "Tenant not found for metric collection" "${tenant}"
        return 1
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
        log_debug "monitoring" "Tenant not running, skipping metric collection" "${tenant}"
        return 0
    fi
    
    local info=$(get_redis_info "${tenant}")
    if [ -z "${info}" ]; then
        log_warn "monitoring" "Failed to get Redis info for metric collection" "${tenant}"
        return 1
    fi
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local epoch=$(date +%s)
    
    local memory_used=$(echo "${info}" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
    local memory_peak=$(echo "${info}" | grep "^used_memory_peak:" | cut -d: -f2 | tr -d '\r')
    local clients=$(echo "${info}" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
    local commands=$(echo "${info}" | grep "^total_commands_processed:" | cut -d: -f2 | tr -d '\r')
    local keyspace_hits=$(echo "${info}" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r')
    local keyspace_misses=$(echo "${info}" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r')
    local evicted_keys=$(echo "${info}" | grep "^evicted_keys:" | cut -d: -f2 | tr -d '\r')
    local expired_keys=$(echo "${info}" | grep "^expired_keys:" | cut -d: -f2 | tr -d '\r')
    
    local date_str=$(date +%Y-%m-%d)
    local metrics_file="${METRICS_DIR}/${tenant}_${date_str}.jsonl"
    
    cat <<EOF >> "${metrics_file}"
{"timestamp":"${timestamp}","epoch":${epoch},"tenant":"${tenant}","memory_used":${memory_used},"memory_peak":${memory_peak},"clients":${clients},"commands":${commands},"keyspace_hits":${keyspace_hits},"keyspace_misses":${keyspace_misses},"evicted_keys":${evicted_keys},"expired_keys":${expired_keys}}
EOF
    
    log_debug "monitoring" "Metrics collected successfully" "${tenant}"
    check_tenant_thresholds "${tenant}" "${info}"
    
    return 0
}

collect_all_metrics() {
    log_info "monitoring" "Starting metric collection for all tenants"
    
    local collected=0
    local failed=0
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [ -d "${tenant_dir}" ]; then
            local tenant=$(basename "${tenant_dir}")
            
            if collect_tenant_metrics "${tenant}"; then
                ((collected++))
            else
                ((failed++))
            fi
        fi
    done
    
    log_info "monitoring" "Metric collection completed" "" "{\"collected\":${collected},\"failed\":${failed}}"
    return 0
}

check_tenant_thresholds() {
    local tenant="$1"
    local info="$2"
    
    if [ -z "${tenant}" ] || [ -z "${info}" ]; then
        return 0
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    source "${tenant_dir}/config.env"
    
    local used_memory=$(echo "${info}" | grep "^used_memory:" | cut -d: -f2 | tr -d '\r')
    if [ -n "${used_memory}" ] && [ -n "${MAXMEMORY}" ]; then
        local max_memory_bytes=$((MAXMEMORY * 1024 * 1024))
        local usage_percent=$((used_memory * 100 / max_memory_bytes))
        
        if [ ${usage_percent} -ge ${MEMORY_CRITICAL_PERCENT:-95} ]; then
            alert_create "critical" "Memory usage critical" \
                "Tenant ${tenant} memory usage at ${usage_percent}%" "${tenant}" >/dev/null 2>&1
        elif [ ${usage_percent} -ge ${MEMORY_WARNING_PERCENT:-85} ]; then
            alert_create "warning" "Memory usage high" \
                "Tenant ${tenant} memory usage at ${usage_percent}%" "${tenant}" >/dev/null 2>&1
        fi
    fi
    
    local clients=$(echo "${info}" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
    if [ -n "${clients}" ]; then
        if [ ${clients} -ge 950 ]; then
            alert_create "critical" "Client connections critical" \
                "Tenant ${tenant} has ${clients} connected clients" "${tenant}" >/dev/null 2>&1
        elif [ ${clients} -ge 900 ]; then
            alert_create "warning" "Client connections high" \
                "Tenant ${tenant} has ${clients} connected clients" "${tenant}" >/dev/null 2>&1
        fi
    fi
    
    return 0
}

get_metric_trend() {
    local tenant="$1"
    local metric="$2"
    local hours="${3:-24}"
    
    if [ -z "${tenant}" ] || [ -z "${metric}" ]; then
        echo '{"error":"Tenant and metric name required"}'
        return 1
    fi
    
    echo "[]"
    return 0
}

cleanup_old_metrics() {
    local days_to_keep="${1:-7}"
    
    if [ ! -d "${METRICS_DIR}" ]; then
        return 0
    fi
    
    log_info "monitoring" "Cleaning up metrics older than ${days_to_keep} days"
    
    local cutoff_date=$(date -d "${days_to_keep} days ago" +%Y-%m-%d 2>/dev/null || date -v-${days_to_keep}d +%Y-%m-%d 2>/dev/null)
    local deleted=0
    
    for metrics_file in "${METRICS_DIR}"/*.jsonl; do
        if [ -f "${metrics_file}" ]; then
            local filename=$(basename "${metrics_file}")
            local file_date=$(echo "${filename}" | grep -oP '\d{4}-\d{2}-\d{2}')
            
            if [ -n "${file_date}" ] && [ "${file_date}" \< "${cutoff_date}" ]; then
                rm -f "${metrics_file}"
                ((deleted++))
            fi
        fi
    done
    
    log_info "monitoring" "Metric cleanup completed" "" "{\"deleted\":${deleted}}"
    return 0
}

export -f get_redis_info
export -f show_tenant_status
export -f list_all_tenants
export -f show_global_stats
export -f get_tenant_status_json
export -f list_all_tenants_json
export -f show_global_stats_json
export -f collect_tenant_metrics
export -f collect_all_metrics
export -f check_tenant_thresholds
export -f get_metric_trend
export -f cleanup_old_metrics
