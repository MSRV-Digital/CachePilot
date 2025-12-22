"""
CachePilot - Tenant Service

Business logic for tenant lifecycle management including creation, updates,
deletion, configuration, and operational control.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
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
            str(request.docker_limit_mb),
            request.security_mode.value
        ]
        
        if request.password:
            args.append(request.password)
        
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
        
        success, stdout, stderr = executor.execute("status", name)
        status_info = self._parse_status(stdout) if success else {}
        
        cli_status = status_info.get('redis_statistics_status', status_info.get('status', 'unknown')).lower()
        if 'running' in cli_status or 'ok' in cli_status or cli_status == 'healthy':
            status = 'running'
        elif 'stopped' in cli_status:
            status = 'stopped'
        else:
            status = 'unknown'
        
        # Parse uptime - now comes from Redis Statistics section
        uptime_seconds = 0
        uptime_str = status_info.get('redis_statistics_uptime', '0')
        try:
            if uptime_str and uptime_str != 'N/A':
                # Handle formats like "12m", "12h", "18h 34m"
                parts = uptime_str.split()
                for part in parts:
                    part = part.strip()
                    if 'd' in part:
                        days = int(part.replace('d', ''))
                        uptime_seconds += days * 86400
                    elif 'h' in part:
                        hours = int(part.replace('h', ''))
                        uptime_seconds += hours * 3600
                    elif 'm' in part:
                        minutes = int(part.replace('m', ''))
                        uptime_seconds += minutes * 60
                    elif 's' in part:
                        seconds = int(part.replace('s', ''))
                        uptime_seconds += seconds
        except (ValueError, AttributeError):
            uptime_seconds = 0
        
        security_mode = config.get('SECURITY_MODE', 'tls-only')
        port_tls = config.get('PORT_TLS', config.get('PORT', ''))
        port_plain = config.get('PORT_PLAIN', '')
        
        tenant_data = {
            "tenant": name,
            "port": port_tls or port_plain,
            "security_mode": security_mode,
            "port_tls": port_tls,
            "port_plain": port_plain,
            "status": status,
            "memory_used": status_info.get('redis_statistics_memory_used', status_info.get('memory_used', 'N/A')),
            "clients": status_info.get('redis_statistics_connected_clients', status_info.get('connected_clients', '0')),
            "keys": status_info.get('redis_statistics_total_keys', status_info.get('total_keys', '0')),
            "uptime_seconds": uptime_seconds,
            "maxmemory": int(config.get('MAXMEMORY', '256')),
            "docker_limit": int(config.get('DOCKER_LIMIT', '512')),
            "total_commands": status_info.get('redis_statistics_total_commands', '0'),
            "keyspace_hits": status_info.get('redis_statistics_keyspace_hits', '0'),
            "keyspace_misses": status_info.get('redis_statistics_keyspace_misses', '0'),
            "hit_rate": status_info.get('redis_statistics_hit_rate', 'N/A'),
            "memory_peak": status_info.get('redis_statistics_memory_peak', 'N/A'),
            "evicted_keys": status_info.get('redis_statistics_evicted_keys', '0')
        }
        
        return {
            "success": True,
            "message": "Tenant status retrieved",
            "data": tenant_data
        }
    
    def list_tenants(self) -> Dict[str, Any]:
        """List all tenants by reading filesystem directly - avoids subprocess timeout"""
        from pathlib import Path
        import subprocess
        
        tenants = []
        tenants_dir = Path(self.settings.tenants_dir)
        
        # Get list of running containers quickly
        try:
            result = subprocess.run(
                ["docker", "ps", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False
            )
            running_containers = set(result.stdout.strip().split('\n')) if result.returncode == 0 else set()
        except:
            running_containers = set()
        
        for tenant_dir in tenants_dir.iterdir():
            if not tenant_dir.is_dir():
                continue
                
            config_file = tenant_dir / 'config.env'
            if not config_file.exists():
                continue
            
            # Read config
            config = {}
            with open(config_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        config[key] = value
            
            tenant_name = tenant_dir.name
            port = config.get('PORT_TLS', config.get('PORT', ''))
            
            # Check if container is running
            status = "running" if f"redis-{tenant_name}" in running_containers else "stopped"
            
            tenants.append({
                "tenant": tenant_name,
                "port": port,
                "status": status,
                "security_mode": config.get('SECURITY_MODE', 'tls-only'),
                "port_tls": config.get('PORT_TLS', ''),
                "port_plain": config.get('PORT_PLAIN', '')
            })
        
        return {
            "success": True,
            "message": f"Found {len(tenants)} tenants",
            "data": {"tenants": tenants}
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
        
        security_mode = config.get('SECURITY_MODE', 'tls-only')
        port_tls = config.get('PORT_TLS', config.get('PORT', '6379'))
        port_plain = config.get('PORT_PLAIN', '')
        password = config.get('PASSWORD', '')
        
        # WordPress configuration for TLS mode
        wp_config_tls = f"""define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_SCHEME', 'tls');
define('WP_REDIS_HOST', '{internal_ip}');
define('WP_REDIS_PORT', {port_tls});
define('WP_REDIS_PASSWORD', '{password}');
define('WP_REDIS_PREFIX', 'wp:');

$redis_options = [
    'verify_peer' => true,
    'verify_peer_name' => true,
    'cafile' => ABSPATH . 'redis/redis-ca.pem'
];
define('WP_REDIS_SSL_CONTEXT', $redis_options);"""
        
        # WordPress configuration for plain-text mode
        wp_config_plain = f"""define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_HOST', '{internal_ip}');
define('WP_REDIS_PORT', {port_plain});
define('WP_REDIS_PASSWORD', '{password}');
define('WP_REDIS_PREFIX', 'wp:');"""
        
        credentials_text = f"""Redis Connection Details
Tenant: {name}
Security Mode: {security_mode}
Created: {config.get('CREATED', 'N/A')}

"""
        
        if security_mode in ['tls-only', 'dual-mode'] and port_tls:
            credentials_text += f"""TLS Connection:
  Host: {internal_ip}
  Port: {port_tls}
  Password: {password}
  Requires: CA Certificate

"""
        
        if security_mode in ['dual-mode', 'plain-only'] and port_plain:
            credentials_text += f"""Plain-Text Connection:
  Host: {internal_ip}
  Port: {port_plain}
  Password: {password}
  No certificate required

"""
        
        credentials_text += f"""Memory Limits:
  Redis: {config.get('MAXMEMORY', '256')} MB
  Docker: {config.get('DOCKER_LIMIT', '512')} MB

Contact: {org_name}
Email: {contact_email}
"""
        
        success, stdout, stderr = executor.execute("status", name)
        tenant_status = self._parse_status(stdout) if success else {}
        
        handover_dir = tenant_dir / 'handover'
        handover_file = handover_dir / f'{name}-handover.zip'
        
        handover_data = {
            "tenant": name,
            "security_mode": security_mode,
            "host": internal_ip,
            "public_host": public_ip,
            "password": password,
            "ca_certificate": ca_certificate,
            "status": tenant_status.get('status', 'unknown'),
            "handover_package": str(handover_file) if handover_file.exists() else None,
            "credentials_text": credentials_text
        }
        
        if security_mode in ['tls-only', 'dual-mode'] and port_tls:
            handover_data["tls_connection"] = {
                "port": int(port_tls),
                "connection_string": f"rediss://:{password}@{internal_ip}:{port_tls}",
                "wordpress_config": wp_config_tls
            }
        
        if security_mode in ['dual-mode', 'plain-only'] and port_plain:
            handover_data["plaintext_connection"] = {
                "port": int(port_plain),
                "connection_string": f"redis://:{password}@{internal_ip}:{port_plain}",
                "wordpress_config": wp_config_plain
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
    
    def change_security_mode(self, name: str, security_mode: str) -> Dict[str, Any]:
        """Change security mode for a tenant"""
        try:
            validated_name = sanitize_tenant_name(name)
            if security_mode not in ['tls-only', 'dual-mode', 'plain-only']:
                return {
                    "success": False,
                    "message": "Invalid security mode",
                    "error": "Security mode must be one of: tls-only, dual-mode, plain-only"
                }
        except ValidationError as e:
            logger.warning(f"Security mode change validation failed: {e}")
            return {
                "success": False,
                "message": "Validation error",
                "error": str(e)
            }
        
        success, stdout, stderr = executor.execute("set-access", validated_name, security_mode)
        
        if success:
            return {
                "success": True,
                "message": f"Security mode changed to {security_mode} for tenant {name}",
                "data": {"tenant": name, "security_mode": security_mode}
            }
        else:
            return {
                "success": False,
                "message": "Failed to change security mode",
                "error": stderr or stdout or "Mode change failed"
            }
    
    def _parse_status(self, output: str) -> Dict[str, Any]:
        # Strip ANSI escape codes
        ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
        output = ansi_escape.sub('', output)
        
        lines = output.strip().split('\n')
        status = {}
        current_section = None
        
        for line in lines:
            # Check for indentation BEFORE stripping
            is_indented = line.startswith('  ')
            line = line.strip()
            
            if not line or line.startswith('='):
                continue
            
            # Detect section headers (lines ending with : and no other :)
            if line.endswith(':') and line.count(':') == 1:
                current_section = line[:-1].lower().replace(' ', '_')
                continue
            
            # Parse key-value pairs
            if ':' in line:
                key, value = line.split(':', 1)
                clean_key = key.strip().lower().replace(' ', '_')
                clean_value = value.strip()
                
                # Store with section prefix if in a section and indented
                if current_section and is_indented:
                    full_key = f"{current_section}_{clean_key}"
                    status[full_key] = clean_value
                
                # Also store without prefix for backward compatibility
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
