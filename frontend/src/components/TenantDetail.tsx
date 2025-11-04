/**
 * CachePilot - Tenant Detail Component
 * 
 * Detailed view of a Redis tenant with statistics, actions, and handover information.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React, { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useTenant, useStartTenant, useStopTenant, useRestartTenant, useDeleteTenant } from '../hooks/useTenants';
import { useCreateBackup, useListBackups, useDeleteBackup, useRestoreBackup } from '../hooks/useMonitoring';
import { ArrowLeft, Play, Square, RotateCw, Trash2, Download, Copy, RefreshCw, Key, Upload } from 'lucide-react';
import { getStatusColor, formatUptime, formatBytes } from '../utils/format';
import { getApiClient } from '../api/client';

const TenantDetail: React.FC = () => {
  const { name } = useParams<{ name: string }>();
  const navigate = useNavigate();
  const { tenant, isLoading, refetch } = useTenant(name || '');
  const startMutation = useStartTenant();
  const stopMutation = useStopTenant();
  const restartMutation = useRestartTenant();
  const deleteMutation = useDeleteTenant();
  const backupMutation = useCreateBackup();
  const { data: backups = [], isLoading: backupsLoading, refetch: refetchBackups } = useListBackups(name || '');
  const deleteBackupMutation = useDeleteBackup();
  const restoreBackupMutation = useRestoreBackup();
  const [actionMessage, setActionMessage] = React.useState<{ type: 'success' | 'error', text: string } | null>(null);
  const [handoverInfo, setHandoverInfo] = useState<any>(null);
  const [loadingHandover, setLoadingHandover] = useState(false);
  const [showHandover, setShowHandover] = useState(false);

  useEffect(() => {
    if (showHandover && name) {
      loadHandoverInfo();
    }
  }, [showHandover, name]);

  const loadHandoverInfo = async () => {
    if (!name) return;
    setLoadingHandover(true);
    try {
      const info = await getApiClient().getHandoverInfo(name);
      setHandoverInfo(info);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load handover info';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    } finally {
      setLoadingHandover(false);
    }
  };

  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    setActionMessage({ type: 'success', text: `${label} copied to clipboard` });
    setTimeout(() => setActionMessage(null), 3000);
  };

  const handleRegenerateHandover = async () => {
    if (!name) return;
    setLoadingHandover(true);
    try {
      await getApiClient().regenerateHandover(name);
      setActionMessage({ type: 'success', text: 'Handover package regenerated' });
      setTimeout(() => setActionMessage(null), 5000);
      await loadHandoverInfo();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to regenerate handover';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    } finally {
      setLoadingHandover(false);
    }
  };

  const handleAction = async (action: () => Promise<void>, successMessage: string) => {
    setActionMessage(null);
    try {
      await action();
      setActionMessage({ type: 'success', text: successMessage });
      setTimeout(() => setActionMessage(null), 5000);
      await refetch();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Action failed';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    }
  };

  const handleDelete = async () => {
    if (!window.confirm(`Are you sure you want to delete tenant "${name}"? This action cannot be undone.`)) {
      return;
    }
    setActionMessage(null);
    try {
      await deleteMutation.mutateAsync({ name: name!, force: true });
      navigate('/tenants');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Delete failed';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    }
  };

  const handleBackup = async () => {
    setActionMessage(null);
    try {
      await backupMutation.mutateAsync(name!);
      setActionMessage({ type: 'success', text: 'Backup created successfully' });
      setTimeout(() => setActionMessage(null), 5000);
      await refetchBackups();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Backup failed';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    }
  };

  const handleDeleteBackup = async (backupFile: string) => {
    if (!window.confirm(`Are you sure you want to delete backup "${backupFile}"?`)) {
      return;
    }
    setActionMessage(null);
    try {
      await deleteBackupMutation.mutateAsync({ tenantName: name!, backupFile });
      setActionMessage({ type: 'success', text: 'Backup deleted successfully' });
      setTimeout(() => setActionMessage(null), 5000);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Delete backup failed';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    }
  };

  const handleRestoreBackup = async (backupFile: string) => {
    if (!window.confirm(`Are you sure you want to restore from "${backupFile}"? This will overwrite current data.`)) {
      return;
    }
    setActionMessage(null);
    try {
      await restoreBackupMutation.mutateAsync({ tenant: name!, backupFile });
      setActionMessage({ type: 'success', text: 'Backup restored successfully. Tenant will be restarted.' });
      setTimeout(() => setActionMessage(null), 5000);
      await refetch();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Restore backup failed';
      setActionMessage({ type: 'error', text: errorMessage });
      setTimeout(() => setActionMessage(null), 8000);
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading tenant details...</div>
      </div>
    );
  }

  if (!tenant) {
    return (
      <div className="space-y-6">
        <Link to="/tenants" className="btn inline-flex items-center space-x-2">
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Tenants</span>
        </Link>
        <div className="card text-center py-12">
          <p className="text-gray-600">Tenant not found</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Action Message */}
      {actionMessage && (
        <div className={`card ${actionMessage.type === 'success' ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
          <p className={`text-sm ${actionMessage.type === 'success' ? 'text-green-700' : 'text-red-700'}`}>
            {actionMessage.text}
          </p>
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <Link to="/tenants" className="btn inline-flex items-center space-x-2">
            <ArrowLeft className="w-4 h-4" />
            <span>Back</span>
          </Link>
          <div>
            <h1 className="text-2xl font-semibold">{tenant.tenant}</h1>
            <p className="text-sm text-gray-600 mt-1">Tenant Details</p>
          </div>
        </div>
        <span className={`status-badge ${getStatusColor(tenant.status)}`}>
          {tenant.status}
        </span>
      </div>

      {/* Actions */}
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">Actions</h2>
        <div className="flex flex-wrap gap-2">
          {tenant.status === 'stopped' ? (
            <button
              onClick={() => handleAction(() => startMutation.mutateAsync(tenant.tenant), 'Tenant started successfully')}
              disabled={startMutation.isPending}
              className="btn flex items-center space-x-2"
            >
              <Play className="w-4 h-4" />
              <span>{startMutation.isPending ? 'Starting...' : 'Start'}</span>
            </button>
          ) : (
            <>
              <button
                onClick={() => handleAction(() => stopMutation.mutateAsync(tenant.tenant), 'Tenant stopped successfully')}
                disabled={stopMutation.isPending}
                className="btn flex items-center space-x-2"
              >
                <Square className="w-4 h-4" />
                <span>{stopMutation.isPending ? 'Stopping...' : 'Stop'}</span>
              </button>
              <button
                onClick={() => handleAction(() => restartMutation.mutateAsync(tenant.tenant), 'Tenant restarted successfully')}
                disabled={restartMutation.isPending}
                className="btn flex items-center space-x-2"
              >
                <RotateCw className="w-4 h-4" />
                <span>{restartMutation.isPending ? 'Restarting...' : 'Restart'}</span>
              </button>
            </>
          )}
          <button
            onClick={handleBackup}
            disabled={backupMutation.isPending}
            className="btn flex items-center space-x-2"
          >
            <Download className="w-4 h-4" />
            <span>{backupMutation.isPending ? 'Creating...' : 'Backup'}</span>
          </button>
          <button
            onClick={handleDelete}
            disabled={deleteMutation.isPending}
            className="btn-danger flex items-center space-x-2"
          >
            <Trash2 className="w-4 h-4" />
            <span>{deleteMutation.isPending ? 'Deleting...' : 'Delete'}</span>
          </button>
        </div>
      </div>

      {/* Tenant Information */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Connection Info</h2>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Name</td>
                <td className="py-2 font-mono font-semibold">{tenant.tenant}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Port</td>
                <td className="py-2 font-mono">{tenant.port}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Status</td>
                <td className="py-2">
                  <span className={`status-badge ${getStatusColor(tenant.status)}`}>
                    {tenant.status}
                  </span>
                </td>
              </tr>
              <tr>
                <td className="py-2 text-gray-600">Uptime</td>
                <td className="py-2 font-mono">{formatUptime(tenant.uptime_seconds || 0)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Resource Usage</h2>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Memory Used</td>
                <td className="py-2 font-mono">{tenant.memory_used || 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Max Memory</td>
                <td className="py-2 font-mono">{tenant.maxmemory ? formatBytes(tenant.maxmemory) : 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Docker Limit</td>
                <td className="py-2 font-mono">{tenant.docker_limit ? formatBytes(tenant.docker_limit) : 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Connected Clients</td>
                <td className="py-2 font-mono">{tenant.clients || '0'}</td>
              </tr>
              <tr>
                <td className="py-2 text-gray-600">Total Keys</td>
                <td className="py-2 font-mono">{tenant.keys || '0'}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* Handover Section */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold flex items-center space-x-2">
            <Key className="w-5 h-5" />
            <span>Handover / WordPress Integration</span>
          </h2>
          <button
            onClick={() => setShowHandover(!showHandover)}
            className="btn-primary"
          >
            {showHandover ? 'Hide' : 'Show'} Credentials
          </button>
        </div>

        {showHandover && (
          <>
            {loadingHandover ? (
              <div className="text-center py-8 text-gray-500">Loading handover information...</div>
            ) : handoverInfo ? (
              <div className="space-y-4">
                {/* Credentials Text */}
                <div className="border border-gray-200 p-4">
                  <h3 className="font-semibold text-sm mb-2">Connection Credentials</h3>
                  <p className="text-xs text-gray-600 mb-3">Complete connection information for your Redis instance:</p>
                  <pre className="bg-gray-50 border border-gray-200 p-3 rounded text-xs overflow-x-auto whitespace-pre-wrap">
{handoverInfo.credentials_text}
                  </pre>
                  <button
                    onClick={() => copyToClipboard(handoverInfo.credentials_text, 'Credentials')}
                    className="btn mt-3 w-full flex items-center justify-center space-x-2"
                  >
                    <Copy className="w-4 h-4" />
                    <span>Copy Credentials</span>
                  </button>
                </div>

                {/* CA Certificate */}
                {handoverInfo.ca_certificate && (
                  <div className="border border-gray-200 p-4">
                    <h3 className="font-semibold text-sm mb-2">TLS CA Certificate</h3>
                    <p className="text-xs text-gray-600 mb-3">Save this certificate as <code className="bg-gray-100 px-1">ca.crt</code> in your WordPress redis directory:</p>
                    <pre className="bg-gray-900 text-gray-100 p-3 rounded text-xs overflow-x-auto whitespace-pre-wrap font-mono">
{handoverInfo.ca_certificate}
                    </pre>
                    <button
                      onClick={() => copyToClipboard(handoverInfo.ca_certificate, 'CA Certificate')}
                      className="btn mt-3 w-full flex items-center justify-center space-x-2"
                    >
                      <Copy className="w-4 h-4" />
                      <span>Copy CA Certificate</span>
                    </button>
                  </div>
                )}

                {/* WordPress Configuration */}
                {handoverInfo.wordpress_config?.full_config && (
                  <div className="border border-gray-200 p-4">
                    <h3 className="font-semibold text-sm mb-2">WordPress Configuration</h3>
                    <p className="text-xs text-gray-600 mb-3">Add this to your <code className="bg-gray-100 px-1">wp-config.php</code> (before "That's all, stop editing!"):</p>
                    <pre className="bg-gray-900 text-gray-100 p-3 rounded text-xs overflow-x-auto whitespace-pre-wrap">
{handoverInfo.wordpress_config.full_config}
                    </pre>
                    <button
                      onClick={() => copyToClipboard(handoverInfo.wordpress_config.full_config, 'WordPress configuration')}
                      className="btn mt-3 w-full flex items-center justify-center space-x-2"
                    >
                      <Copy className="w-4 h-4" />
                      <span>Copy WordPress Config</span>
                    </button>
                  </div>
                )}

                {/* Connection String */}
                <div className="border border-gray-200 p-4">
                  <h3 className="font-semibold text-sm mb-2">Connection String</h3>
                  <p className="text-xs text-gray-600 mb-2">Use this for direct Redis connections (rediss:// indicates TLS):</p>
                  <div className="flex items-center space-x-2">
                    <code className="bg-gray-100 px-3 py-2 text-xs flex-1 overflow-x-auto">{handoverInfo.connection_string}</code>
                    <button
                      onClick={() => copyToClipboard(handoverInfo.connection_string, 'Connection string')}
                      className="text-gray-600 hover:text-gray-900"
                    >
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                {/* Regenerate Button */}
                <div className="flex justify-end pt-2">
                  <button
                    onClick={handleRegenerateHandover}
                    disabled={loadingHandover}
                    className="btn flex items-center space-x-2"
                  >
                    <RefreshCw className="w-4 h-4" />
                    <span>Regenerate Handover Package</span>
                  </button>
                </div>
              </div>
            ) : (
              <div className="text-center py-8 text-gray-500">Failed to load handover information</div>
            )}
          </>
        )}
      </div>

      {/* Backups Section */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold flex items-center space-x-2">
            <Download className="w-5 h-5" />
            <span>Backups</span>
          </h2>
          <button
            onClick={handleBackup}
            disabled={backupMutation.isPending}
            className="btn-primary flex items-center space-x-2"
          >
            <Download className="w-4 h-4" />
            <span>{backupMutation.isPending ? 'Creating...' : 'Create Backup'}</span>
          </button>
        </div>

        {backupsLoading ? (
          <div className="text-center py-8 text-gray-500">Loading backups...</div>
        ) : backups.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <p>No backups found</p>
            <p className="text-xs mt-2">Create your first backup using the button above</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="table">
              <thead>
                <tr>
                  <th>Backup File</th>
                  <th>Size</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {backups.map((backup) => (
                  <tr key={backup.file}>
                    <td className="font-mono text-xs">{backup.file}</td>
                    <td className="font-mono text-xs">{backup.size}</td>
                    <td>
                      <div className="flex items-center justify-end space-x-2">
                        <button
                          onClick={() => handleRestoreBackup(backup.file)}
                          disabled={restoreBackupMutation.isPending}
                          className="btn flex items-center space-x-1"
                          title="Restore from this backup"
                        >
                          <Upload className="w-4 h-4" />
                          <span className="text-xs">Restore</span>
                        </button>
                        <button
                          onClick={() => handleDeleteBackup(backup.file)}
                          disabled={deleteBackupMutation.isPending}
                          className="btn-danger flex items-center space-x-1"
                          title="Delete this backup"
                        >
                          <Trash2 className="w-4 h-4" />
                          <span className="text-xs">Delete</span>
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};

export default TenantDetail;
