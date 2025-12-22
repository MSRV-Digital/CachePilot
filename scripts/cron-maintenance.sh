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
    local unresolved_alerts=$(alert_list "" "" "false" 2>/dev/null | grep -o '"id"' | wc -l || echo "0")
    log_message "  Active alerts: ${unresolved_alerts}"
    
    if [ ${unresolved_alerts} -gt 0 ]; then
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
    
    # Clean up old metrics
    log_message "  Cleaning up old metrics (>7 days)..."
    cleanup_old_metrics 7 >> "$LOG_FILE" 2>&1
    
    # Clean up old resolved alerts
    log_message "  Cleaning up old resolved alerts (>30 days)..."
    alert_cleanup 30 >> "$LOG_FILE" 2>&1
    
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
    
    # Final Summary
    log_message "=== Maintenance Complete ==="
    log_info "maintenance" "Automated maintenance tasks completed"
    
    # Log summary to structured log
    log_info "maintenance" "Maintenance summary" "" "{\"health_code\":${health_code},\"cert_code\":${cert_code},\"disk_code\":${disk_code},\"unresolved_alerts\":${unresolved_alerts}}"
}

# Run main maintenance routine
main

exit 0
