# Configuration Templates

This directory contains template configuration files for CachePilot.

## Important Notice

**These are NOT the active configuration files used by the system.**

### Active Configuration Location

The actual configuration files used by CachePilot are located in:
```
/etc/cachepilot/
```

### Purpose of This Directory

This directory serves as:
- Reference templates for administrators
- Source files during fresh installations
- Examples for configuration options

### Installation Process

During installation, files from this directory are:
1. Copied to `/etc/cachepilot/`
2. Customized with your settings (IP addresses, etc.)
3. Used by the running system

### Template Files

| File | Purpose |
|------|---------|
| `system.yaml` | System-wide configuration template |
| `api.yaml` | REST API configuration template |
| `frontend.yaml` | Frontend configuration template |
| `logging-config.yaml` | Logging configuration template |
| `monitoring-config.yaml` | Monitoring configuration template |
| `.env.example` | Environment variables example |

### Making Configuration Changes

**DO NOT** edit files in this directory. Instead:

1. Edit the active configuration in `/etc/cachepilot/`
2. Restart services to apply changes:
   ```bash
   systemctl restart cachepilot-api
   ```

### See Also

- [Configuration Documentation](../docs/CONFIGURATION.md)
- [Deployment Guide](../docs/DEPLOYMENT.md)
