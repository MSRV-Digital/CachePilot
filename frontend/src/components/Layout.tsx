/**
 * CachePilot - Layout Component
 * 
 * Main layout wrapper with navigation and sidebar.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Terminal, Github, LogOut } from 'lucide-react';
import { useAuth } from '../hooks/useAuth';

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const location = useLocation();
  const { logout } = useAuth();

  const isActive = (path: string) => {
    return location.pathname === path;
  };

  return (
    <div className="min-h-screen flex flex-col">
      {/* Header */}
      <header className="border-b-2 border-gray-900 bg-white">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <Link to="/" className="flex items-center space-x-3 hover:opacity-80 transition-opacity">
              <Terminal className="w-6 h-6" />
              <div>
                <h1 className="text-xl font-semibold">CACHEPILOT MANAGER</h1>
                <p className="text-xs text-gray-600">Multi-Tenant Redis Management System</p>
              </div>
            </Link>

            <nav className="flex items-center space-x-6">
              <Link
                to="/"
                className={`text-sm hover:text-gray-600 transition-colors ${
                  isActive('/') ? 'font-semibold' : ''
                }`}
              >
                Dashboard
              </Link>
              <Link
                to="/tenants"
                className={`text-sm hover:text-gray-600 transition-colors ${
                  isActive('/tenants') ? 'font-semibold' : ''
                }`}
              >
                Tenants
              </Link>
              <Link
                to="/health"
                className={`text-sm hover:text-gray-600 transition-colors ${
                  isActive('/health') ? 'font-semibold' : ''
                }`}
              >
                Health
              </Link>
              <a
                href="https://github.com/MSRV-Digital/CachePilot"
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm hover:text-gray-600 transition-colors flex items-center space-x-1"
              >
                <Github className="w-4 h-4" />
                <span>GitHub</span>
              </a>
              <button
                onClick={logout}
                className="text-sm hover:text-gray-600 transition-colors flex items-center space-x-1"
                title="Logout"
              >
                <LogOut className="w-4 h-4" />
                <span>Logout</span>
              </button>
            </nav>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 bg-gray-50">
        <div className="max-w-7xl mx-auto px-4 py-8">
          {children}
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-300 bg-white">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between text-xs text-gray-600">
            <div>
              CachePilot v2.1.2-Beta | Patrick Schlesinger, MSRV Digital
            </div>
            <div>
              Professional Multi-Tenant Redis Management
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default Layout;
