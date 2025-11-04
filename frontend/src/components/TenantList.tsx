/**
 * CachePilot - Tenant List Component
 * 
 * Overview table of all Redis tenant instances with status and actions.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React from 'react';
import { Link } from 'react-router-dom';
import { useTenants } from '../hooks/useTenants';
import { Plus, Eye } from 'lucide-react';
import { getStatusColor } from '../utils/format';

const TenantList: React.FC = () => {
  const { tenants, isLoading } = useTenants();

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading tenants...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Tenants</h1>
          <p className="text-sm text-gray-600 mt-1">{tenants.length} tenant(s) total</p>
        </div>
        <Link to="/tenants/new" className="btn-primary flex items-center space-x-2">
          <Plus className="w-4 h-4" />
          <span>New Tenant</span>
        </Link>
      </div>

      {/* Tenants Table */}
      {tenants.length === 0 ? (
        <div className="card text-center py-12">
          <p className="text-gray-600 mb-4">No tenants found</p>
          <Link to="/tenants/new" className="btn-primary inline-flex items-center space-x-2">
            <Plus className="w-4 h-4" />
            <span>Create First Tenant</span>
          </Link>
        </div>
      ) : (
        <div className="card overflow-x-auto">
          <table className="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Port</th>
                <th>Status</th>
                <th className="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {tenants.map((tenant) => (
                <tr key={tenant.tenant} className="cursor-pointer">
                  <td>
                    <Link to={`/tenants/${tenant.tenant}`} className="font-semibold hover:underline">
                      {tenant.tenant}
                    </Link>
                  </td>
                  <td className="font-mono">{tenant.port}</td>
                  <td>
                    <span className={`status-badge ${getStatusColor(tenant.status)}`}>
                      {tenant.status}
                    </span>
                  </td>
                  <td>
                    <div className="flex items-center justify-end">
                      <Link
                        to={`/tenants/${tenant.tenant}`}
                        className="btn flex items-center space-x-1"
                      >
                        <Eye className="w-4 h-4" />
                        <span>View Details</span>
                      </Link>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default TenantList;
