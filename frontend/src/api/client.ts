/**
 * CachePilot - API Client
 * 
 * Axios-based HTTP client for CachePilot REST API with authentication and error handling.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import axios, { AxiosInstance, AxiosError } from 'axios';
import type {
  ApiResponse,
  Tenant,
  TenantCreateRequest,
  TenantUpdateRequest,
  HealthStatus,
  Stats,
  Alert,
  BackupRequest,
} from './types';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api';

// Custom event for auth errors
export const AUTH_ERROR_EVENT = 'auth-error';

// Create axios instance
export const createApiClient = (apiKey: string): AxiosInstance => {
  const client = axios.create({
    baseURL: `${API_BASE_URL}/v1`,
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': apiKey,
    },
    timeout: 120000, // 120 seconds for operations like tenant creation
  });

  // Response interceptor for error handling
  client.interceptors.response.use(
    (response) => response,
    (error: AxiosError<ApiResponse<unknown>>) => {
      // Handle different error scenarios
      if (error.response) {
        // Server responded with error status
        const status = error.response.status;
        const data = error.response.data;
        
        if (status === 401) {
          // Trigger auth error event for global handling
          window.dispatchEvent(new CustomEvent(AUTH_ERROR_EVENT, {
            detail: { message: 'Invalid or expired API key. Please log in again.' }
          }));
          throw new Error('Invalid or expired API key. Please log in again.');
        } else if (status === 429) {
          throw new Error('Rate limit exceeded. Please try again later.');
        } else if (status === 404) {
          throw new Error(data?.error || data?.message || 'Resource not found');
        } else if (data?.error || data?.message) {
          throw new Error(data.error || data.message);
        } else {
          throw new Error(`Server error: ${status}`);
        }
      } else if (error.request) {
        // Request made but no response
        throw new Error('Cannot connect to API server. Please check your connection.');
      } else {
        // Something else happened
        throw new Error(error.message || 'An unexpected error occurred');
      }
    }
  );

  return client;
};

// API Client class
export class ApiClient {
  private client: AxiosInstance;

  constructor(apiKey: string) {
    this.client = createApiClient(apiKey);
  }

  // Tenant operations
  async fetchTenants(): Promise<Tenant[]> {
    const response = await this.client.get<ApiResponse<{ tenants: Tenant[] }>>('/tenants');
    return response.data.data?.tenants || [];
  }

  async fetchTenant(name: string): Promise<Tenant> {
    const response = await this.client.get<ApiResponse<Tenant>>(`/tenants/${name}`);
    if (!response.data.data) {
      throw new Error('Tenant not found');
    }
    return response.data.data;
  }

  async createTenant(data: TenantCreateRequest): Promise<void> {
    await this.client.post<ApiResponse<{ tenant: string }>>('/tenants', data);
  }

  async updateTenant(name: string, data: TenantUpdateRequest): Promise<void> {
    await this.client.patch<ApiResponse<void>>(`/tenants/${name}`, data);
  }

  async deleteTenant(name: string, force = true): Promise<void> {
    await this.client.delete<ApiResponse<void>>(`/tenants/${name}`, {
      params: { force },
    });
  }

  async startTenant(name: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/tenants/${name}/start`);
  }

  async stopTenant(name: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/tenants/${name}/stop`);
  }

  async restartTenant(name: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/tenants/${name}/restart`);
  }

  async rotatePassword(name: string): Promise<string> {
    const response = await this.client.post<ApiResponse<{ tenant: string; new_password: string }>>(
      `/tenants/${name}/rotate-password`
    );
    return response.data.data?.new_password || '';
  }

  async getHandoverInfo(name: string): Promise<any> {
    const response = await this.client.get<ApiResponse<any>>(`/tenants/${name}/handover`);
    return response.data.data;
  }

  async regenerateHandover(name: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/tenants/${name}/handover/regenerate`);
  }

  async changeSecurityMode(name: string, securityMode: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/tenants/${name}/security-mode`, null, {
      params: { security_mode: securityMode }
    });
  }

  // RedisInsight operations
  async enableRedisInsight(name: string): Promise<any> {
    const response = await this.client.post<ApiResponse<any>>(
      `/tenants/${name}/redisinsight/enable`
    );
    return response.data.data;
  }

  async disableRedisInsight(name: string): Promise<void> {
    await this.client.delete<ApiResponse<void>>(`/tenants/${name}/redisinsight`);
  }

  async getRedisInsightStatus(name: string): Promise<any> {
    const response = await this.client.get<ApiResponse<any>>(
      `/tenants/${name}/redisinsight`
    );
    return response.data.data;
  }

  // Monitoring operations
  async fetchHealth(): Promise<HealthStatus> {
    const response = await this.client.get<ApiResponse<HealthStatus>>('/monitoring/health');
    if (!response.data.data) {
      throw new Error('Health data not available');
    }
    return response.data.data;
  }

  async fetchStats(): Promise<Stats> {
    const response = await this.client.get<ApiResponse<Stats>>('/monitoring/stats');
    if (!response.data.data) {
      throw new Error('Stats data not available');
    }
    return response.data.data;
  }

  async fetchAlerts(params?: {
    severity?: 'info' | 'warning' | 'critical';
    tenant?: string;
    resolved?: boolean;
  }): Promise<Alert[]> {
    const response = await this.client.get<ApiResponse<{ alerts: Alert[] }>>('/monitoring/alerts', {
      params,
    });
    return response.data.data?.alerts || [];
  }

  async resolveAlert(alertId: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/monitoring/alerts/${alertId}/resolve`);
  }

  async fetchTenantMetrics(name: string, hours = 24): Promise<unknown> {
    const response = await this.client.get<ApiResponse<unknown>>(
      `/monitoring/metrics/${name}`,
      { params: { hours } }
    );
    return response.data.data;
  }

  // System operations
  async createBackup(data: BackupRequest): Promise<void> {
    await this.client.post<ApiResponse<void>>('/system/backup', data);
  }

  async listBackups(tenantName: string): Promise<any[]> {
    const response = await this.client.get<ApiResponse<{ tenant: string; backups: any[] }>>(
      `/system/backups/${tenantName}`
    );
    return response.data.data?.backups || [];
  }

  async deleteBackup(tenantName: string, backupFile: string): Promise<void> {
    await this.client.delete<ApiResponse<void>>(
      `/system/backups/${tenantName}/${backupFile}`
    );
  }

  async restoreBackup(tenant: string, backupFile: string): Promise<void> {
    await this.client.post<ApiResponse<void>>('/system/restore', {
      tenant,
      backup_file: backupFile,
    });
  }

  async verifyBackup(backupFile: string): Promise<boolean> {
    try {
      await this.client.post<ApiResponse<void>>('/system/verify-backup', null, {
        params: { backup_file: backupFile },
      });
      return true;
    } catch {
      return false;
    }
  }

  async enableAutoBackup(tenantName: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/system/backup/enable/${tenantName}`);
  }

  async disableAutoBackup(tenantName: string): Promise<void> {
    await this.client.post<ApiResponse<void>>(`/system/backup/disable/${tenantName}`);
  }

  // Validation
  async validateApiKey(): Promise<boolean> {
    try {
      await this.client.get<ApiResponse<{ status: string }>>('/health');
      return true;
    } catch (error) {
      return false;
    }
  }
}

// Export singleton getter
let apiClientInstance: ApiClient | null = null;

export const getApiClient = (apiKey?: string): ApiClient => {
  if (apiKey) {
    apiClientInstance = new ApiClient(apiKey);
  }
  if (!apiClientInstance) {
    throw new Error('API client not initialized. Please provide an API key.');
  }
  return apiClientInstance;
};
