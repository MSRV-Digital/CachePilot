"""
CachePilot - API Data Models

Pydantic models for request/response validation, type safety, and API documentation.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict, Any, List
from datetime import datetime

class TenantCreateRequest(BaseModel):
    tenant_name: str = Field(pattern=r'^[a-z0-9][a-z0-9-]{0,62}$')
    maxmemory_mb: int = Field(default=256, ge=64, le=4096)
    docker_limit_mb: int = Field(default=512, ge=128, le=8192)
    password: Optional[str] = None
    
    @field_validator('docker_limit_mb')
    @classmethod
    def validate_docker_limit(cls, v, info):
        if 'maxmemory_mb' in info.data and v < info.data['maxmemory_mb'] * 1.5:
            raise ValueError(f'docker_limit_mb must be at least 1.5x maxmemory_mb')
        return v

class TenantUpdateRequest(BaseModel):
    maxmemory_mb: Optional[int] = Field(None, ge=64, le=4096)
    docker_limit_mb: Optional[int] = Field(None, ge=128, le=8192)

class TenantResponse(BaseModel):
    tenant: str
    port: int
    status: str
    created: str
    memory_used: Optional[int] = None
    memory_limit: int
    docker_limit: int
    clients: Optional[int] = None
    keys: Optional[int] = None
    uptime_seconds: Optional[int] = None
    insight_enabled: bool
    insight_port: Optional[int] = None

class ApiResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

class HealthCheckResponse(BaseModel):
    status: str
    timestamp: str
    services: Dict[str, str]
    total_tenants: int
    running_tenants: int
    issues: List[str]

class LogEntry(BaseModel):
    timestamp: str
    level: str
    component: str
    message: str
    tenant: Optional[str] = None
    user: Optional[str] = None
    details: Optional[Dict[str, Any]] = None

class MonitoringMetric(BaseModel):
    tenant: str
    metric_name: str
    value: float
    unit: str
    timestamp: str
    threshold: Optional[float] = None
    alert_triggered: bool = False

class Alert(BaseModel):
    id: str
    severity: str
    tenant: Optional[str] = None
    title: str
    message: str
    timestamp: str
    resolved: bool = False
    resolved_at: Optional[str] = None

class BackupRequest(BaseModel):
    tenant: str

class BackupListResponse(BaseModel):
    tenant: str
    backups: List[Dict[str, Any]]

class RestoreRequest(BaseModel):
    tenant: str
    backup_file: str

class PasswordRotateRequest(BaseModel):
    tenant: str

class ApiKeyResponse(BaseModel):
    key: str
    name: str
    created: str
    permissions: List[str]
