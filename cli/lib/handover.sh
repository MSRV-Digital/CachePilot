#!/usr/bin/env bash
#
# CachePilot - Customer Handover Package Generator
#

generate_handover() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    local handover_dir="${tenant_dir}/handover"
    local temp_dir="${handover_dir}/temp"
    
    source "${tenant_dir}/config.env"
    
    INSIGHT_PORT="${INSIGHT_PORT:-0}"
    INSIGHT_USER="${INSIGHT_USER:-}"
    INSIGHT_PASS="${INSIGHT_PASS:-}"
    SECURITY_MODE="${SECURITY_MODE:-tls-only}"
    PORT_TLS="${PORT_TLS:-${PORT:-}}"
    PORT_PLAIN="${PORT_PLAIN:-}"
    
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    cp "${CA_DIR}/ca.crt" "${temp_dir}/redis-ca.pem"
    
    cat > "${temp_dir}/credentials.txt" << EOF
Redis Connection Details
========================

Security Mode: $SECURITY_MODE
Host: ${INTERNAL_IP}
Password: $PASSWORD

EOF

    case "$SECURITY_MODE" in
        "tls-only")
            cat >> "${temp_dir}/credentials.txt" << EOF
TLS Connection (Recommended):
  Port: $PORT_TLS
  Requires: CA Certificate (redis-ca.pem)
  Connection String: rediss://:$PASSWORD@${INTERNAL_IP}:$PORT_TLS
EOF
            ;;
        "dual-mode")
            cat >> "${temp_dir}/credentials.txt" << EOF
TLS Connection (Recommended):
  Port: $PORT_TLS
  Requires: CA Certificate (redis-ca.pem)
  Connection String: rediss://:$PASSWORD@${INTERNAL_IP}:$PORT_TLS

Plain-Text Connection (Alternative):
  Port: $PORT_PLAIN
  No certificate required (password only)
  Connection String: redis://:$PASSWORD@${INTERNAL_IP}:$PORT_PLAIN
  Warning: Not encrypted in transit
EOF
            ;;
        "plain-only")
            cat >> "${temp_dir}/credentials.txt" << EOF
Plain-Text Connection:
  Port: $PORT_PLAIN
  No certificate required (password only)
  Connection String: redis://:$PASSWORD@${INTERNAL_IP}:$PORT_PLAIN
  Warning: Not encrypted in transit
EOF
            ;;
    esac

    cat >> "${temp_dir}/credentials.txt" << EOF

Created: $CREATED
Tenant: $tenant

Contact:
--------
MSRV Digital
Patrick Schlesinger
Mail: cachepilot@msrv-digital.de
Web: https://msrv-digital.de

RedisInsight:
-------------
Status: $(if [[ -n "${INSIGHT_PORT}" ]] && [[ "${INSIGHT_PORT}" != "0" ]]; then echo "Enabled"; else echo "Disabled"; fi)
$(if [[ -n "${INSIGHT_PORT}" ]] && [[ "${INSIGHT_PORT}" != "0" ]]; then echo "Public URL: https://${PUBLIC_IP}:${INSIGHT_PORT}"; echo "Internal URL: https://${INTERNAL_IP}:${INSIGHT_PORT}"; echo "Username: ${INSIGHT_USER:-admin}"; echo "Password: ${INSIGHT_PASS}"; echo ""; echo "Redis Host (in RedisInsight): redis-${tenant}"; echo "Redis Port (in RedisInsight): 6379"; echo "Redis Password: Use the password above"; echo "Note: Accept the self-signed certificate warning in your browser"; fi)
EOF
    
    cat > "${temp_dir}/README.md" << EOF
# Redis Connection Setup

## Files Included

- redis-ca.pem - TLS CA certificate
- credentials.txt - Connection details and password
- README.md - This file

## WordPress Setup (TLS Mode)

### 1. Install Plugin
Install "Redis Object Cache" plugin from wordpress.org

### 2. Upload Certificate
\`\`\`bash
mkdir -p /var/www/html/redis
cp redis-ca.pem /var/www/html/redis/
chmod 644 /var/www/html/redis/redis-ca.pem
\`\`\`

### 3. Configure wp-config.php
\`\`\`php
define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_SCHEME', 'tls');
define('WP_REDIS_HOST', '${INTERNAL_IP}');
define('WP_REDIS_PORT', $PORT_TLS);
define('WP_REDIS_PASSWORD', '$PASSWORD');
define('WP_REDIS_PREFIX', 'wp:');

\$redis_options = [
    'verify_peer' => true,
    'verify_peer_name' => true,
    'cafile' => ABSPATH . 'redis/redis-ca.pem'
];
define('WP_REDIS_SSL_CONTEXT', \$redis_options);
\`\`\`

### 4. Enable Cache
Go to WordPress Admin → Settings → Redis → Enable Object Cache

## Plain-Text Mode (If Available)

\`\`\`php
define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_HOST', '${INTERNAL_IP}');
define('WP_REDIS_PORT', ${PORT_PLAIN:-$PORT_TLS});
define('WP_REDIS_PASSWORD', '$PASSWORD');
define('WP_REDIS_PREFIX', 'wp:');
\`\`\`

## Troubleshooting

1. Verify phpredis extension: \`php -m | grep redis\`
2. Check file permissions on ca.pem
3. Verify port accessibility from server

## Support

**MSRV Digital**
Patrick Schlesinger
- Email: cachepilot@msrv-digital.de
- Web: https://msrv-digital.de
EOF
    
    cd "$handover_dir"
    zip -q -r "${tenant}-handover.zip" temp/
    
    rm -rf "$temp_dir"
    
    log "Handover package created: ${handover_dir}/${tenant}-handover.zip"
}
