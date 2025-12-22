# CachePilot - Frontend Development Guide

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.2-Beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

**BETA SOFTWARE NOTICE**

The CachePilot frontend is part of v2.1.2-Beta and is under active development. All core features are functional and tested. UI/UX improvements and additional dashboard features are ongoing. Test thoroughly before production deployment.

---

This guide covers the React-based frontend for CachePilot.

## Overview

The CachePilot frontend is a modern React application built with:
- **React 18** - UI framework
- **TypeScript** - Type-safe development
- **Vite** - Fast build tool
- **Tailwind CSS** - Utility-first CSS framework
- **React Query** - Data fetching and caching
- **Axios** - HTTP client

## Prerequisites

- Node.js 18+ and npm 9+
- Running CachePilot API
- API key for authentication

## Quick Start

```bash
# Navigate to frontend directory
cd /opt/cachepilot/frontend

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Edit .env with your API key
nano .env

# Start development server
npm run dev

# Build for production
npm run build
```

## Project Structure

```
frontend/
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── vite.config.ts        # Vite build configuration
├── tailwind.config.js    # Tailwind CSS configuration
├── .env.example          # Environment variables template
├── public/               # Static assets
│   ├── index.html
│   └── favicon.ico
└── src/                  # Source code
    ├── main.tsx          # Application entry point
    ├── App.tsx           # Main app component
    ├── api/              # API client
    │   └── client.ts
    ├── components/       # React components
    │   ├── Dashboard.tsx
    │   ├── TenantList.tsx
    │   ├── TenantDetail.tsx
    │   ├── CreateTenant.tsx
    │   ├── Monitoring.tsx
    │   ├── Alerts.tsx
    │   └── Settings.tsx
    ├── hooks/            # Custom React hooks
    │   ├── useApi.ts
    │   └── useAuth.ts
    └── styles/           # Stylesheets
        └── main.css
```

## Development

### Environment Configuration

Create `.env` file:

```env
# API Configuration
# For development (direct API access):
VITE_API_BASE_URL=http://localhost:8000

# For production (nginx reverse proxy):
# VITE_API_BASE_URL=/api

VITE_API_KEY=your-api-key-here

# App Configuration
VITE_APP_TITLE=CachePilot
VITE_REFRESH_INTERVAL=30
```

**Note:** When using nginx reverse proxy (recommended for production), set `VITE_API_BASE_URL=/api` to use relative paths. For development or direct API access, use `http://localhost:8000`.

### Available Scripts

```bash
# Development server (hot reload)
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview

# Type checking
npm run type-check

# Linting
npm run lint

# Format code
npm run format
```

### Development Server

The development server runs at `http://localhost:5173` by default with:
- Hot module replacement
- Fast refresh
- TypeScript type checking
- ESLint integration

### API Integration

The frontend communicates with the CachePilot API using the API client:

```typescript
// src/api/client.ts
import axios from 'axios';

// Use relative path when behind nginx reverse proxy, or absolute URL for direct access
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api';
const API_KEY = import.meta.env.VITE_API_KEY;

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'X-API-Key': API_KEY,
    'Content-Type': 'application/json',
  },
});

export const fetchTenants = async () => {
  const response = await apiClient.get('/api/v1/tenants');
  return response.data;
};

export const createTenant = async (data: TenantCreate) => {
  const response = await apiClient.post('/api/v1/tenants', data);
  return response.data;
};
```

**Note:** When deployed behind nginx (production), API calls use relative paths (`/api/v1/...`). For development with direct API access, use `http://localhost:8000` as base URL.

## Production Build

### Building

```bash
# Build optimized production bundle
npm run build

# Output in dist/ directory
ls -la dist/
```

### Build Output

```
dist/
├── index.html           # Entry HTML file
├── assets/             # Bundled assets
│   ├── index-[hash].js   # JavaScript bundle
│   └── index-[hash].css  # CSS bundle
└── favicon.ico         # Application icon
```

### Deployment with Nginx

#### Nginx Configuration

Create `/etc/nginx/sites-available/cachepilot-frontend`:

```nginx
server {
    listen 80;
    server_name redis-manager.example.com;
    
    root /opt/cachepilot/frontend/dist;
    index index.html;
    
    # Frontend
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # API Proxy
    location /api/ {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

#### Enable Site

```bash
# Create symlink
sudo ln -s /etc/nginx/sites-available/cachepilot-frontend /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### SSL/TLS with Let's Encrypt

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d redis-manager.example.com

# Auto-renewal is configured automatically
```

## Component Development

### Creating Components

Example component structure:

```typescript
// src/components/ExampleComponent.tsx
import React, { useState, useEffect } from 'react';
import { useApi } from '../hooks/useApi';

interface ExampleProps {
  tenantName: string;
  onUpdate?: () => void;
}

export const ExampleComponent: React.FC<ExampleProps> = ({ 
  tenantName, 
  onUpdate 
}) => {
  const [data, setData] = useState(null);
  const { loading, error, refetch } = useApi();

  useEffect(() => {
    loadData();
  }, [tenantName]);

  const loadData = async () => {
    // Implementation
  };

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error.message}</div>;

  return (
    <div className="p-4 bg-white rounded-lg shadow">
      {/* Component content */}
    </div>
  );
};
```

### Custom Hooks

```typescript
// src/hooks/useApi.ts
import { useState, useCallback } from 'react';

export function useApi<T>() {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const execute = useCallback(async (apiCall: () => Promise<T>) => {
    setLoading(true);
    setError(null);
    
    try {
      const result = await apiCall();
      setData(result);
      return result;
    } catch (err) {
      setError(err as Error);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { data, loading, error, execute };
}
```

## Styling

### Tailwind CSS

The project uses Tailwind CSS for styling:

```typescript
// Example with Tailwind classes
<div className="flex items-center justify-between p-4 bg-gray-100 rounded-lg">
  <h2 className="text-xl font-bold text-gray-900">Title</h2>
  <button className="px-4 py-2 text-white bg-blue-600 rounded hover:bg-blue-700">
    Action
  </button>
</div>
```

### Custom Styles

Global styles in `src/styles/main.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer components {
  .btn-primary {
    @apply px-4 py-2 text-white bg-blue-600 rounded hover:bg-blue-700 transition;
  }
  
  .card {
    @apply p-6 bg-white rounded-lg shadow-md;
  }
}
```

## Testing

### Setup Testing

```bash
# Install testing libraries
npm install --save-dev @testing-library/react @testing-library/jest-dom vitest
```

### Component Tests

```typescript
// src/components/__tests__/TenantList.test.tsx
import { render, screen } from '@testing-library/react';
import { TenantList } from '../TenantList';

describe('TenantList', () => {
  it('renders tenant list', () => {
    render(<TenantList />);
    expect(screen.getByText('Tenants')).toBeInTheDocument();
  });
});
```

## Performance Optimization

### Code Splitting

```typescript
// Lazy load components
import { lazy, Suspense } from 'react';

const Dashboard = lazy(() => import('./components/Dashboard'));
const TenantDetail = lazy(() => import('./components/TenantDetail'));

function App() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <Dashboard />
    </Suspense>
  );
}
```

### Memoization

```typescript
import { memo, useMemo, useCallback } from 'react';

// Memoize component
export const TenantCard = memo(({ tenant }) => {
  return <div>{tenant.name}</div>;
});

// Memoize expensive computation
const sortedTenants = useMemo(() => {
  return tenants.sort((a, b) => a.name.localeCompare(b.name));
}, [tenants]);

// Memoize callback
const handleClick = useCallback(() => {
  console.log('Clicked');
}, []);
```

## Troubleshooting

### Common Issues

**Issue: "Cannot connect to API"**
- Check API is running: `systemctl status cachepilot-api`
- Verify API_BASE_URL in `.env` (use `/api` for nginx proxy, `http://localhost:8000` for direct)
- Check CORS settings in `/etc/cachepilot/api.yaml`
- Test API directly: `curl http://localhost:8000/api/v1/health`
- Check nginx is running: `systemctl status nginx`
- Check nginx config: `nginx -t`

**Issue: "Invalid API key"**
- Verify API key in `.env` matches `/etc/cachepilot/api-keys.json`
- Check API key format (should be 64 character hex string)
- Generate new key if needed: `cachepilot api key generate <name>`

**Issue: "Build fails"**
- Clear node_modules: `rm -rf node_modules && npm install`
- Check Node.js version: `node --version` (should be 18+)
- Review build errors in terminal output
- Check TypeScript errors: `npm run type-check`

**Issue: "White screen after deployment"**
- Check browser console for errors
- Verify nginx configuration
- Check file permissions in `dist/` directory
- Ensure API proxy is working

### Debugging

Enable debug mode:

```env
# .env
VITE_DEBUG=true
VITE_LOG_LEVEL=debug
```

View logs in browser console (F12).

## Best Practices

### 1. Code Organization
- Keep components small and focused
- Use custom hooks for reusable logic
- Separate API calls into api client
- Use TypeScript for type safety

### 2. State Management
- Use local state for component-specific data
- Use React Query for server state
- Consider Context API for global state
- Avoid prop drilling with composition

### 3. Performance
- Lazy load routes and heavy components
- Memoize expensive computations
- Use React.memo for pure components
- Optimize re-renders

### 4. Security
- Never commit `.env` files
- Validate user input
- Sanitize HTML content
- Use HTTPS in production

### 5. Accessibility
- Use semantic HTML
- Add ARIA labels
- Ensure keyboard navigation
- Test with screen readers

## Resources

- [React Documentation](https://react.dev/)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [Vite Guide](https://vitejs.dev/guide/)
- [Tailwind CSS Docs](https://tailwindcss.com/docs)
- [React Query Docs](https://tanstack.com/query/latest)

## See Also

- [API Documentation](API.md) - REST API reference
- [Configuration Guide](CONFIGURATION.md) - Configuration reference
- [Deployment Guide](DEPLOYMENT.md) - Deployment instructions
