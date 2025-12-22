/**
 * CachePilot - RedisInsight Hooks
 * 
 * React hooks for RedisInsight operations including enable, disable, and status retrieval.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getApiClient } from '../api/client';
import type { RedisInsightStatus } from '../api/types';

/**
 * Hook to get RedisInsight status for a tenant
 */
export const useRedisInsightStatus = (tenantName: string) => {
  return useQuery<any>({
    queryKey: ['redisinsight-status', tenantName],
    queryFn: async () => {
      const client = getApiClient();
      return await client.getRedisInsightStatus(tenantName);
    },
    enabled: !!tenantName,
    retry: 1,
  });
};

/**
 * Hook to enable RedisInsight for a tenant
 */
export const useEnableRedisInsight = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (tenantName: string) => {
      const client = getApiClient();
      return await client.enableRedisInsight(tenantName);
    },
    onSuccess: (_, tenantName) => {
      // Invalidate related queries
      queryClient.invalidateQueries({ queryKey: ['tenant', tenantName] });
      queryClient.invalidateQueries({ queryKey: ['redisinsight-status', tenantName] });
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
    },
  });
};

/**
 * Hook to disable RedisInsight for a tenant
 */
export const useDisableRedisInsight = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (tenantName: string) => {
      const client = getApiClient();
      await client.disableRedisInsight(tenantName);
    },
    onSuccess: (_, tenantName) => {
      // Invalidate related queries
      queryClient.invalidateQueries({ queryKey: ['tenant', tenantName] });
      queryClient.invalidateQueries({ queryKey: ['redisinsight-status', tenantName] });
      queryClient.invalidateQueries({ queryKey: ['tenants'] });
    },
  });
};
