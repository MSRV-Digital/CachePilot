"""
CachePilot - REST API Main Application

FastAPI application providing REST endpoints for Redis multi-tenant management
with authentication, rate limiting, and comprehensive monitoring.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from api.config import settings
from api.routes import tenants, monitoring, system
from api.middleware.security import (
    SecurityHeadersMiddleware,
    RateLimitMiddleware,
    RequestValidationMiddleware,
    ContentSecurityMiddleware,
    sanitize_error_message,
    log_security_event
)
import time
import logging

logger = logging.getLogger(__name__)

app = FastAPI(
    title="CachePilot API",
    description="REST API for Redis Multi-Tenant Manager",
    version="2.1.2-Beta",
    docs_url="/api/docs" if settings.debug else None,
    redoc_url="/api/redoc" if settings.debug else None,
)

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RateLimitMiddleware, default_limit=100, default_window=60)
app.add_middleware(RequestValidationMiddleware)
app.add_middleware(ContentSecurityMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key"],
)

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    return response

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    client_ip = request.client.host if request.client else "unknown"
    
    log_security_event(
        event_type="unhandled_exception",
        ip_address=client_ip,
        details={
            "path": str(request.url.path),
            "method": request.method,
            "exception_type": type(exc).__name__
        },
        severity="ERROR"
    )
    
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    
    error_message = sanitize_error_message(exc, debug=settings.debug)
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "success": False,
            "message": error_message,
            "error": "internal_server_error"
        }
    )

app.include_router(tenants.router, prefix="/api/v1")
app.include_router(monitoring.router, prefix="/api/v1")
app.include_router(system.router, prefix="/api/v1")

@app.get("/")
async def root():
    return {
        "name": "CachePilot API",
        "version": "2.1.2-Beta",
        "status": "running"
    }

@app.get("/api/v1/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": time.time()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=settings.api_host, port=settings.api_port)
