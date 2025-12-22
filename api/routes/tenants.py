"""
CachePilot - Tenant API Routes

API endpoints for tenant management including creation, updates, lifecycle
operations, and credential rotation.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import APIRouter, Depends, HTTPException
from typing import List
from api.models import TenantCreateRequest, TenantUpdateRequest, TenantResponse, ApiResponse, PasswordRotateRequest
from api.services.tenant_service import tenant_service
from api.auth import get_api_key

router = APIRouter(prefix="/tenants", tags=["tenants"])

@router.post("", response_model=ApiResponse)
async def create_tenant(request: TenantCreateRequest, api_key: dict = Depends(get_api_key)):
    import asyncio
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(None, tenant_service.create_tenant, request)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.get("", response_model=ApiResponse)
async def list_tenants(api_key: dict = Depends(get_api_key)):
    return tenant_service.list_tenants()

@router.get("/{tenant_name}", response_model=ApiResponse)
async def get_tenant(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.get_tenant(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["error"])
    return result

@router.patch("/{tenant_name}", response_model=ApiResponse)
async def update_tenant(tenant_name: str, updates: TenantUpdateRequest, api_key: dict = Depends(get_api_key)):
    result = tenant_service.update_tenant(tenant_name, updates)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.delete("/{tenant_name}", response_model=ApiResponse)
async def delete_tenant(tenant_name: str, force: bool = False, api_key: dict = Depends(get_api_key)):
    result = tenant_service.delete_tenant(tenant_name, force)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/start", response_model=ApiResponse)
async def start_tenant(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.start_tenant(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/stop", response_model=ApiResponse)
async def stop_tenant(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.stop_tenant(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/restart", response_model=ApiResponse)
async def restart_tenant(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.restart_tenant(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/rotate-password", response_model=ApiResponse)
async def rotate_password(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.rotate_password(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.get("/{tenant_name}/handover", response_model=ApiResponse)
async def get_handover_info(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.get_handover_info(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["error"])
    return result

@router.post("/{tenant_name}/handover/regenerate", response_model=ApiResponse)
async def regenerate_handover(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.regenerate_handover(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/security-mode", response_model=ApiResponse)
async def change_security_mode(tenant_name: str, security_mode: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.change_security_mode(tenant_name, security_mode)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/{tenant_name}/redisinsight/enable", response_model=ApiResponse)
async def enable_redisinsight(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.enable_redisinsight(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.delete("/{tenant_name}/redisinsight", response_model=ApiResponse)
async def disable_redisinsight(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.disable_redisinsight(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.get("/{tenant_name}/redisinsight", response_model=ApiResponse)
async def get_redisinsight_status(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = tenant_service.get_redisinsight_status(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=404, detail=result["error"])
    return result
