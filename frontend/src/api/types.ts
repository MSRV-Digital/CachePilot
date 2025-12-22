export type SecurityMode = 'tls-only' | 'dual-mode' | 'plain-only';
export type PersistenceMode = 'memory-only' | 'persistent';

export interface Tenant {
  tenant: string;
  port: number | string;
  status: string;
  created?: string;
  memory_used?: string;
  memory_peak?: string;
  memory_limit?: number;
  maxmemory?: number;
  docker_limit?: number;
  clients?: string;
  keys?: string;
  uptime_seconds?: number;
  security_mode?: SecurityMode;
  persistence_mode?: PersistenceMode;
  port_tls?: number | string;
  port_plain?: number | string;
  total_commands?: string;
  keyspace_hits?: string;
  keyspace_misses?: string;
  hit_rate?: string;
  evicted_keys?: string;
}

export interface TenantCreateRequest {
  tenant_name: string;
  maxmemory_mb: number;
  docker_limit_mb: number;
  password?: string;
  security_mode?: SecurityMode;
  persistence_mode?: PersistenceMode;
}

export interface TenantUpdateRequest {
  maxmemory_mb?: number;
  docker_limit_mb?: number;
  password?: string;
}

export interface BackupRequest {
  tenant_name?: string;
  tenant?: string;
}

export interface ApiResponse<T = any> {
  success: boolean;
  message: string;
  data?: T;
  error?: string;
}

export interface Stats {
  total_tenants: number;
  running_tenants: number;
  running?: number;
  stopped_tenants: number;
  stopped?: number;
  total_memory_used: number;
  total_memory_limit: number;
  total_connections: number;
  total_clients?: number;
  total_keys: number;
}

export interface Alert {
  id: string;
  tenant?: string;
  severity: 'info' | 'warning' | 'critical';
  message: string;
  timestamp: string;
  resolved: boolean;
}

export interface HealthStatus {
  status: string;
  timestamp: string;
  services: {
    [key: string]: string;
  };
  total_tenants: number;
  running_tenants: number;
  issues: string[];
}

export interface MonitoringData {
  timestamp: string;
  tenants: {
    name: string;
    memory_used: number;
    memory_limit: number;
    connected_clients: number;
    total_keys: number;
    uptime_seconds: number;
  }[];
}

export interface RedisInsightStatus {
  enabled: boolean;
  port?: number;
  public_url?: string;
  internal_url?: string;
  username?: string;
  password?: string;
  status?: string;
}

export interface RedisInsightResponse {
  tenant: string;
  redisinsight: RedisInsightStatus;
}
