/**
 * CachePilot - Authentication Hook
 * 
 * React hook for managing API key authentication and session state.
 * 
 * @author Patrick Schlesinger <cachepilot@msrv-digital.de>
 * @company MSRV Digital
 * @version 2.1.2-Beta
 * @license MIT
 * 
 * Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
 */

import { useState, useEffect } from 'react';

const API_KEY_STORAGE_KEY = 'cachepilot-api-key';

interface UseAuthReturn {
  apiKey: string | null;
  setApiKey: (key: string) => void;
  isAuthenticated: boolean;
  logout: () => void;
}

export const useAuth = (): UseAuthReturn => {
  const [apiKey, setApiKeyState] = useState<string | null>(() => {
    // Try to get API key from localStorage on mount
    const stored = localStorage.getItem(API_KEY_STORAGE_KEY);
    return stored || null;
  });

  const setApiKey = (key: string) => {
    localStorage.setItem(API_KEY_STORAGE_KEY, key);
    setApiKeyState(key);
  };

  const logout = () => {
    // Clear localStorage
    localStorage.removeItem(API_KEY_STORAGE_KEY);
    localStorage.clear();
    
    // Clear sessionStorage (important for auth error messages)
    sessionStorage.clear();
    
    // Update state
    setApiKeyState(null);
    
    // No need for window.location.href - React will handle the redirect
  };

  const isAuthenticated = !!apiKey;

  // Sync with localStorage changes from other tabs
  useEffect(() => {
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === API_KEY_STORAGE_KEY) {
        setApiKeyState(e.newValue);
      }
    };

    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  }, []);

  return {
    apiKey,
    setApiKey,
    isAuthenticated,
    logout,
  };
};
