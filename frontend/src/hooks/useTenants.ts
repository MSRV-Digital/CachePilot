/**
 * CachePilot - Tenants Hook
 * 
 * React Query hooks for tenant management operations and state.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getApiClient } from '../api/client';
import type { Tenant, TenantCreateRequest, TenantUpdateRequest } from '../api/types';

export const useTenants = () => {
  // Fetch all tenants
  const {
    data: tenants = [],
    isLoading,
    error,
    refetch,
  } = useQuery<Tenant[], Error>({
    queryKey: ['tenants'],
    queryFn: () => getApiClient().fetchTenants(),
    staleTime: 5 * 60 * 1000, // 5 minutes
    refetchInterval: 30 * 1000, // Refresh every 30 seconds
    retry: (failureCount, error) => {
      // Don't retry on auth errors
      if (error instanceof Error && error.message.includes('Invalid or expired API key')) {
        return false;
      }
      return failureCount < 3;
    },
  });

  return {
    tenants,
    isLoading,
    error,
    refetch,
  };
};

export const useTenant = (name: string) => {
  const {
    data: tenant,
    isLoading,
    error,
    refetch,
  } = useQuery<Tenant, Error>({
    queryKey: ['tenant', name],
    queryFn: () => getApiClient().fetchTenant(name),
    enabled: !!name,
    staleTime: 2 * 60 * 1000, // 2 minutes
    refetchInterval: 10 * 1000, // Refresh every 10 seconds
    retry: (failureCount, error) => {
      // Don't retry on auth errors
      if (error instanceof Error && error.message.includes('Invalid or expired API key')) {
        return false;
      }
      return failureCount < 3;
    },
  });

  return {
    tenant,
    isLoading,
    error,
    refetch,
  };
};

export const useCreateTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, TenantCreateRequest>({
    mutationFn: (data) => getApiClient().createTenant(data),
    onSuccess: async () => {
      // Invalidate and refetch to ensure fresh data
      await queryClient.invalidateQueries({ queryKey: ['tenants'] });
      await queryClient.refetchQueries({ queryKey: ['tenants'] });
    },
  });
};

export const useUpdateTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, { name: string; data: TenantUpdateRequest }>({
    mutationFn: ({ name, data }) => getApiClient().updateTenant(name, data),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
      queryClient.invalidateQueries({ queryKey: ['tenant', variables.name] });
    },
  });
};

export const useDeleteTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, { name: string; force?: boolean }>({
    mutationFn: ({ name, force }) => getApiClient().deleteTenant(name, force),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
    },
  });
};

export const useStartTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>({
    mutationFn: (name) => getApiClient().startTenant(name),
    onSuccess: (_, name) => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
      queryClient.invalidateQueries({ queryKey: ['tenant', name] });
    },
  });
};

export const useStopTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>({
    mutationFn: (name) => getApiClient().stopTenant(name),
    onSuccess: (_, name) => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
      queryClient.invalidateQueries({ queryKey: ['tenant', name] });
    },
  });
};

export const useRestartTenant = () => {
  const queryClient = useQueryClient();

  return useMutation<void, Error, string>({
    mutationFn: (name) => getApiClient().restartTenant(name),
    onSuccess: (_, name) => {
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
      queryClient.invalidateQueries({ queryKey: ['tenant', name] });
    },
  });
};

export const useRotatePassword = () => {
  return useMutation<string, Error, string>({
    mutationFn: (name) => getApiClient().rotatePassword(name),
  });
};
