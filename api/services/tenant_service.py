"""
CachePilot - Tenant Service

Business logic for tenant lifecycle management including creation, updates,
deletion, configuration, and operational control.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from typing import List, Optional, Dict, Any
from api.utils.executor import executor
from api.config import settings
from api.models import TenantCreateRequest, TenantUpdateRequest, TenantResponse
from api.utils.input_sanitization import (
    sanitize_tenant_name,
    sanitize_file_path,
    validate_memory_limit,
    validate_port,
    ValidationError
)
import json
import re
import logging

logger = logging.getLogger(__name__)

class TenantService:
    def __init__(self):
        """Initialize tenant service with configuration"""
        self.settings = settings
    
    def create_tenant(self, request: TenantCreateRequest) -> Dict[str, Any]:
        try:
            validated_name = sanitize_tenant_name(request.tenant_name)
            validate_memory_limit(request.maxmemory_mb)
            validate_memory_limit(request.docker_limit_mb)
        except ValidationError as e:
            logger.warning(f"Tenant creation validation failed: {e}")
            return {
                "success": False,
                "message": "Validation error",
                "error": str(e)
            }
        
        args = [
            validated_name,
            str(request.maxmemory_mb),
            str(request.docker_limit_mb)
        ]
        
        if request.password:
            args.append(request.password)
        
        # Use extended timeout for tenant creation (container setup can take time)
        success, stdout, stderr = executor.execute_with_timeout("new", 120, *args)
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {validated_name} created successfully",
                "data": {"tenant": validated_name}
            }
        else:
            return {
                "success": False,
                "message": "Failed to create tenant",
                "error": "Tenant creation failed"
            }
    
    def get_tenant(self, name: str) -> Dict[str, Any]:
        from pathlib import Path
        
        try:
            validated_name = sanitize_tenant_name(name)
        except ValidationError as e:
            logger.warning(f"Tenant name validation failed: {e}")
            return {
                "success": False,
                "message": "Invalid tenant name",
                "error": str(e)
            }
        
        # Use configured tenants directory
        tenants_dir = self.settings.tenants_dir
        
        try:
            tenant_dir_str = sanitize_file_path(validated_name, tenants_dir)
            tenant_dir = Path(tenant_dir_str)
        except ValidationError as e:
            logger.warning(f"Path validation failed: {e}")
            return {
                "success": False,
                "message": "Invalid tenant path",
                "error": "Path validation failed"
            }
        
        if not tenant_dir.exists():
            return {
                "success": False,
                "message": "Tenant not found",
                "error": f"Tenant {name} does not exist"
            }
        
        # Read config.env file for basic info
        config_file = tenant_dir / 'config.env'
        if not config_file.exists():
            return {
                "success": False,
                "message": "Tenant configuration not found",
                "error": f"Configuration file not found for tenant {name}"
            }
        
        config = {}
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key] = value
        
        # Get status from CLI
        success, stdout, stderr = executor.execute("status", name)
        status_info = self._parse_status(stdout) if success else {}
        
        # Determine status - map CLI output to expected values
        cli_status = status_info.get('status', 'unknown').lower()
        if 'running' in cli_status or 'ok' in cli_status or cli_status == 'healthy':
            status = 'running'
        elif 'stopped' in cli_status:
            status = 'stopped'
        else:
            status = 'unknown'
        
        # Parse uptime if available (handle both seconds and formatted strings)
        uptime_seconds = 0
        if status_info.get('uptime'):
            uptime_str = status_info.get('uptime', '0')
            # Try to parse as integer first (if it's just seconds)
            try:
                # Remove any non-numeric characters except first digit
                if uptime_str.strip():
                    # Handle formats like "12m", "12h", "12h 34m"
                    parts = uptime_str.split()
                    for part in parts:
                        if 'h' in part:
                            hours = int(part.replace('h', ''))
                            uptime_seconds += hours * 3600
                        elif 'm' in part:
                            minutes = int(part.replace('m', ''))
                            uptime_seconds += minutes * 60
                        elif 's' in part:
                            seconds = int(part.replace('s', ''))
                            uptime_seconds += seconds
                        else:
                            # Just a number, assume seconds
                            uptime_seconds = int(part)
            except (ValueError, AttributeError):
                uptime_seconds = 0
        
        tenant_data = {
            "tenant": name,
            "port": config.get('PORT', ''),
            "status": status,
            "memory_used": status_info.get('memory_used'),
            "clients": status_info.get('connected_clients', '0'),
            "keys": status_info.get('total_keys', '0'),
            "uptime_seconds": uptime_seconds,
            "maxmemory": int(config.get('MAXMEMORY', '256')),
            "docker_limit": int(config.get('DOCKER_LIMIT', '512'))
        }
        
        return {
            "success": True,
            "message": "Tenant status retrieved",
            "data": tenant_data
        }
    
    def list_tenants(self) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("list")
        
        if success:
            tenants = self._parse_tenant_list(stdout)
            return {
                "success": True,
                "message": f"Found {len(tenants)} tenants",
                "data": {"tenants": tenants}
            }
        else:
            return {
                "success": False,
                "message": "Failed to list tenants",
                "error": stderr
            }
    
    def update_tenant(self, name: str, updates: TenantUpdateRequest) -> Dict[str, Any]:
        try:
            validated_name = sanitize_tenant_name(name)
            if updates.maxmemory_mb is not None:
                validate_memory_limit(updates.maxmemory_mb)
            if updates.docker_limit_mb is not None:
                validate_memory_limit(updates.docker_limit_mb)
        except ValidationError as e:
            logger.warning(f"Tenant update validation failed: {e}")
            return {
                "success": False,
                "message": "Validation error",
                "error": str(e)
            }
        
        if updates.maxmemory_mb is not None and updates.docker_limit_mb is not None:
            success, stdout, stderr = executor.execute(
                "set-memory",
                validated_name,
                str(updates.maxmemory_mb),
                str(updates.docker_limit_mb)
            )
        elif updates.maxmemory_mb is not None:
            success, stdout, stderr = executor.execute(
                "set-memory",
                validated_name,
                str(updates.maxmemory_mb)
            )
        else:
            return {
                "success": False,
                "message": "No updates provided",
                "error": "At least one field must be updated"
            }
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {name} updated successfully",
                "data": {"tenant": name}
            }
        else:
            return {
                "success": False,
                "message": "Failed to update tenant",
                "error": stderr or stdout
            }
    
    def delete_tenant(self, name: str, force: bool = False) -> Dict[str, Any]:
        try:
            validated_name = sanitize_tenant_name(name)
        except ValidationError as e:
            logger.warning(f"Tenant deletion validation failed: {e}")
            return {
                "success": False,
                "message": "Invalid tenant name",
                "error": str(e)
            }
        
        if force:
            success, stdout, stderr = executor.execute("rm", validated_name, "--force")
        else:
            success, stdout, stderr = executor.execute("rm", validated_name)
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {validated_name} deleted successfully",
                "data": {"tenant": validated_name}
            }
        else:
            return {
                "success": False,
                "message": "Failed to delete tenant",
                "error": stderr or "Tenant deletion failed"
            }
    
    def start_tenant(self, name: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("start", name)
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {name} started successfully",
                "data": {"tenant": name, "status": "running"}
            }
        else:
            return {
                "success": False,
                "message": "Failed to start tenant",
                "error": stderr or stdout
            }
    
    def stop_tenant(self, name: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("stop", name)
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {name} stopped successfully",
                "data": {"tenant": name, "status": "stopped"}
            }
        else:
            return {
                "success": False,
                "message": "Failed to stop tenant",
                "error": stderr or stdout
            }
    
    def restart_tenant(self, name: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("restart", name)
        
        if success:
            return {
                "success": True,
                "message": f"Tenant {name} restarted successfully",
                "data": {"tenant": name, "status": "running"}
            }
        else:
            return {
                "success": False,
                "message": "Failed to restart tenant",
                "error": stderr or stdout
            }
    
    def rotate_password(self, name: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("rotate", name)
        
        if success:
            new_password = stdout.strip().split(":")[-1].strip()
            return {
                "success": True,
                "message": f"Password rotated for tenant {name}",
                "data": {"tenant": name, "new_password": new_password}
            }
        else:
            return {
                "success": False,
                "message": "Failed to rotate password",
                "error": stderr or stdout
            }
    
    def get_handover_info(self, name: str) -> Dict[str, Any]:
        """Get handover information for a tenant including connection details"""
        import yaml
        from pathlib import Path
        
        # Get tenant directory using configured path
        tenants_dir = self.settings.tenants_dir
        tenant_dir = Path(tenants_dir) / name
        
        if not tenant_dir.exists():
            return {
                "success": False,
                "message": "Tenant not found",
                "error": f"Tenant {name} does not exist"
            }
        
        # Read config.env file
        config_file = tenant_dir / 'config.env'
        if not config_file.exists():
            return {
                "success": False,
                "message": "Tenant configuration not found",
                "error": f"Configuration file not found for tenant {name}"
            }
        
        config = {}
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key] = value
        
        system_config_file = Path(self.settings.config_dir) / 'system.yaml'
        internal_ip = 'localhost'
        public_ip = 'not-configured'
        org_name = 'Organization'
        contact_name = 'Administrator'
        contact_email = 'admin@example.com'
        contact_phone = 'not-configured'
        contact_web = 'not-configured'
        
        if system_config_file.exists():
            with open(system_config_file, 'r') as f:
                system_config = yaml.safe_load(f)
                if system_config:
                    if 'network' in system_config:
                        internal_ip = system_config['network'].get('internal_ip', internal_ip)
                        public_ip = system_config['network'].get('public_ip', public_ip)
                    if 'organization' in system_config:
                        org_name = system_config['organization'].get('name', org_name)
                        contact_name = system_config['organization'].get('contact_name', contact_name)
                        contact_email = system_config['organization'].get('contact_email', contact_email)
                        contact_phone = system_config['organization'].get('contact_phone', contact_phone)
                        contact_web = system_config['organization'].get('contact_web', contact_web)
        
        # Load CA certificate using configured path
        ca_cert_path = Path(self.settings.ca_dir) / 'ca.crt'
        ca_certificate = ""
        if ca_cert_path.exists():
            with open(ca_cert_path, 'r') as f:
                ca_certificate = f.read()
        
        port = config.get('PORT', '6379')
        password = config.get('PASSWORD', '')
        
        # Generate full WordPress configuration
        wp_config_full = f"""// Redis Object Cache Configuration
define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_SCHEME', 'tls');
define('WP_REDIS_HOST', '{internal_ip}');
define('WP_REDIS_PORT', {port});
define('WP_REDIS_PASSWORD', '{password}');
define('WP_REDIS_PREFIX', 'wp:');
define('WP_REDIS_DATABASE', 0);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);

// TLS Configuration
$redis_tls_options = [
    'verify_peer' => true,
    'verify_peer_name' => true,
    'cafile' => ABSPATH . 'redis/ca.crt'
];
define('WP_REDIS_SSL_CONTEXT', $redis_tls_options);"""
        
        # Generate credentials text
        credentials_text = f"""===========================================
Redis Connection Details

Tenant: {name}
Created: {config.get('CREATED', 'N/A')}

Connection:
-----------
Internal Host: {internal_ip}
Public Host: {public_ip}
Port: {port}
Password: {password}

TLS: Enabled
CA Certificate: Required (see below)

Memory Limits:
--------------
Redis Maxmemory: {config.get('MAXMEMORY', '256')} MB
Docker Limit: {config.get('DOCKER_LIMIT', '512')} MB

Contact:
--------
{org_name}
{contact_name}
Email: {contact_email}
Phone: {contact_phone}
Web: {contact_web}
"""
        
        # Get tenant status
        success, stdout, stderr = executor.execute("status", name)
        tenant_status = self._parse_status(stdout) if success else {}
        
        # Get handover package path
        handover_dir = tenant_dir / 'handover'
        handover_file = handover_dir / f'{name}-handover.zip'
        
        handover_data = {
            "tenant": name,
            "host": internal_ip,
            "public_host": public_ip,
            "port": port,
            "password": password,
            "tls_enabled": True,
            "ca_certificate": ca_certificate,
            "connection_string": f"rediss://:{password}@{internal_ip}:{port}",
            "status": tenant_status.get('status', 'unknown'),
            "handover_package": str(handover_file) if handover_file.exists() else None,
            "wordpress_config": {
                "host": internal_ip,
                "port": int(port),
                "password": password,
                "database": 0,
                "timeout": 1,
                "read_timeout": 1,
                "full_config": wp_config_full
            },
            "credentials_text": credentials_text
        }
        
        return {
            "success": True,
            "message": "Handover information retrieved",
            "data": handover_data
        }
    
    def regenerate_handover(self, name: str) -> Dict[str, Any]:
        """Regenerate handover package for a tenant"""
        success, stdout, stderr = executor.execute("handover", name)
        
        if success:
            return {
                "success": True,
                "message": f"Handover package regenerated for tenant {name}",
                "data": {"tenant": name}
            }
        else:
            return {
                "success": False,
                "message": "Failed to regenerate handover package",
                "error": "Handover regeneration failed"
            }
    
    def _parse_status(self, output: str) -> Dict[str, Any]:
        # Strip ANSI escape codes
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        output = ansi_escape.sub('', output)
        
        lines = output.strip().split('\n')
        status = {}
        
        for line in lines:
            if ':' in line:
                key, value = line.split(':', 1)
                clean_key = key.strip().lower().replace(' ', '_')
                clean_value = value.strip()
                status[clean_key] = clean_value
        
        return status
    
    def _parse_tenant_list(self, output: str) -> List[Dict[str, str]]:
        # Strip ANSI escape codes
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        output = ansi_escape.sub('', output)
        
        lines = output.strip().split('\n')
        tenants = []
        
        # Skip header and separator lines
        for line in lines[2:]:
            if line.strip() and not line.startswith('-'):
                parts = line.split()
                if len(parts) >= 3:
                    # Skip header row (TENANT, PORT, STATUS)
                    if parts[0].upper() == "TENANT":
                        continue
                    tenants.append({
                        "tenant": parts[0],
                        "port": parts[1],
                        "status": parts[2]
                    })
        
        return tenants

tenant_service = TenantService()
