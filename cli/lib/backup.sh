#!/usr/bin/env bash
#
# CachePilot - Backup & Restore Library
#
# Manages automated and manual backups of tenant data with configurable
# retention, compression, and verification capabilities.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

BACKUP_DIR="${BACKUPS_DIR:-/var/cachepilot/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_MAX_COUNT="${BACKUP_MAX_COUNT:-50}"

backup_init() {
    BACKUP_DIR="${BACKUPS_DIR:-${BACKUP_DIR}}"
    mkdir -p "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR" 2>/dev/null || true
    log_debug "backup" "Backup system initialized" "" "{\"dir\":\"$BACKUP_DIR\",\"retention\":$BACKUP_RETENTION_DAYS}"
}

backup_create() {
    local tenant="$1"
    local backup_type="${2:-manual}"
    
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "$tenant_dir" ]; then
        log_error "backup" "Tenant not found" "$tenant"
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${tenant}_${timestamp}.tar.gz"
    
    log_info "backup" "Creating backup" "$tenant" "{\"type\":\"$backup_type\",\"file\":\"$backup_file\"}"
    
    if tar -czf "$backup_file" -C "$tenant_dir" . 2>/dev/null; then
        local size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
        log_info "backup" "Backup created successfully" "$tenant" "{\"file\":\"$backup_file\",\"size\":$size}"
        log_audit "system" "backup_created" "$tenant" "{\"file\":\"$backup_file\",\"type\":\"$backup_type\"}"
        
        echo "$timestamp" > "$tenant_dir/LAST_BACKUP"
        
        backup_cleanup "$tenant"
        return 0
    else
        log_error "backup" "Backup creation failed" "$tenant"
        rm -f "$backup_file"
        return 1
    fi
}

backup_restore() {
    local tenant="$1"
    local backup_file="$2"
    
    require_tenant "$tenant"
    
    if [ ! -f "$backup_file" ]; then
        log_error "backup" "Backup file not found" "$tenant" "{\"file\":\"$backup_file\"}"
        return 1
    fi
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "$tenant_dir" ]; then
        log_error "backup" "Tenant not found" "$tenant"
        return 1
    fi
    
    log_warn "backup" "Starting backup restore" "$tenant" "{\"file\":\"$backup_file\"}"
    
    local backup_temp="$tenant_dir.backup_$(date +%s)"
    mv "$tenant_dir" "$backup_temp"
    
    mkdir -p "$tenant_dir"
    
    if tar -xzf "$backup_file" -C "$tenant_dir" 2>/dev/null; then
        log_info "backup" "Backup restored successfully" "$tenant"
        log_audit "system" "backup_restored" "$tenant" "{\"file\":\"$backup_file\"}"
        rm -rf "$backup_temp"
        return 0
    else
        log_error "backup" "Backup restore failed, rolling back" "$tenant"
        rm -rf "$tenant_dir"
        mv "$backup_temp" "$tenant_dir"
        return 1
    fi
}

backup_list() {
    local tenant="$1"
    local format="${2:-text}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        if [ "$format" = "json" ]; then
            echo '{"backups":[]}'
        fi
        return 0
    fi
    
    if [ "$format" = "json" ]; then
        echo -n '{"backups":['
        local first=true
        for backup in "$BACKUP_DIR/${tenant}_"*.tar.gz; do
            [ -f "$backup" ] || continue
            local filename=$(basename "$backup")
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null)
            local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
            
            if [ "$first" = true ]; then
                first=false
            else
                echo -n ','
            fi
            echo -n "{\"file\":\"$filename\",\"size\":$size,\"timestamp\":$mtime}"
        done
        echo ']}'
    else
        ls -lh "$BACKUP_DIR/${tenant}_"*.tar.gz 2>/dev/null | awk '{print $9, $5, $6, $7, $8}'
    fi
}

backup_verify() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log_error "backup" "Backup file not found for verification" "" "{\"file\":\"$backup_file\"}"
        return 1
    fi
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_debug "backup" "Backup verification passed" "" "{\"file\":\"$backup_file\"}"
        return 0
    else
        log_error "backup" "Backup verification failed" "" "{\"file\":\"$backup_file\"}"
        return 1
    fi
}

backup_cleanup() {
    local tenant="$1"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        return 0
    fi
    
    local count=0
    local deleted=0
    
    while IFS= read -r backup; do
        [ -f "$backup" ] || continue
        count=$((count + 1))
        
        local mtime=$(stat -f%m "$backup" 2>/dev/null || stat -c%Y "$backup" 2>/dev/null)
        local age_days=$(( ($(date +%s) - mtime) / 86400 ))
        
        if [ $age_days -gt $BACKUP_RETENTION_DAYS ] || [ $count -gt $BACKUP_MAX_COUNT ]; then
            log_info "backup" "Removing old backup" "$tenant" "{\"file\":\"$(basename "$backup")\",\"age_days\":$age_days}"
            rm -f "$backup"
            deleted=$((deleted + 1))
        fi
    done < <(ls -t "$BACKUP_DIR/${tenant}_"*.tar.gz 2>/dev/null || true)
    
    if [ $deleted -gt 0 ]; then
        log_info "backup" "Cleanup completed" "$tenant" "{\"deleted\":$deleted}"
    fi
}

backup_schedule_enable() {
    local tenant="$1"
    local schedule="${2:-daily}"
    
    log_info "backup" "Enabling backup schedule" "$tenant" "{\"schedule\":\"$schedule\"}"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "$tenant_dir" ]; then
        log_error "backup" "Tenant not found" "$tenant"
        return 1
    fi
    
    echo "BACKUP_ENABLED=true" >> "$tenant_dir/config.env"
    echo "BACKUP_SCHEDULE=$schedule" >> "$tenant_dir/config.env"
    
    log_audit "system" "backup_schedule_enabled" "$tenant" "{\"schedule\":\"$schedule\"}"
    return 0
}

backup_schedule_disable() {
    local tenant="$1"
    
    log_info "backup" "Disabling backup schedule" "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "$tenant_dir" ]; then
        log_error "backup" "Tenant not found" "$tenant"
        return 1
    fi
    
    sed -i '/BACKUP_ENABLED=/d' "$tenant_dir/config.env"
    sed -i '/BACKUP_SCHEDULE=/d' "$tenant_dir/config.env"
    
    log_audit "system" "backup_schedule_disabled" "$tenant" "{}"
    return 0
}

backup_get_last() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    
    if [ -f "$tenant_dir/LAST_BACKUP" ]; then
        cat "$tenant_dir/LAST_BACKUP"
    else
        echo "never"
    fi
}

backup_health_check() {
    local tenant="$1"
    local issues=()
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    if [ ! -d "$tenant_dir" ]; then
        echo "error:tenant_not_found"
        return 1
    fi
    
    local last_backup=$(backup_get_last "$tenant")
    if [ "$last_backup" = "never" ]; then
        issues+=("no_backup_exists")
    else
        local backup_age=$(( ($(date +%s) - $(date -d "$last_backup" +%s 2>/dev/null || echo 0)) / 86400 ))
        if [ $backup_age -gt 7 ]; then
            issues+=("backup_too_old:${backup_age}_days")
        fi
    fi
    
    local backup_count=$(ls -1 "$BACKUP_DIR/${tenant}_"*.tar.gz 2>/dev/null | wc -l)
    if [ $backup_count -eq 0 ]; then
        issues+=("no_backups_found")
    fi
    
    if [ ${#issues[@]} -eq 0 ]; then
        echo "healthy"
        return 0
    else
        echo "issues:${issues[*]}"
        return 1
    fi
}

backup_auto_run() {
    log_info "backup" "Running automated backup for all tenants" ""
    
    local success=0
    local failed=0
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        [ -d "$tenant_dir" ] || continue
        local tenant=$(basename "$tenant_dir")
        
        if [ -f "$tenant_dir/config.env" ]; then
            source "$tenant_dir/config.env"
            
            if [ "${BACKUP_ENABLED:-false}" = "true" ]; then
                if backup_create "$tenant" "auto"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
            fi
        fi
    done
    
    log_info "backup" "Automated backup completed" "" "{\"success\":$success,\"failed\":$failed}"
}

backup_status_overview() {
    local format="${1:-text}"
    
    if [ "$format" = "json" ]; then
        echo -n '{"tenants":['
        local first=true
        
        for tenant_dir in "${TENANTS_DIR}"/*; do
            [ -d "$tenant_dir" ] || continue
            local tenant=$(basename "$tenant_dir")
            
            local enabled="false"
            local schedule="-"
            local last_backup="never"
            
            if [ -f "$tenant_dir/config.env" ]; then
                source "$tenant_dir/config.env"
                enabled="${BACKUP_ENABLED:-false}"
                schedule="${BACKUP_SCHEDULE:--}"
            fi
            
            last_backup=$(backup_get_last "$tenant")
            
            if [ "$first" = true ]; then
                first=false
            else
                echo -n ','
            fi
            
            echo -n "{\"tenant\":\"$tenant\",\"enabled\":$enabled,\"schedule\":\"$schedule\",\"last_backup\":\"$last_backup\"}"
        done
        
        echo ']}'
    else
        printf "%-20s %-12s %-10s %-20s\n" "TENANT" "ENABLED" "SCHEDULE" "LAST BACKUP"
        printf "%-20s %-12s %-10s %-20s\n" "──────────────────" "──────────" "────────" "──────────────────"
        
        for tenant_dir in "${TENANTS_DIR}"/*; do
            [ -d "$tenant_dir" ] || continue
            local tenant=$(basename "$tenant_dir")
            
            local enabled="No"
            local enabled_icon="✗"
            local schedule="-"
            local last_backup="never"
            
            if [ -f "$tenant_dir/config.env" ]; then
                source "$tenant_dir/config.env"
                if [ "${BACKUP_ENABLED:-false}" = "true" ]; then
                    enabled="Yes"
                    enabled_icon="✓"
                fi
                schedule="${BACKUP_SCHEDULE:--}"
            fi
            
            last_backup=$(backup_get_last "$tenant")
            
            printf "%-20s %-12s %-10s %-20s\n" "$tenant" "$enabled_icon $enabled" "$schedule" "$last_backup"
        done
    fi
}

backup_enable_all() {
    log_info "backup" "Enabling backups for all tenants without backup"
    
    local enabled=0
    local skipped=0
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        [ -d "$tenant_dir" ] || continue
        local tenant=$(basename "$tenant_dir")
        
        if [ -f "$tenant_dir/config.env" ]; then
            source "$tenant_dir/config.env"
            
            if [ "${BACKUP_ENABLED:-false}" != "true" ]; then
                if backup_schedule_enable "$tenant" "daily"; then
                    enabled=$((enabled + 1))
                fi
            else
                skipped=$((skipped + 1))
            fi
        fi
    done
    
    log_info "backup" "Bulk enable completed" "" "{\"enabled\":$enabled,\"skipped\":$skipped}"
    echo "Enabled backups for $enabled tenant(s), skipped $skipped already enabled"
}
