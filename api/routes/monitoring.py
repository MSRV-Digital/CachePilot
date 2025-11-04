"""
CachePilot - Monitoring API Routes

API endpoints for health checks, statistics, alerts, and metrics monitoring.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import APIRouter, Depends, Query
from typing import Optional
from api.models import ApiResponse, HealthCheckResponse
from api.services.monitoring_service import monitoring_service
from api.auth import get_api_key

router = APIRouter(prefix="/monitoring", tags=["monitoring"])

@router.get("/health", response_model=ApiResponse)
async def get_health(api_key: dict = Depends(get_api_key)):
    return monitoring_service.get_health_status()

@router.get("/stats", response_model=ApiResponse)
async def get_stats(api_key: dict = Depends(get_api_key)):
    return monitoring_service.get_global_stats()

@router.get("/alerts", response_model=ApiResponse)
async def get_alerts(
    severity: Optional[str] = Query(None, regex="^(info|warning|critical)$"),
    tenant: Optional[str] = None,
    resolved: Optional[bool] = None,
    api_key: dict = Depends(get_api_key)
):
    return monitoring_service.get_alerts(severity, tenant, resolved)

@router.post("/alerts/{alert_id}/resolve", response_model=ApiResponse)
async def resolve_alert(alert_id: str, api_key: dict = Depends(get_api_key)):
    result = monitoring_service.resolve_alert(alert_id)
    if not result["success"]:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail=result["error"])
    return result

@router.get("/metrics/{tenant_name}", response_model=ApiResponse)
async def get_tenant_metrics(
    tenant_name: str,
    hours: int = Query(24, ge=1, le=168),
    api_key: dict = Depends(get_api_key)
):
    return monitoring_service.get_tenant_metrics(tenant_name, hours)
