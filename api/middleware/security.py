"""
CachePilot - Security Middleware

Security middleware for API including headers, rate limiting, request validation,
and content security policies.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import Request, HTTPException, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from typing import Callable, Dict, Any
import time
import logging
from collections import defaultdict
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable):
        response = await call_next(request)
        
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        
        return response

class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, default_limit: int = 100, default_window: int = 60):
        super().__init__(app)
        self.default_limit = default_limit
        self.default_window = default_window
        self.requests: Dict[str, list] = defaultdict(list)
        self.blocked_ips: Dict[str, datetime] = {}
        
        self.endpoint_limits = {
            "/api/auth/login": {"limit": 5, "window": 60},
            "/api/tenants": {"limit": 50, "window": 60},
            "/api/monitoring": {"limit": 200, "window": 60},
            "/api/system": {"limit": 30, "window": 60},
        }
    
    def _get_client_ip(self, request: Request) -> str:
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "unknown"
    
    def _is_blocked(self, ip: str) -> bool:
        if ip in self.blocked_ips:
            block_until = self.blocked_ips[ip]
            if datetime.now() < block_until:
                return True
            else:
                del self.blocked_ips[ip]
        return False
    
    def _block_ip(self, ip: str, duration_minutes: int = 15):
        self.blocked_ips[ip] = datetime.now() + timedelta(minutes=duration_minutes)
        logger.warning(f"IP {ip} temporarily blocked for {duration_minutes} minutes due to rate limit violation")
    
    def _check_rate_limit(self, ip: str, path: str) -> bool:
        if self._is_blocked(ip):
            return False
        
        now = time.time()
        
        endpoint_config = None
        for endpoint_path, config in self.endpoint_limits.items():
            if path.startswith(endpoint_path):
                endpoint_config = config
                break
        
        limit = endpoint_config["limit"] if endpoint_config else self.default_limit
        window = endpoint_config["window"] if endpoint_config else self.default_window
        
        request_key = f"{ip}:{path}"
        requests = self.requests[request_key]
        
        requests = [req_time for req_time in requests if now - req_time < window]
        
        if len(requests) >= limit:
            logger.warning(f"Rate limit exceeded for IP {ip} on path {path}")
            
            if len(requests) >= limit * 2:
                self._block_ip(ip)
            
            return False
        
        requests.append(now)
        self.requests[request_key] = requests
        
        return True
    
    async def dispatch(self, request: Request, call_next: Callable):
        ip = self._get_client_ip(request)
        path = request.url.path
        
        if not self._check_rate_limit(ip, path):
            logger.info(f"Rate limit exceeded for {ip} on {path}")
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={
                    "detail": "Rate limit exceeded. Please try again later.",
                    "error": "too_many_requests"
                },
                headers={"Retry-After": "60"}
            )
        
        response = await call_next(request)
        return response

class RequestValidationMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.suspicious_patterns = [
            r'\.\./\.\.',
            r'<script',
            r'javascript:',
            r'onclick=',
            r'onerror=',
            r'eval\(',
            r'exec\(',
            r'system\(',
            r'passthru\(',
            r'shell_exec\(',
            r'\${',
            r'`[^`]*`',
        ]
    
    def _contains_suspicious_pattern(self, value: str) -> bool:
        import re
        value_lower = value.lower()
        for pattern in self.suspicious_patterns:
            if re.search(pattern, value_lower):
                return True
        return False
    
    def _validate_query_params(self, request: Request) -> bool:
        for key, value in request.query_params.items():
            if self._contains_suspicious_pattern(str(value)):
                logger.warning(f"Suspicious query parameter detected: {key}={value}")
                return False
        return True
    
    async def dispatch(self, request: Request, call_next: Callable):
        if not self._validate_query_params(request):
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={
                    "detail": "Invalid request parameters",
                    "error": "bad_request"
                }
            )
        
        response = await call_next(request)
        return response

def sanitize_error_message(error: Exception, debug: bool = False) -> str:
    if debug:
        return str(error)
    
    error_type = type(error).__name__
    
    safe_errors = {
        "ValidationError": "Invalid input provided",
        "ValueError": "Invalid value",
        "KeyError": "Required field missing",
        "FileNotFoundError": "Resource not found",
        "PermissionError": "Access denied",
        "TimeoutError": "Request timeout",
    }
    
    return safe_errors.get(error_type, "An error occurred while processing your request")

def log_security_event(
    event_type: str,
    ip_address: str,
    details: Dict[str, Any],
    severity: str = "INFO"
):
    log_entry = {
        "timestamp": datetime.now().isoformat(),
        "event_type": event_type,
        "ip_address": ip_address,
        "severity": severity,
        **details
    }
    
    log_func = getattr(logger, severity.lower(), logger.info)
    log_func(f"Security event: {log_entry}")

class ContentSecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable):
        content_type = request.headers.get("content-type", "")
        
        if request.method in ["POST", "PUT", "PATCH"]:
            if "application/json" not in content_type and content_type:
                return JSONResponse(
                    status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                    content={
                        "detail": "Content-Type must be application/json",
                        "error": "unsupported_media_type"
                    }
                )
        
        response = await call_next(request)
        return response
