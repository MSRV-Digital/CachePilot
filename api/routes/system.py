"""
CachePilot - System API Routes

API endpoints for backup management, restore operations, and system maintenance.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import APIRouter, Depends, HTTPException
from api.models import ApiResponse, BackupRequest, RestoreRequest
from api.services.backup_service import backup_service
from api.auth import get_api_key

router = APIRouter(prefix="/system", tags=["system"])

@router.post("/backup", response_model=ApiResponse)
async def create_backup(request: BackupRequest, api_key: dict = Depends(get_api_key)):
    result = backup_service.create_backup(request.tenant)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.get("/backups/{tenant_name}", response_model=ApiResponse)
async def list_backups(tenant_name: str, api_key: dict = Depends(get_api_key)):
    return backup_service.list_backups(tenant_name)

@router.post("/restore", response_model=ApiResponse)
async def restore_backup(request: RestoreRequest, api_key: dict = Depends(get_api_key)):
    result = backup_service.restore_backup(request.tenant, request.backup_file)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/verify-backup", response_model=ApiResponse)
async def verify_backup(backup_file: str, api_key: dict = Depends(get_api_key)):
    result = backup_service.verify_backup(backup_file)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/backup/enable/{tenant_name}", response_model=ApiResponse)
async def enable_auto_backup(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = backup_service.enable_auto_backup(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.post("/backup/disable/{tenant_name}", response_model=ApiResponse)
async def disable_auto_backup(tenant_name: str, api_key: dict = Depends(get_api_key)):
    result = backup_service.disable_auto_backup(tenant_name)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result

@router.delete("/backups/{tenant_name}/{backup_file}", response_model=ApiResponse)
async def delete_backup(tenant_name: str, backup_file: str, api_key: dict = Depends(get_api_key)):
    result = backup_service.delete_backup(tenant_name, backup_file)
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
    return result
