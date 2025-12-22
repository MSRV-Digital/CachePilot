/**
 * CachePilot - Formatting Utilities
 * 
 * Helper functions for data formatting including bytes, dates, and uptime.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

export const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';
  if (!bytes) return 'N/A';
  
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

// Format uptime seconds to human-readable string
export const formatUptime = (seconds: number): string => {
  if (!seconds || seconds === 0) return 'N/A';
  
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  
  if (days > 0) {
    return `${days}d ${hours}h`;
  } else if (hours > 0) {
    return `${hours}h ${minutes}m`;
  } else {
    return `${minutes}m`;
  }
};

// Format date string to human-readable format
export const formatDate = (date: string | Date): string => {
  if (!date) return 'N/A';
  
  const d = typeof date === 'string' ? new Date(date) : date;
  
  if (isNaN(d.getTime())) return 'Invalid date';
  
  return d.toLocaleString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Get status color class for Tailwind
export const getStatusColor = (status: string): string => {
  switch (status.toLowerCase()) {
    case 'running':
    case 'healthy':
      return 'text-status-running';
    case 'stopped':
    case 'unhealthy':
      return 'text-status-stopped';
    case 'warning':
    case 'degraded':
      return 'text-status-warning';
    default:
      return 'text-gray-700';
  }
};

// Get status background color class for Tailwind
export const getStatusBg = (status: string): string => {
  switch (status.toLowerCase()) {
    case 'running':
    case 'healthy':
      return 'bg-status-running';
    case 'stopped':
    case 'unhealthy':
      return 'bg-status-stopped';
    case 'warning':
    case 'degraded':
      return 'bg-status-warning';
    default:
      return 'bg-gray-300';
  }
};

// Format MB values for display
export const formatMB = (mb: number | string): string => {
  if (!mb || mb === 0) return '0 MB';
  
  const mbValue = typeof mb === 'string' ? parseFloat(mb) : mb;
  
  if (mbValue >= 1024) {
    return `${(mbValue / 1024).toFixed(2)} GB`;
  }
  
  return `${mbValue} MB`;
};

// Parse memory string to bytes
export const parseMemory = (memory: string): number => {
  if (!memory) return 0;
  
  const units: { [key: string]: number } = {
    B: 1,
    K: 1024,
    M: 1024 * 1024,
    G: 1024 * 1024 * 1024,
  };
  
  const match = memory.match(/^([\d.]+)([BKMG])?$/i);
  if (!match) return 0;
  
  const value = parseFloat(match[1]);
  const unit = (match[2] || 'B').toUpperCase();
  
  return value * (units[unit] || 1);
};
