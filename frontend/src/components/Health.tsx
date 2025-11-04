/**
 * CachePilot - Health Component
 * 
 * System health monitoring display with service status and alerts.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React from 'react';
import { useMonitoring, useAlerts } from '../hooks/useMonitoring';
import { Activity, AlertTriangle, CheckCircle, Info } from 'lucide-react';
import { getStatusColor, formatDate } from '../utils/format';

const Health: React.FC = () => {
  const { health, stats, isLoading, error, refetch } = useMonitoring();
  const { alerts } = useAlerts({ resolved: false });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading health data...</div>
      </div>
    );
  }

  // Show error state if data fetch failed
  if (error && !health && !stats) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold">System Health</h1>
            <p className="text-sm text-gray-600 mt-1">Monitor system status and alerts</p>
          </div>
          <button onClick={refetch} className="btn">
            Retry
          </button>
        </div>
        
        <div className="card bg-red-50 border-red-200">
          <div className="flex items-center space-x-3 text-red-700">
            <AlertTriangle className="w-6 h-6" />
            <div>
              <h2 className="font-semibold">Failed to load health data</h2>
              <p className="text-sm mt-1">{error.message}</p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  const healthStatus = health?.status || 'unknown';
  const healthColor = getStatusColor(healthStatus);

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">System Health</h1>
          <p className="text-sm text-gray-600 mt-1">Monitor system status and alerts</p>
        </div>
        <button onClick={refetch} className="btn">
          Refresh
        </button>
      </div>

      {/* Overall Health Status */}
      <div className="card">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <Activity className="w-6 h-6" />
            <div>
              <h2 className="text-lg font-semibold">Overall Status</h2>
              <p className="text-sm text-gray-600">System health check</p>
            </div>
          </div>
          <span className={`text-xl font-semibold uppercase ${healthColor}`}>
            {healthStatus}
          </span>
        </div>
      </div>

      {/* Services Status */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Services</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Docker */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium">Docker Engine</span>
              {health?.services.docker === 'healthy' ? (
                <CheckCircle className="w-5 h-5 text-status-running" />
              ) : (
                <AlertTriangle className="w-5 h-5 text-status-stopped" />
              )}
            </div>
            <div className={`text-sm font-semibold uppercase ${getStatusColor(health?.services.docker || 'unknown')}`}>
              {health?.services.docker || 'Unknown'}
            </div>
          </div>

          {/* Disk Space */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium">Disk Space</span>
              {health?.services.disk_space === 'healthy' ? (
                <CheckCircle className="w-5 h-5 text-status-running" />
              ) : (
                <AlertTriangle className="w-5 h-5 text-status-stopped" />
              )}
            </div>
            <div className={`text-sm font-semibold uppercase ${getStatusColor(health?.services.disk_space || 'unknown')}`}>
              {health?.services.disk_space || 'Unknown'}
            </div>
          </div>

          {/* Certificates */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium">SSL Certificates</span>
              {health?.services.certificates === 'healthy' ? (
                <CheckCircle className="w-5 h-5 text-status-running" />
              ) : (
                <AlertTriangle className="w-5 h-5 text-status-stopped" />
              )}
            </div>
            <div className={`text-sm font-semibold uppercase ${getStatusColor(health?.services.certificates || 'unknown')}`}>
              {health?.services.certificates || 'Unknown'}
            </div>
          </div>
        </div>
      </div>

      {/* Tenant Statistics */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Tenant Statistics</h2>
        <table className="table">
          <tbody>
            <tr>
              <td className="font-medium">Total Tenants</td>
              <td className="text-right font-mono">{health?.total_tenants || 0}</td>
            </tr>
            <tr>
              <td className="font-medium">Running Tenants</td>
              <td className="text-right font-mono text-status-running">{health?.running_tenants || 0}</td>
            </tr>
            <tr>
              <td className="font-medium">Stopped Tenants</td>
              <td className="text-right font-mono text-status-stopped">
                {(health?.total_tenants || 0) - (health?.running_tenants || 0)}
              </td>
            </tr>
            <tr>
              <td className="font-medium">Total Memory Used</td>
              <td className="text-right font-mono">{stats?.total_memory_used || 0} MB</td>
            </tr>
            <tr>
              <td className="font-medium">Total Clients</td>
              <td className="text-right font-mono">{stats?.total_clients || 0}</td>
            </tr>
            <tr>
              <td className="font-medium">Total Keys</td>
              <td className="text-right font-mono">{stats?.total_keys || 0}</td>
            </tr>
          </tbody>
        </table>
      </div>

      {/* Issues */}
      {health?.issues && health.issues.length > 0 && (
        <div className="card bg-gray-50 border-status-warning">
          <div className="flex items-center space-x-2 mb-4">
            <AlertTriangle className="w-5 h-5 text-status-warning" />
            <h2 className="text-lg font-semibold">Active Issues</h2>
          </div>
          <ul className="space-y-2">
            {health.issues.map((issue: string, index: number) => (
              <li key={index} className="flex items-start space-x-2 text-sm">
                <span className="text-status-warning mt-0.5">•</span>
                <span>{issue}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Alerts */}
      {alerts && alerts.length > 0 && (
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Active Alerts</h2>
          <div className="space-y-3">
            {alerts.map((alert) => {
              const severityIcon: Record<string, JSX.Element> = {
                critical: <AlertTriangle className="w-4 h-4 text-status-stopped" />,
                warning: <AlertTriangle className="w-4 h-4 text-status-warning" />,
                info: <Info className="w-4 h-4 text-gray-600" />,
              };

              return (
                <div key={alert.id} className="border border-gray-200 p-4">
                  <div className="flex items-start justify-between mb-2">
                    <div className="flex items-center space-x-2">
                      {severityIcon[alert.severity] || severityIcon.info}
                      <span className={`text-xs font-semibold uppercase ${getStatusColor(alert.severity)}`}>
                        {alert.severity}
                      </span>
                    </div>
                    <span className="text-xs text-gray-600">{formatDate(alert.timestamp)}</span>
                  </div>
                  <p className="text-sm text-gray-900">{alert.message}</p>
                  {alert.tenant && (
                    <p className="text-xs text-gray-600 mt-1">Tenant: {alert.tenant}</p>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* No Alerts Message */}
      {(!alerts || alerts.length === 0) && (!health?.issues || health.issues.length === 0) && (
        <div className="card text-center py-8">
          <CheckCircle className="w-12 h-12 text-status-running mx-auto mb-3" />
          <p className="text-gray-600">No active alerts or issues</p>
          <p className="text-sm text-gray-500 mt-1">System is running smoothly</p>
        </div>
      )}
    </div>
  );
};

export default Health;
