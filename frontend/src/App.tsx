/**
 * CachePilot - Main Application Component
 * 
 * Root component with routing, authentication, and layout management.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.0-beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { getApiClient, AUTH_ERROR_EVENT } from './api/client';
import { useAuth } from './hooks/useAuth';
import Layout from './components/Layout';
import Dashboard from './components/Dashboard';
import TenantList from './components/TenantList';
import TenantDetail from './components/TenantDetail';
import CreateTenant from './components/CreateTenant';
import Health from './components/Health';

// Login component
const Login: React.FC<{ onLogin: (key: string) => void; authError?: string }> = ({ onLogin, authError }) => {
  const [apiKey, setApiKey] = useState('');
  const [error, setError] = useState('');
  const [isValidating, setIsValidating] = useState(false);
  const [showAuthError, setShowAuthError] = useState(!!authError);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    
    if (!apiKey.trim()) {
      setError('Please enter an API key');
      return;
    }

    setIsValidating(true);
    
    try {
      // Create temporary client to validate key
      const tempClient = new (await import('./api/client')).ApiClient(apiKey.trim());
      const isValid = await tempClient.validateApiKey();
      
      if (isValid) {
        onLogin(apiKey.trim());
      } else {
        setError('Invalid API key. Please check and try again.');
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to validate API key';
      setError(errorMessage);
    } finally {
      setIsValidating(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      {showAuthError && authError && (
        <div className="fixed top-0 left-0 right-0 bg-red-600 text-white px-4 py-3 flex items-center justify-between z-50">
          <p className="font-semibold">{authError}</p>
          <button
            onClick={() => setShowAuthError(false)}
            className="text-white hover:text-gray-200 font-bold text-xl ml-4"
            aria-label="Close"
          >
            ×
          </button>
        </div>
      )}
      <div className="card max-w-md w-full">
        <h1 className="text-2xl font-semibold mb-2">CachePilot</h1>
        <p className="text-sm text-gray-600 mb-6">Enter your API key to continue</p>
        
        <form onSubmit={handleSubmit}>
          <div className="mb-4">
            <label htmlFor="apiKey" className="block text-sm font-medium mb-2">
              API Key
            </label>
            <input
              id="apiKey"
              type="password"
              className="input"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="Enter your API key"
              autoFocus
            />
            {error && <p className="text-status-stopped text-xs mt-1">{error}</p>}
          </div>
          
          <button 
            type="submit" 
            className="btn-primary w-full"
            disabled={isValidating}
          >
            {isValidating ? 'Validating...' : 'Login'}
          </button>
        </form>

        <div className="mt-6 pt-6 border-t border-gray-200">
          <p className="text-xs text-gray-600">
            Generate an API key using:
          </p>
          <code className="block mt-2 p-2 bg-gray-100 text-xs border border-gray-200">
            cachepilot api key generate frontend
          </code>
        </div>
      </div>
    </div>
  );
};

const AUTH_ERROR_STORAGE_KEY = 'cachepilot-auth-error';

const App: React.FC = () => {
  const { apiKey, setApiKey, isAuthenticated, logout } = useAuth();
  const [authError, setAuthError] = useState(false);
  const [authErrorMessage, setAuthErrorMessage] = useState(() => {
    // Check for stored auth error on mount
    return sessionStorage.getItem(AUTH_ERROR_STORAGE_KEY) || '';
  });
  const [isInitialized, setIsInitialized] = useState(false);

  // Listen for auth errors globally
  useEffect(() => {
    const handleAuthError = (event: Event) => {
      const customEvent = event as CustomEvent<{ message: string }>;
      const message = customEvent.detail.message || 'Authentication failed. Please log in again.';
      console.error('Authentication error:', message);
      
      // Store error message in sessionStorage so it persists across state updates
      sessionStorage.setItem(AUTH_ERROR_STORAGE_KEY, message);
      setAuthErrorMessage(message);
      setAuthError(true);
      
      // Clear auth state and logout
      logout();
    };

    window.addEventListener(AUTH_ERROR_EVENT, handleAuthError);
    
    return () => {
      window.removeEventListener(AUTH_ERROR_EVENT, handleAuthError);
    };
  }, [logout]);

  useEffect(() => {
    if (apiKey) {
      // Initialize API client with the key
      try {
        getApiClient(apiKey);
        setAuthError(false);
        setAuthErrorMessage('');
        setIsInitialized(true);
      } catch (error) {
        console.error('Failed to initialize API client:', error);
        setAuthError(true);
        setAuthErrorMessage('Failed to initialize API client');
        setIsInitialized(false);
        logout();
      }
    } else {
      setIsInitialized(false);
    }
  }, [apiKey, logout]);

  const handleLogin = (key: string) => {
    // Clear any stored auth errors on successful login
    sessionStorage.removeItem(AUTH_ERROR_STORAGE_KEY);
    setApiKey(key);
    setAuthError(false);
    setAuthErrorMessage('');
  };

  // Show login if not authenticated or auth error
  if (!isAuthenticated || authError) {
    return <Login onLogin={handleLogin} authError={authErrorMessage} />;
  }

  // Show loading while initializing API client
  if (!isInitialized) {
    return <div className="min-h-screen flex items-center justify-center">
      <div className="text-gray-500">Initializing...</div>
    </div>;
  }

  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/tenants" element={<TenantList />} />
          <Route path="/tenants/new" element={<CreateTenant />} />
          <Route path="/tenants/:name" element={<TenantDetail />} />
          <Route path="/health" element={<Health />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
};

export default App;
