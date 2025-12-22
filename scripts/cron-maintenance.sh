#!/usr/bin/env bash
#
# CachePilot - Automated Maintenance Script
#
# Performs automated maintenance tasks including certificate renewal,
# health checks, metric collection, and alert management.
# Designed to run via cron.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
REDIS_MGR="/usr/local/bin/cachepilot"
LIB_DIR="${BASE_DIR}/cli/lib"

# Export LIB_DIR for common.sh
export LIB_DIR

# Source required libraries (these will load paths from config)
source "${BASE_DIR}/cli/lib/common.sh"
source "${BASE_DIR}/cli/lib/logger.sh"
source "${BASE_DIR}/cli/lib/health.sh"
source "${BASE_DIR}/cli/lib/alerts.sh"
source "${BASE_DIR}/cli/lib/monitoring.sh"
source "${BASE_DIR}/cli/lib/backup.sh"

# Use configured log directory (loaded from common.sh)
LOG_FILE="${LOGS_DIR}/maintenance-$(date +%Y%m%d).log"

# Initialize directories
mkdir -p "$LOGS_DIR"

# Initialize logging
log_init

#######################################
# Log message to maintenance log file
# Arguments:
#   $* - Message to log
#######################################
log_message() {
    echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"
}

#######################################
# Main maintenance routine
#######################################
main() {
    log_message "=== Starting Redis Maintenance ==="
    log_info "maintenance" "Starting automated maintenance tasks"
    
    # 1. System Health Check
    log_message "Running system health check..."
    local health_status=$(health_check_system 2>&1)
    local health_code=$?
    
    if [ $health_code -eq 0 ]; then
        log_message "✓ System health: HEALTHY"
        log_info "maintenance" "System health check passed"
    elif [ $health_code -eq 1 ]; then
        log_message "⚠ System health: DEGRADED"
        log_warn "maintenance" "System health check shows degraded status"
        echo "$health_status" >> "$LOG_FILE"
    else
        log_message "✗ System health: UNHEALTHY"
        log_error "maintenance" "System health check failed"
        echo "$health_status" >> "$LOG_FILE"
        
        # Create critical alert for unhealthy system
        alert_create "critical" "System health check failed" \
            "Automated maintenance detected unhealthy system status" "" >/dev/null 2>&1
    fi
    
    # 2. Certificate Management
    log_message "Checking certificates..."
    local cert_status=$(health_check_certificates 2>&1)
    local cert_code=$?
    
    if [ $cert_code -eq 0 ]; then
        log_message "✓ All certificates valid"
    elif [ $cert_code -eq 1 ]; then
        log_message "⚠ Certificate warnings detected"
        echo "$cert_status" >> "$LOG_FILE"
    else
        log_message "✗ Certificate issues detected"
        echo "$cert_status" >> "$LOG_FILE"
    fi
    
    log_message "Checking for expiring certificates..."
    "$REDIS_MGR" check-certs >> "$LOG_FILE" 2>&1 || true
    
    log_message "Renewing expiring certificates..."
    "$REDIS_MGR" renew-certs all >> "$LOG_FILE" 2>&1 || true
    
    # 3. Metric Collection
    log_message "Collecting metrics for all tenants..."
    if collect_all_metrics >> "$LOG_FILE" 2>&1; then
        log_message "✓ Metric collection completed"
    else
        log_message "⚠ Metric collection had errors"
        log_warn "maintenance" "Metric collection encountered errors"
    fi
    
    # 4. Alert Management
    log_message "Checking active alerts..."
    local unresolved_alerts=$(alert_list "" "" "false" 2>/dev/null | grep -o '"id"' | wc -l 2>/dev/null || echo "0")
    unresolved_alerts=$(echo "$unresolved_alerts" | tr -d ' \n\r' | head -n1)
    log_message "  Active alerts: ${unresolved_alerts}"
    
    if [[ -n "$unresolved_alerts" ]] && [[ "$unresolved_alerts" -gt 0 ]]; then
        log_warn "maintenance" "There are ${unresolved_alerts} unresolved alerts"
    fi
    
    # 5. Automated Backups
    log_message "Running automated backups..."
    backup_init
    backup_auto_run >> "$LOG_FILE" 2>&1
    log_message "✓ Automated backups completed"
    
    # 6. Cleanup Tasks
    log_message "Running cleanup tasks..."
    
    # Clean up old maintenance logs
    log_message "  Cleaning up old maintenance logs (>30 days)..."
    local deleted_logs=$(find "$LOGS_DIR" -name "maintenance-*.log" -mtime +30 -delete -print | wc -l)
    log_message "  Deleted ${deleted_logs} old maintenance log(s)"
    
    # Clean up old metrics (using configured retention)
    local metrics_retention="${CONFIG_MONITORING[metrics_retention_days]:-7}"
    log_message "  Cleaning up old metrics (>${metrics_retention} days)..."
    cleanup_old_metrics "$metrics_retention" >> "$LOG_FILE" 2>&1
    
    # Clean up old resolved alerts (using configured retention)
    local alert_retention="${CONFIG_MONITORING[alert_retention_days]:-30}"
    log_message "  Cleaning up old resolved alerts (>${alert_retention} days)..."
    alert_cleanup "$alert_retention" >> "$LOG_FILE" 2>&1
    
    # 7. Generate Statistics Report
    log_message "Generating statistics report..."
    "$REDIS_MGR" stats >> "$LOG_FILE" 2>&1 || true
    
    # 8. Disk Space Check
    log_message "Checking disk space..."
    local disk_status=$(health_check_disk_space 2>&1)
    local disk_code=$?
    
    if [ $disk_code -eq 0 ]; then
        log_message "✓ Disk space: OK"
        echo "  ${disk_status}" >> "$LOG_FILE"
    elif [ $disk_code -eq 1 ]; then
        log_message "⚠ Disk space: WARNING"
        echo "  ${disk_status}" >> "$LOG_FILE"
    else
        log_message "✗ Disk space: CRITICAL"
        echo "  ${disk_status}" >> "$LOG_FILE"
    fi
    
    # 9. Docker Status Check
    log_message "Checking Docker daemon..."
    if health_check_docker >> "$LOG_FILE" 2>&1; then
        log_message "✓ Docker daemon: HEALTHY"
    else
        log_message "✗ Docker daemon: UNHEALTHY"
        log_error "maintenance" "Docker daemon health check failed"
    fi
    
    # 10. RedisInsight Health Check
    log_message "Checking RedisInsight instances..."
    local insight_running=0
    local insight_stopped=0
    # Count RedisInsight instances
    local nginx_count=$(docker ps --filter "name=nginx-" --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
    insight_running=${nginx_count}
    log_message "  RedisInsight instances: ${insight_running} running"
    
    # 11. API Service Status Check
    log_message "Checking API service..."
    if systemctl is-active --quiet cachepilot-api 2>/dev/null; then
        log_message "✓ API service: RUNNING"
    else
        log_message "⚠ API service: STOPPED or NOT INSTALLED"
        log_warn "maintenance" "API service is not running"
    fi
    
    # 12. Security Mode Validation
    log_message "Validating tenant security modes..."
    local invalid_modes=0
    local tls_only=$(grep -l "^SECURITY_MODE=tls-only" "${TENANTS_DIR}"/*/config.env 2>/dev/null | wc -l | tr -d ' \n\r' || echo "0")
    local dual_mode=$(grep -l "^SECURITY_MODE=dual-mode" "${TENANTS_DIR}"/*/config.env 2>/dev/null | wc -l | tr -d ' \n\r' || echo "0")
    local plain_only=$(grep -l "^SECURITY_MODE=plain-only" "${TENANTS_DIR}"/*/config.env 2>/dev/null | wc -l | tr -d ' \n\r' || echo "0")
    log_message "  Security modes: TLS-only=${tls_only}, Dual=${dual_mode}, Plain=${plain_only}"
    
    # 13. Persistence Mode Check
    log_message "Checking persistence modes..."
    local memory_only_count=$(grep -l "^PERSISTENCE_MODE=memory-only" "${TENANTS_DIR}"/*/config.env 2>/dev/null | wc -l | tr -d ' \n\r' || echo "0")
    local persistent_count=$(grep -l "^PERSISTENCE_MODE=persistent" "${TENANTS_DIR}"/*/config.env 2>/dev/null | wc -l | tr -d ' \n\r' || echo "0")
    # Count tenants without explicit PERSISTENCE_MODE (defaults to memory-only)
    local total_tenants=$(find "${TENANTS_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' \n\r' || echo "0")
    memory_only_count=$((total_tenants - persistent_count))
    log_message "  Persistence: Memory-only=${memory_only_count}, Persistent=${persistent_count}"
    
    # 14. Error Pattern Analysis
    log_message "Analyzing error patterns..."
    local error_count=0
    if command -v log_get_errors &>/dev/null; then
        error_count=$(log_get_errors 100 2>/dev/null | grep -c '"level":"ERROR"' | tr -d ' \n\r' || echo "0")
    fi
    log_message "  Recent errors (last 100 entries): ${error_count}"
    if [[ -n "$error_count" ]] && [[ "$error_count" -gt 10 ]]; then
        log_warn "maintenance" "High error count detected: ${error_count} errors in last 100 log entries"
    fi
    
    # Final Summary
    log_message "=== Maintenance Complete ==="
    log_info "maintenance" "Automated maintenance tasks completed"
    
    # Log comprehensive summary to structured log
    log_info "maintenance" "Maintenance summary" "" "{\"health_code\":${health_code},\"cert_code\":${cert_code},\"disk_code\":${disk_code},\"unresolved_alerts\":${unresolved_alerts},\"insight_running\":${insight_running},\"insight_stopped\":${insight_stopped},\"security_invalid\":${invalid_modes},\"memory_only\":${memory_only_count},\"persistent\":${persistent_count},\"recent_errors\":${error_count}}"
}

# Run main maintenance routine
main

exit 0
