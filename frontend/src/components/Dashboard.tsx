/**
 * CachePilot - Dashboard Component
 * 
 * Main dashboard displaying system overview, statistics, and quick actions.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React from 'react';
import { Link } from 'react-router-dom';
import { useMonitoring } from '../hooks/useMonitoring';
import { useTenants } from '../hooks/useTenants';
import { Activity, Database, AlertTriangle, CheckCircle, Plus } from 'lucide-react';
import { getStatusColor } from '../utils/format';

const Dashboard: React.FC = () => {
  const { health, stats, isLoading: monitoringLoading } = useMonitoring();
  const { isLoading: tenantsLoading } = useTenants();

  const isLoading = monitoringLoading || tenantsLoading;

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading...</div>
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
          <h1 className="text-2xl font-semibold">Dashboard</h1>
          <p className="text-sm text-gray-600 mt-1">System overview and health status</p>
        </div>
        <Link to="/tenants/new" className="btn-primary flex items-center space-x-2">
          <Plus className="w-4 h-4" />
          <span>New Tenant</span>
        </Link>
      </div>

      {/* Health Status Card */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold flex items-center space-x-2">
            <Activity className="w-5 h-5" />
            <span>System Health</span>
          </h2>
          <span className={`text-sm font-semibold uppercase ${healthColor}`}>
            {healthStatus}
          </span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Docker Status */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-600">Docker</span>
              {health?.services.docker === 'healthy' ? (
                <CheckCircle className="w-4 h-4 text-status-running" />
              ) : (
                <AlertTriangle className="w-4 h-4 text-status-stopped" />
              )}
            </div>
            <div className={`text-xs font-semibold uppercase ${getStatusColor(health?.services.docker || 'unknown')}`}>
              {health?.services.docker || 'Unknown'}
            </div>
          </div>

          {/* Disk Space Status */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-600">Disk Space</span>
              {health?.services.disk_space === 'healthy' ? (
                <CheckCircle className="w-4 h-4 text-status-running" />
              ) : (
                <AlertTriangle className="w-4 h-4 text-status-stopped" />
              )}
            </div>
            <div className={`text-xs font-semibold uppercase ${getStatusColor(health?.services.disk_space || 'unknown')}`}>
              {health?.services.disk_space || 'Unknown'}
            </div>
          </div>

          {/* Certificates Status */}
          <div className="border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-600">Certificates</span>
              {health?.services.certificates === 'healthy' ? (
                <CheckCircle className="w-4 h-4 text-status-running" />
              ) : (
                <AlertTriangle className="w-4 h-4 text-status-stopped" />
              )}
            </div>
            <div className={`text-xs font-semibold uppercase ${getStatusColor(health?.services.certificates || 'unknown')}`}>
              {health?.services.certificates || 'Unknown'}
            </div>
          </div>
        </div>

        {/* Issues */}
        {health?.issues && health.issues.length > 0 && (
          <div className="mt-4 p-4 bg-gray-100 border border-gray-200">
            <div className="flex items-center space-x-2 mb-2">
              <AlertTriangle className="w-4 h-4 text-status-warning" />
              <span className="text-sm font-semibold">Issues Detected</span>
            </div>
            <ul className="text-xs space-y-1 text-gray-700">
              {health.issues.map((issue, index) => (
                <li key={index}>• {issue}</li>
              ))}
            </ul>
          </div>
        )}
      </div>

      {/* Statistics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Total Tenants */}
        <div className="card">
          <div className="flex items-center space-x-3 mb-2">
            <Database className="w-5 h-5 text-gray-700" />
            <span className="text-sm text-gray-600">Total Tenants</span>
          </div>
          <div className="text-3xl font-semibold">{stats?.total_tenants || health?.total_tenants || 0}</div>
        </div>

        {/* Running Tenants */}
        <div className="card">
          <div className="flex items-center space-x-3 mb-2">
            <CheckCircle className="w-5 h-5 text-status-running" />
            <span className="text-sm text-gray-600">Running</span>
          </div>
          <div className="text-3xl font-semibold text-status-running">
            {stats?.running || health?.running_tenants || 0}
          </div>
        </div>

        {/* Stopped Tenants */}
        <div className="card">
          <div className="flex items-center space-x-3 mb-2">
            <AlertTriangle className="w-5 h-5 text-status-stopped" />
            <span className="text-sm text-gray-600">Stopped</span>
          </div>
          <div className="text-3xl font-semibold text-status-stopped">
            {stats?.stopped || (health?.total_tenants && health?.running_tenants ? health.total_tenants - health.running_tenants : 0)}
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Link to="/tenants" className="btn text-center">
            View All Tenants
          </Link>
          <Link to="/tenants/new" className="btn text-center">
            Create New Tenant
          </Link>
          <Link to="/health" className="btn text-center">
            View System Health
          </Link>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
