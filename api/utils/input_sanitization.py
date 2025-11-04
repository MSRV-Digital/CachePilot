"""
CachePilot - Input Sanitization Utilities

Comprehensive validation and sanitization for all user inputs to prevent
injection attacks, directory traversal, and security vulnerabilities.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

import re
import os
from pathlib import Path
from typing import Optional

class ValidationError(Exception):
    """Raised when input validation fails."""
    pass

def sanitize_tenant_name(name: str) -> str:
    if not name or not isinstance(name, str):
        raise ValidationError("Tenant name must be a non-empty string")
    
    name = name.strip().lower()
    
    if len(name) < 3 or len(name) > 63:
        raise ValidationError("Tenant name must be 3-63 characters long")
    
    if not re.match(r'^[a-z][a-z0-9-]*[a-z0-9]$', name):
        raise ValidationError(
            "Tenant name must start with a letter, contain only lowercase "
            "letters, numbers, and hyphens, and not end with a hyphen"
        )
    
    if '--' in name:
        raise ValidationError("Tenant name cannot contain consecutive hyphens")
    
    reserved_names = {'test', 'prod', 'dev', 'staging', 'localhost', 'redis', 'admin'}
    if name in reserved_names:
        raise ValidationError(f"Tenant name '{name}' is reserved")
    
    return name

def sanitize_file_path(path: str, base_dir: str) -> str:
    if not path or not isinstance(path, str):
        raise ValidationError("Path must be a non-empty string")
    
    if not base_dir or not isinstance(base_dir, str):
        raise ValidationError("Base directory must be a non-empty string")
    
    try:
        base_path = Path(base_dir).resolve()
        target_path = (base_path / path).resolve()
        
        if not str(target_path).startswith(str(base_path)):
            raise ValidationError("Path traversal detected")
        
        return str(target_path)
    except (ValueError, OSError) as e:
        raise ValidationError(f"Invalid path: {str(e)}")

def validate_memory_limit(mb: int) -> bool:
    if not isinstance(mb, int):
        raise ValidationError("Memory limit must be an integer")
    
    if mb < 64:
        raise ValidationError("Memory limit must be at least 64 MB")
    
    if mb > 65536:
        raise ValidationError("Memory limit cannot exceed 64 GB")
    
    return True

def validate_port(port: int) -> bool:
    if not isinstance(port, int):
        raise ValidationError("Port must be an integer")
    
    if port < 1024:
        raise ValidationError("Port must be 1024 or higher (privileged ports not allowed)")
    
    if port > 65535:
        raise ValidationError("Port must be 65535 or lower")
    
    reserved_ports = {6379, 8000, 8001, 8080, 8443, 9090}
    if port in reserved_ports:
        raise ValidationError(f"Port {port} is reserved for system use")
    
    return True

def validate_domain(domain: str) -> bool:
    if not domain or not isinstance(domain, str):
        raise ValidationError("Domain must be a non-empty string")
    
    domain = domain.strip().lower()
    
    if len(domain) > 253:
        raise ValidationError("Domain name too long (max 253 characters)")
    
    domain_pattern = r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'
    if not re.match(domain_pattern, domain):
        raise ValidationError("Invalid domain name format")
    
    return True

def validate_email(email: str) -> bool:
    if not email or not isinstance(email, str):
        raise ValidationError("Email must be a non-empty string")
    
    email = email.strip().lower()
    
    email_pattern = r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
    if not re.match(email_pattern, email):
        raise ValidationError("Invalid email address format")
    
    if len(email) > 254:
        raise ValidationError("Email address too long")
    
    return True

def sanitize_command_argument(arg: str) -> str:
    if not isinstance(arg, str):
        raise ValidationError("Argument must be a string")
    
    dangerous_chars = [';', '|', '&', '$', '`', '\n', '\r', '>', '<', '(', ')', '{', '}']
    for char in dangerous_chars:
        if char in arg:
            raise ValidationError(f"Argument contains dangerous character: {char}")
    
    if '..' in arg:
        raise ValidationError("Argument contains directory traversal pattern")
    
    return arg.strip()

def validate_backup_name(name: str) -> bool:
    if not name or not isinstance(name, str):
        raise ValidationError("Backup name must be a non-empty string")
    
    name = name.strip()
    
    if not re.match(r'^[a-zA-Z0-9_-]+\.(?:tar\.gz|zip)$', name):
        raise ValidationError("Invalid backup file name format")
    
    if len(name) > 255:
        raise ValidationError("Backup name too long")
    
    return True

def validate_tls_cert_path(path: str, base_dir: str = "/opt/cachepilot/data/ca") -> str:
    validated_path = sanitize_file_path(path, base_dir)
    
    if not validated_path.endswith(('.pem', '.crt', '.key')):
        raise ValidationError("Invalid certificate file extension")
    
    return validated_path

def validate_password_strength(password: str, min_length: int = 16) -> bool:
    if not password or not isinstance(password, str):
        raise ValidationError("Password must be a non-empty string")
    
    if len(password) < min_length:
        raise ValidationError(f"Password must be at least {min_length} characters")
    
    if not re.search(r'[a-z]', password):
        raise ValidationError("Password must contain lowercase letters")
    
    if not re.search(r'[A-Z]', password):
        raise ValidationError("Password must contain uppercase letters")
    
    if not re.search(r'[0-9]', password):
        raise ValidationError("Password must contain numbers")
    
    if not re.search(r'[!@#$%^&*()_+\-=\[\]{};:,.<>?]', password):
        raise ValidationError("Password must contain special characters")
    
    return True
