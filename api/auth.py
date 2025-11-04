"""
CachePilot - API Authentication Module

API key management, validation, rate limiting, and security event logging.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import Security, HTTPException, status
from fastapi.security import APIKeyHeader
from typing import Dict, List, Optional
import json
import hashlib
import secrets
import time
import os
import stat
import logging
from pathlib import Path
from api.config import settings
from api.middleware.security import log_security_event

logger = logging.getLogger(__name__)

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

class APIKeyManager:
    def __init__(self, key_file: str = None):
        self.key_file = key_file or settings.api_key_file
        self.keys: Dict[str, dict] = {}
        self._last_load_time: float = 0
        self._cache_ttl: int = 30
        self._failed_attempts: Dict[str, List[float]] = {}
        self.load_keys()
    
    def _verify_file_permissions(self) -> bool:
        if not Path(self.key_file).exists():
            return True
        
        try:
            file_stat = os.stat(self.key_file)
            file_mode = stat.S_IMODE(file_stat.st_mode)
            
            if file_mode != 0o600:
                logger.warning(
                    f"API key file has insecure permissions: {oct(file_mode)}. "
                    f"Expected 0o600. Please run: chmod 600 {self.key_file}"
                )
                return False
            return True
        except Exception as e:
            logger.error(f"Error checking file permissions: {e}")
            return False
    
    def load_keys(self):
        try:
            if Path(self.key_file).exists():
                self._verify_file_permissions()
                
                with open(self.key_file, 'r') as f:
                    self.keys = json.load(f)
                
                logger.info(f"Loaded {len(self.keys)} API keys from {self.key_file}")
            self._last_load_time = time.time()
        except Exception as e:
            logger.error(f"Error loading API keys: {e}")
            self.keys = {}
            self._last_load_time = time.time()
    
    def _should_reload(self) -> bool:
        return (time.time() - self._last_load_time) > self._cache_ttl
    
    def _reload_if_needed(self):
        if self._should_reload():
            self.load_keys()
    
    def save_keys(self):
        Path(self.key_file).parent.mkdir(parents=True, exist_ok=True)
        
        with open(self.key_file, 'w') as f:
            json.dump(self.keys, f, indent=2)
        
        try:
            os.chmod(self.key_file, 0o600)
            logger.info("API key file saved with secure permissions (0o600)")
        except Exception as e:
            logger.error(f"Failed to set secure permissions on API key file: {e}")
    
    def generate_key(self, name: str, permissions: List[str] = None) -> str:
        key = secrets.token_urlsafe(32)
        key_hash = hashlib.sha256(key.encode()).hexdigest()
        
        self.keys[key_hash] = {
            "name": name,
            "permissions": permissions or ["*"],
            "created": time.time(),
            "last_used": None,
            "request_count": 0
        }
        self.save_keys()
        return key
    
    def validate_key(self, key: str, ip_address: str = "unknown") -> Optional[dict]:
        if not key:
            self._log_failed_attempt(ip_address, "empty_key")
            return None
        
        self._reload_if_needed()
        
        key_hash = hashlib.sha256(key.encode()).hexdigest()
        if key_hash in self.keys:
            self.keys[key_hash]["last_used"] = time.time()
            self.keys[key_hash]["request_count"] += 1
            
            log_security_event(
                event_type="auth_success",
                ip_address=ip_address,
                details={
                    "key_name": self.keys[key_hash]["name"],
                    "request_count": self.keys[key_hash]["request_count"]
                },
                severity="INFO"
            )
            
            return self.keys[key_hash]
        
        self._log_failed_attempt(ip_address, "invalid_key")
        return None
    
    def _log_failed_attempt(self, ip_address: str, reason: str):
        now = time.time()
        
        if ip_address not in self._failed_attempts:
            self._failed_attempts[ip_address] = []
        
        self._failed_attempts[ip_address].append(now)
        
        recent_failures = [
            t for t in self._failed_attempts[ip_address]
            if now - t < 300
        ]
        self._failed_attempts[ip_address] = recent_failures
        
        log_security_event(
            event_type="auth_failure",
            ip_address=ip_address,
            details={
                "reason": reason,
                "recent_failures": len(recent_failures)
            },
            severity="WARNING"
        )
        
        if len(recent_failures) >= 5:
            log_security_event(
                event_type="auth_abuse",
                ip_address=ip_address,
                details={
                    "reason": "multiple_failed_attempts",
                    "failure_count": len(recent_failures)
                },
                severity="ERROR"
            )
    
    def revoke_key(self, key: str) -> bool:
        key_hash = hashlib.sha256(key.encode()).hexdigest()
        if key_hash in self.keys:
            del self.keys[key_hash]
            self.save_keys()
            return True
        return False
    
    def list_keys(self) -> List[dict]:
        return [
            {
                "name": data["name"],
                "permissions": data["permissions"],
                "created": data["created"],
                "last_used": data["last_used"],
                "request_count": data["request_count"]
            }
            for data in self.keys.values()
        ]

class RateLimiter:
    def __init__(self):
        self.requests: Dict[str, List[float]] = {}
    
    def check_rate_limit(self, key: str, endpoint: str = "*") -> bool:
        identifier = f"{key}:{endpoint}"
        now = time.time()
        window_start = now - settings.rate_limit_window
        
        if identifier not in self.requests:
            self.requests[identifier] = []
        
        self.requests[identifier] = [
            req_time for req_time in self.requests[identifier] 
            if req_time > window_start
        ]
        
        if len(self.requests[identifier]) >= settings.rate_limit_requests:
            return False
        
        self.requests[identifier].append(now)
        return True
    
    def get_remaining(self, key: str, endpoint: str = "*") -> int:
        identifier = f"{key}:{endpoint}"
        now = time.time()
        window_start = now - settings.rate_limit_window
        
        if identifier not in self.requests:
            return settings.rate_limit_requests
        
        recent_requests = [
            req_time for req_time in self.requests[identifier]
            if req_time > window_start
        ]
        
        return max(0, settings.rate_limit_requests - len(recent_requests))

api_key_manager = APIKeyManager()
rate_limiter = RateLimiter()

def get_api_key(api_key: str = Security(api_key_header)) -> dict:
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key"
        )
    
    key_data = api_key_manager.validate_key(api_key)
    if not key_data:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key"
        )
    
    if not rate_limiter.check_rate_limit(api_key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded"
        )
    
    return key_data
