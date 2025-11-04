/**
 * CachePilot - Monitoring Hook
 * 
 * React Query hooks for health checks, statistics, alerts, and metrics.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getApiClient } from '../api/client';
import type { HealthStatus, Stats, Alert } from '../api/types';

export const useMonitoring = () => {
  // Fetch health status
  const {
    data: health,
    isLoading: healthLoading,
    error: healthError,
    refetch: refetchHealth,
  } = useQuery<HealthStatus, Error>({
    queryKey: ['health'],
    queryFn: async () => {
      try {
        return await getApiClient().fetchHealth();
      } catch (error) {
        console.error('Failed to fetch health:', error);
        throw error;
      }
    },
    staleTime: 2 * 60 * 1000, // 2 minutes
    refetchInterval: 15 * 1000, // Refresh every 15 seconds
    retry: (failureCount, error) => {
      // Don't retry on auth errors
      if (error instanceof Error && error.message.includes('Invalid or expired API key')) {
        return false;
      }
      return failureCount < 3;
    },
    retryDelay: (attemptIndex: number) => Math.min(1000 * 2 ** attemptIndex, 30000),
    enabled: true,
  });

  // Fetch global stats
  const {
    data: stats,
    isLoading: statsLoading,
    error: statsError,
    refetch: refetchStats,
  } = useQuery<Stats, Error>({
    queryKey: ['stats'],
    queryFn: async () => {
      try {
        return await getApiClient().fetchStats();
      } catch (error) {
        console.error('Failed to fetch stats:', error);
        throw error;
      }
    },
    staleTime: 2 * 60 * 1000, // 2 minutes
    refetchInterval: 15 * 1000, // Refresh every 15 seconds
    retry: (failureCount, error) => {
      // Don't retry on auth errors
      if (error instanceof Error && error.message.includes('Invalid or expired API key')) {
        return false;
      }
      return failureCount < 3;
    },
    retryDelay: (attemptIndex: number) => Math.min(1000 * 2 ** attemptIndex, 30000),
    enabled: true,
  });

  const isLoading = healthLoading || statsLoading;
  const error = healthError || statsError;

  const refetch = () => {
    refetchHealth();
    refetchStats();
  };

  return {
    health,
    stats,
    isLoading,
    error,
    refetch,
  };
};

export const useAlerts = (params?: {
  severity?: 'info' | 'warning' | 'critical';
  tenant?: string;
  resolved?: boolean;
}) => {
  const {
    data: alerts = [],
    isLoading,
    error,
    refetch,
  } = useQuery<Alert[], Error>({
    queryKey: ['alerts', params],
    queryFn: () => getApiClient().fetchAlerts(params),
    staleTime: 1 * 60 * 1000, // 1 minute
    refetchInterval: 30 * 1000, // Refresh every 30 seconds
  });

  return {
    alerts,
    isLoading,
    error,
    refetch,
  };
};

export const useResolveAlert = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>({
    mutationFn: (alertId: string) => getApiClient().resolveAlert(alertId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alerts'] });
    },
  });
};

export const useCreateBackup = () => {
  return useMutation<void, Error, string>({
    mutationFn: (tenant: string) => getApiClient().createBackup({ tenant }),
  });
};

export const useListBackups = (tenantName: string) => {
  return useQuery<any[], Error>({
    queryKey: ['backups', tenantName],
    queryFn: () => getApiClient().listBackups(tenantName),
    enabled: !!tenantName,
    staleTime: 30 * 1000,
  });
};

export const useDeleteBackup = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, { tenantName: string; backupFile: string }>({
    mutationFn: ({ tenantName, backupFile }) => getApiClient().deleteBackup(tenantName, backupFile),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['backups', variables.tenantName] });
    },
  });
};

export const useRestoreBackup = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, { tenant: string; backupFile: string }>({
    mutationFn: ({ tenant, backupFile }) => getApiClient().restoreBackup(tenant, backupFile),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['tenant', variables.tenant] });
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
    },
  });
};
