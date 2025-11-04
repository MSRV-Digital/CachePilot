/**
 * CachePilot - API Type Definitions
 * 
 * TypeScript interfaces for API requests, responses, and data models.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

export interface ApiResponse<T> {
  success: boolean;
  message: string;
  data?: T;
  error?: string | null;
}

// Tenant types
export interface Tenant {
  tenant: string;
  port: string;
  status: 'running' | 'stopped';
  memory_used?: string;
  clients?: string;
  keys?: string;
  uptime_seconds?: number;
  maxmemory?: number;
  docker_limit?: number;
}

export interface TenantCreateRequest {
  tenant_name: string;
  maxmemory_mb: number;
  docker_limit_mb: number;
  password?: string;
}

export interface TenantUpdateRequest {
  maxmemory_mb?: number;
  docker_limit_mb?: number;
}

// Monitoring types
export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  services: {
    docker: string;
    disk_space: string;
    certificates: string;
  };
  total_tenants: number;
  running_tenants: number;
  issues: string[];
}

export interface Stats {
  total_tenants: string;
  running: string;
  stopped: string;
  total_memory_used: string;
  total_clients: string;
  total_keys: string;
}

export interface Alert {
  id: string;
  severity: 'info' | 'warning' | 'critical';
  message: string;
  timestamp: string;
  tenant?: string;
}

// Backup types
export interface BackupRequest {
  tenant: string;
}

export interface BackupInfo {
  file: string;
  size: string;
}

export interface RestoreBackupRequest {
  tenant: string;
  backup_file: string;
}
