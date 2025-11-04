#!/usr/bin/env bash
#
# CachePilot - Certificate Management Library
#
# Manages TLS certificates for Redis instances, including CA generation,
# tenant certificate creation, renewal, and expiration checks.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

generate_ca() {
    mkdir -p "${CA_DIR}"
    chmod 700 "${CA_DIR}" 2>/dev/null || true
    
    local ca_key="${CA_DIR}/ca.key"
    local ca_cert="${CA_DIR}/ca.crt"
    
    openssl genrsa -out "$ca_key" 4096
    openssl req -new -x509 -days 3650 -key "$ca_key" -out "$ca_cert" \
        -subj "/C=DE/ST=Bavaria/L=Munich/O=MSRV Digital/CN=Redis-CA"
    
    chmod 600 "$ca_key"
    chmod 644 "$ca_cert"
}

generate_tenant_cert() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    local certs_dir="${tenant_dir}/certs"
    
    mkdir -p "$certs_dir"
    
    local key="${certs_dir}/redis.key"
    local csr="${certs_dir}/redis.csr"
    local cert="${certs_dir}/redis.crt"
    local ca_key="${CA_DIR}/ca.key"
    local ca_cert="${CA_DIR}/ca.crt"
    
    if [[ ! -f "$ca_cert" ]] || [[ ! -f "$ca_key" ]]; then
        log_info "certs" "CA certificate not found, generating new CA..." "$tenant"
        generate_ca
    fi
    
    openssl genrsa -out "$key" 2048
    
    openssl req -new -key "$key" -out "$csr" \
        -subj "/C=DE/ST=Bavaria/L=Munich/O=MSRV Digital/CN=${tenant}.redis"
    
    cat > "${certs_dir}/ext.cnf" << EOF
basicConstraints=CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
subjectAltName=DNS:${tenant}.redis,DNS:localhost,IP:127.0.0.1
EOF
    
    openssl x509 -req -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" \
        -CAcreateserial -out "$cert" -days 1095 \
        -extfile "${certs_dir}/ext.cnf"
    
    cp "$ca_cert" "${certs_dir}/ca.crt"
    
    chmod 644 "$key"
    chmod 644 "$cert"
    chmod 644 "${certs_dir}/ca.crt"
    
    rm -f "$csr" "${certs_dir}/ext.cnf"
}

check_cert_expiry() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        echo "0"
        return
    fi
    
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    echo "$days_left"
}

renew_tenant_cert() {
    local tenant="$1"
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    local cert="${tenant_dir}/certs/redis.crt"
    
    local days_left=$(check_cert_expiry "$cert")
    
    if [[ $days_left -lt 30 ]]; then
        log "Renewing certificate for tenant: $tenant (expires in $days_left days)"
        generate_tenant_cert "$tenant"
        
        if docker ps --format '{{.Names}}' | grep -q "^redis-${tenant}$"; then
            log "Restarting container to apply new certificate..."
            docker restart "redis-${tenant}"
        fi
        
        generate_handover "$tenant"
        success "Certificate renewed for tenant: $tenant"
    else
        log "Certificate for tenant $tenant is still valid ($days_left days left)"
    fi
}

renew_all_certs() {
    log "Checking certificates for all tenants..."
    
    local renewed=0
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [[ -d "$tenant_dir" ]]; then
            local tenant=$(basename "$tenant_dir")
            local cert="${tenant_dir}/certs/redis.crt"
            local days_left=$(check_cert_expiry "$cert")
            
            if [[ $days_left -lt 30 ]]; then
                renew_tenant_cert "$tenant"
                ((renewed++))
            fi
        fi
    done
    
    if [[ $renewed -eq 0 ]]; then
        success "All certificates are valid"
    else
        success "Renewed $renewed certificate(s)"
    fi
}

renew_expiring_certs() {
    renew_all_certs
}

check_all_certs() {
    log "Certificate Status Report"
    echo ""
    printf "%-20s %-15s %-20s\n" "TENANT" "DAYS LEFT" "EXPIRY DATE"
    printf "%-20s %-15s %-20s\n" "--------------------" "---------------" "--------------------"
    
    local ca_cert="${CA_DIR}/ca.crt"
    if [[ -f "$ca_cert" ]]; then
        local ca_days=$(check_cert_expiry "$ca_cert")
        local ca_expiry=$(openssl x509 -in "$ca_cert" -noout -enddate | cut -d= -f2)
        printf "%-20s %-15s %-20s\n" "CA Certificate" "$ca_days" "$(date -d "$ca_expiry" +%Y-%m-%d)"
    fi
    
    for tenant_dir in "${TENANTS_DIR}"/*; do
        if [[ -d "$tenant_dir" ]]; then
            local tenant=$(basename "$tenant_dir")
            local cert="${tenant_dir}/certs/redis.crt"
            
            if [[ -f "$cert" ]]; then
                local days_left=$(check_cert_expiry "$cert")
                local expiry=$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)
                local status=""
                
                if [[ $days_left -lt 30 ]]; then
                    status="${RED}EXPIRING SOON${NC}"
                elif [[ $days_left -lt 90 ]]; then
                    status="${YELLOW}WARNING${NC}"
                else
                    status="${GREEN}OK${NC}"
                fi
                
                printf "%-20s %-15s %-20s %b\n" "$tenant" "$days_left" "$(date -d "$expiry" +%Y-%m-%d)" "$status"
            fi
        fi
    done
    echo ""
}
