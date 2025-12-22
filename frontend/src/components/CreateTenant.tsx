/**
 * CachePilot - Create Tenant Component
 * 
 * Form for creating new Redis tenant instances with validation.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useCreateTenant } from '../hooks/useTenants';
import { ArrowLeft } from 'lucide-react';
import type { SecurityMode } from '../api/types';

const CreateTenant: React.FC = () => {
  const navigate = useNavigate();
  const createMutation = useCreateTenant();
  const [formData, setFormData] = useState<{
    tenant_name: string;
    maxmemory_mb: number;
    docker_limit_mb: number;
    security_mode: SecurityMode;
  }>({
    tenant_name: '',
    maxmemory_mb: 256,
    docker_limit_mb: 512,
    security_mode: 'tls-only',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const validate = () => {
    const newErrors: Record<string, string> = {};

    if (!formData.tenant_name.trim()) {
      newErrors.tenant_name = 'Tenant name is required';
    } else if (!/^[a-z0-9-]+$/.test(formData.tenant_name)) {
      newErrors.tenant_name = 'Only lowercase letters, numbers, and hyphens allowed';
    }

    if (formData.maxmemory_mb < 64) {
      newErrors.maxmemory_mb = 'Minimum 64 MB';
    } else if (formData.maxmemory_mb > 4096) {
      newErrors.maxmemory_mb = 'Maximum 4096 MB';
    }

    if (formData.docker_limit_mb < formData.maxmemory_mb) {
      newErrors.docker_limit_mb = 'Must be >= max memory';
    } else if (formData.docker_limit_mb > 8192) {
      newErrors.docker_limit_mb = 'Maximum 8192 MB';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (!validate()) {
      return;
    }

    try {
      await createMutation.mutateAsync(formData);
      navigate('/tenants');
    } catch (error) {
      setErrors({ submit: `Failed to create tenant: ${error}` });
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center space-x-4">
        <Link to="/tenants" className="btn inline-flex items-center space-x-2">
          <ArrowLeft className="w-4 h-4" />
          <span>Back</span>
        </Link>
        <div>
          <h1 className="text-2xl font-semibold">Create Tenant</h1>
          <p className="text-sm text-gray-600 mt-1">Set up a new Redis tenant</p>
        </div>
      </div>

      {/* Form */}
      <div className="card max-w-2xl">
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Tenant Name */}
          <div>
            <label htmlFor="tenant_name" className="block text-sm font-medium mb-2">
              Tenant Name *
            </label>
            <input
              id="tenant_name"
              type="text"
              className="input"
              value={formData.tenant_name}
              onChange={(e) => setFormData({ ...formData, tenant_name: e.target.value.toLowerCase() })}
              placeholder="my-tenant"
              required
            />
            {errors.tenant_name && (
              <p className="text-status-stopped text-xs mt-1">{errors.tenant_name}</p>
            )}
            <p className="text-xs text-gray-600 mt-1">
              Only lowercase letters, numbers, and hyphens
            </p>
          </div>

          {/* Max Memory */}
          <div>
            <label htmlFor="maxmemory_mb" className="block text-sm font-medium mb-2">
              Max Memory (MB) *
            </label>
            <input
              id="maxmemory_mb"
              type="number"
              className="input"
              value={formData.maxmemory_mb}
              onChange={(e) => setFormData({ ...formData, maxmemory_mb: parseInt(e.target.value) })}
              min="64"
              max="4096"
              required
            />
            {errors.maxmemory_mb && (
              <p className="text-status-stopped text-xs mt-1">{errors.maxmemory_mb}</p>
            )}
            <p className="text-xs text-gray-600 mt-1">
              Redis maxmemory limit (64-4096 MB)
            </p>
          </div>

          {/* Docker Memory Limit */}
          <div>
            <label htmlFor="docker_limit_mb" className="block text-sm font-medium mb-2">
              Docker Memory Limit (MB) *
            </label>
            <input
              id="docker_limit_mb"
              type="number"
              className="input"
              value={formData.docker_limit_mb}
              onChange={(e) => setFormData({ ...formData, docker_limit_mb: parseInt(e.target.value) })}
              min="64"
              max="8192"
              required
            />
            {errors.docker_limit_mb && (
              <p className="text-status-stopped text-xs mt-1">{errors.docker_limit_mb}</p>
            )}
            <p className="text-xs text-gray-600 mt-1">
              Container memory limit (must be ≥ max memory)
            </p>
          </div>

          {/* Security Mode */}
          <div>
            <label htmlFor="security_mode" className="block text-sm font-medium mb-2">
              Security Mode *
            </label>
            <select
              id="security_mode"
              className="input"
              value={formData.security_mode}
              onChange={(e) => setFormData({ 
                ...formData, 
                security_mode: e.target.value as 'tls-only' | 'dual-mode' | 'plain-only' 
              })}
            >
              <option value="tls-only">TLS Only (Most Secure - Recommended)</option>
              <option value="dual-mode">Dual Mode (TLS + Plain-Text)</option>
              <option value="plain-only">Plain-Text Only (Password Only)</option>
            </select>
            <p className="text-xs text-gray-600 mt-1">
              <strong>TLS Only:</strong> Requires CA certificate, encrypted connection (port 7300-7599)<br />
              <strong>Dual Mode:</strong> Both TLS and Plain-Text on separate ports<br />
              <strong>Plain-Text:</strong> Password-only, no certificate required (port 7600-7899, not encrypted)
            </p>
          </div>

          {/* Submit Error */}
          {errors.submit && (
            <div className="p-4 bg-gray-100 border border-status-stopped">
              <p className="text-status-stopped text-sm">{errors.submit}</p>
            </div>
          )}

          {/* Actions */}
          <div className="flex items-center space-x-4">
            <button
              type="submit"
              disabled={createMutation.isPending}
              className="btn-primary"
            >
              {createMutation.isPending ? 'Creating...' : 'Create Tenant'}
            </button>
            <Link to="/tenants" className="btn">
              Cancel
            </Link>
          </div>
        </form>
      </div>

      {/* Info Box */}
      <div className="card max-w-2xl bg-gray-50">
        <h3 className="text-sm font-semibold mb-2">What happens next?</h3>
        <ul className="text-xs space-y-1 text-gray-700">
          <li>• Redis instance will be created with your selected security mode</li>
          <li>• A secure password will be generated automatically</li>
          <li>• Instance will start on an available port (TLS: 7300-7599, Plain: 7600-7899)</li>
          <li>• Connection details and credentials will be available in tenant view</li>
        </ul>
      </div>
    </div>
  );
};

export default CreateTenant;
