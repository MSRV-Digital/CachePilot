/**
 * CachePilot - Tenant Detail Component
 * 
 * Detailed view of a Redis tenant with statistics, actions, and handover information.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React, { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useTenant, useStartTenant, useStopTenant, useRestartTenant, useDeleteTenant } from '../hooks/useTenants';
import { useCreateBackup, useListBackups, useDeleteBackup, useRestoreBackup } from '../hooks/useMonitoring';
import { ArrowLeft, Play, Square, RotateCw, Trash2, Download, Copy, RefreshCw, Key, Upload } from 'lucide-react';
import { getStatusColor, formatUptime, formatBytes, formatMB } from '../utils/format';
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
              {tenant.port_tls && (
                <tr className="border-b border-gray-200">
                  <td className="py-2 text-gray-600">TLS Port</td>
                  <td className="py-2 font-mono">{tenant.port_tls}</td>
                </tr>
              )}
              {tenant.port_plain && (
                <tr className="border-b border-gray-200">
                  <td className="py-2 text-gray-600">Plain-Text Port</td>
                  <td className="py-2">
                    <span className="font-mono">{tenant.port_plain}</span>
                    <span className="ml-2 text-xs text-yellow-600">⚠ Not encrypted</span>
                  </td>
                </tr>
              )}
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
          <h2 className="text-lg font-semibold mb-4">Security Configuration</h2>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Security Mode</td>
                <td className="py-2">
                  <span className="font-semibold">
                    {tenant.security_mode || 'tls-only'}
                  </span>
                </td>
              </tr>
              {tenant.port_tls && (
                <tr className="border-b border-gray-200">
                  <td className="py-2 text-gray-600">TLS Port</td>
                  <td className="py-2 font-mono">{tenant.port_tls}</td>
                </tr>
              )}
              {tenant.port_plain && (
                <tr className="border-b border-gray-200">
                  <td className="py-2 text-gray-600">Plain-Text Port</td>
                  <td className="py-2">
                    <span className="font-mono">{tenant.port_plain}</span>
                    <span className="ml-2 text-xs text-yellow-600">⚠ Not encrypted</span>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          
          {/* Change Security Mode */}
          <div className="mt-4 pt-4 border-t border-gray-200">
            <h3 className="text-sm font-semibold mb-2">Change Security Mode</h3>
            <div className="flex items-center space-x-2">
              <select
                className="input flex-1"
                value={tenant.security_mode || 'tls-only'}
                onChange={(e) => {
                  const newMode = e.target.value;
                  if (newMode === (tenant.security_mode || 'tls-only')) {
                    return;
                  }
                  if (!window.confirm(`Change security mode to ${newMode}? This will restart the tenant and may allocate new ports.`)) {
                    e.target.value = tenant.security_mode || 'tls-only';
                    return;
                  }
                  setActionMessage(null);
                  getApiClient().changeSecurityMode(tenant.tenant, newMode)
                    .then(() => {
                      setActionMessage({ type: 'success', text: `Security mode changed to ${newMode}. Reloading...` });
                      setTimeout(async () => {
                        await refetch();
                        setActionMessage(null);
                      }, 2000);
                    })
                    .catch((error) => {
                      const errorMessage = error instanceof Error ? error.message : 'Failed to change mode';
                      setActionMessage({ type: 'error', text: errorMessage });
                      setTimeout(() => setActionMessage(null), 8000);
                      e.target.value = tenant.security_mode || 'tls-only';
                    });
                }}
                id="change-security-mode"
              >
                <option value="tls-only">TLS Only</option>
                <option value="dual-mode">Dual Mode</option>
                <option value="plain-only">Plain-Text Only</option>
              </select>
            </div>
            <p className="text-xs text-gray-600 mt-2">
              Changing the security mode will restart the tenant and may allocate new ports.
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Resource Usage</h2>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Memory Used</td>
                <td className="py-2 font-mono">{tenant.memory_used || 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Memory Peak</td>
                <td className="py-2 font-mono">{tenant.memory_peak || 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Max Memory</td>
                <td className="py-2 font-mono">{tenant.maxmemory ? formatMB(tenant.maxmemory) : 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Docker Limit</td>
                <td className="py-2 font-mono">{tenant.docker_limit ? formatMB(tenant.docker_limit) : 'N/A'}</td>
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

        <div className="card">
          <h2 className="text-lg font-semibold mb-4">Performance Statistics</h2>
          <table className="w-full text-sm">
            <tbody>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Total Commands</td>
                <td className="py-2 font-mono">{tenant.total_commands ? parseInt(tenant.total_commands).toLocaleString() : 'N/A'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Cache Hit Rate</td>
                <td className="py-2 font-mono">
                  {tenant.hit_rate && tenant.hit_rate !== 'N/A' ? (
                    <span className={tenant.hit_rate.replace('%', '') >= '80' ? 'text-green-600' : 'text-yellow-600'}>
                      {tenant.hit_rate}
                    </span>
                  ) : 'N/A'}
                </td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Keyspace Hits</td>
                <td className="py-2 font-mono">{tenant.keyspace_hits ? parseInt(tenant.keyspace_hits).toLocaleString() : '0'}</td>
              </tr>
              <tr className="border-b border-gray-200">
                <td className="py-2 text-gray-600">Keyspace Misses</td>
                <td className="py-2 font-mono">{tenant.keyspace_misses ? parseInt(tenant.keyspace_misses).toLocaleString() : '0'}</td>
              </tr>
              <tr>
                <td className="py-2 text-gray-600">Evicted Keys</td>
                <td className="py-2 font-mono">{tenant.evicted_keys || '0'}</td>
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

                {/* TLS WordPress Configuration */}
                {handoverInfo.tls_connection && (
                  <div className="border border-gray-200 p-4">
                    <h3 className="font-semibold text-sm mb-2">WordPress Configuration (TLS - Recommended)</h3>
                    <p className="text-xs text-gray-600 mb-3">Add this to your <code className="bg-gray-100 px-1">wp-config.php</code> (before "That's all, stop editing!"):</p>
                    <pre className="bg-gray-900 text-gray-100 p-3 rounded text-xs overflow-x-auto whitespace-pre-wrap">
{handoverInfo.tls_connection.wordpress_config}
                    </pre>
                    <button
                      onClick={() => copyToClipboard(handoverInfo.tls_connection.wordpress_config, 'TLS WordPress configuration')}
                      className="btn mt-3 w-full flex items-center justify-center space-x-2"
                    >
                      <Copy className="w-4 h-4" />
                      <span>Copy TLS WordPress Config</span>
                    </button>
                    
                    <div className="mt-4 pt-4 border-t border-gray-200">
                      <h4 className="font-semibold text-xs mb-2">TLS Connection String</h4>
                      <p className="text-xs text-gray-600 mb-2">For direct Redis connections with TLS encryption:</p>
                      <div className="flex items-center space-x-2">
                        <code className="bg-gray-100 px-3 py-2 text-xs flex-1 overflow-x-auto">{handoverInfo.tls_connection.connection_string}</code>
                        <button
                          onClick={() => copyToClipboard(handoverInfo.tls_connection.connection_string, 'TLS connection string')}
                          className="text-gray-600 hover:text-gray-900"
                        >
                          <Copy className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Plain-Text WordPress Configuration */}
                {handoverInfo.plaintext_connection && (
                  <div className="border border-yellow-200 bg-yellow-50 p-4">
                    <h3 className="font-semibold text-sm mb-2">WordPress Configuration (Plain-Text - Alternative)</h3>
                    <p className="text-xs text-gray-600 mb-3">
                      Add this to your <code className="bg-gray-100 px-1">wp-config.php</code> if TLS is not available:
                      <span className="block mt-1 text-yellow-700">⚠ Warning: Traffic is not encrypted</span>
                    </p>
                    <pre className="bg-gray-900 text-gray-100 p-3 rounded text-xs overflow-x-auto whitespace-pre-wrap">
{handoverInfo.plaintext_connection.wordpress_config}
                    </pre>
                    <button
                      onClick={() => copyToClipboard(handoverInfo.plaintext_connection.wordpress_config, 'Plain-text WordPress configuration')}
                      className="btn mt-3 w-full flex items-center justify-center space-x-2"
                    >
                      <Copy className="w-4 h-4" />
                      <span>Copy Plain-Text WordPress Config</span>
                    </button>
                    
                    <div className="mt-4 pt-4 border-t border-yellow-200">
                      <h4 className="font-semibold text-xs mb-2">Plain-Text Connection String</h4>
                      <p className="text-xs text-gray-600 mb-2">For direct Redis connections without encryption:</p>
                      <div className="flex items-center space-x-2">
                        <code className="bg-gray-100 px-3 py-2 text-xs flex-1 overflow-x-auto">{handoverInfo.plaintext_connection.connection_string}</code>
                        <button
                          onClick={() => copyToClipboard(handoverInfo.plaintext_connection.connection_string, 'Plain-text connection string')}
                          className="text-gray-600 hover:text-gray-900"
                        >
                          <Copy className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  </div>
                )}

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
