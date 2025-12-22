Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.2-Beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

# CachePilot - Git-Based Workflow Guide

This guide explains how CachePilot uses Git for installation, updates, and version management.

## Overview

Starting with CachePilot v2.1.0, the system uses a Git-based deployment model:

- **Installation**: Direct clone from GitHub to `/opt/cachepilot`
- **Updates**: Simple `git pull` instead of file copying
- **Rollback**: Git history enables easy version rollback
- **Branch Management**: Switch between stable and beta versions

## Installation

### New Installation (Git-Based)

The installation script automatically clones the repository:

```bash
sudo bash install.sh
```

During installation, you can choose:
- **main** branch - Stable releases (recommended for production)
- **develop** branch - Beta versions with latest features

### Converting Existing Installation

If you have a legacy installation (pre-v2.1.0), convert to Git-based:

```bash
sudo bash /opt/cachepilot/install/scripts/git-setup.sh convert
```

This will:
1. Initialize Git repository
2. Add remote to GitHub
3. Fetch and sync with remote branch
4. Preserve local customizations

## Updates

### Check for Updates

```bash
cachepilot system check-updates
```

This shows:
- Current branch and commit
- Available updates
- Changelog preview

### Install Updates

```bash
sudo cachepilot system update
```

Or directly:

```bash
sudo bash /opt/cachepilot/install/upgrade.sh
```

The upgrade process:
1. Detects Git-based installation
2. Stashes any local changes
3. Pulls latest changes from GitHub
4. Updates dependencies
5. Restarts services

### Manual Update (Advanced)

For advanced users who want more control:

```bash
cd /opt/cachepilot
sudo git fetch origin
sudo git pull origin main  # or 'develop'
sudo systemctl restart cachepilot-api
```

## Version Management

### View System Information

```bash
cachepilot system info
```

Shows:
- Current branch
- Commit hash and date
- Latest tag
- Local modifications
- Available updates

Detailed version info:

```bash
cachepilot version
```

### Rollback to Previous Version

If an update causes issues, rollback to a previous commit:

```bash
sudo cachepilot system rollback
```

Interactive process:
1. Shows recent commits
2. Select commit hash to rollback to
3. Confirms rollback
4. Creates backup of current state
5. Checks out selected commit

Manual rollback:

```bash
cd /opt/cachepilot
git log --oneline -10  # Find commit hash
sudo git checkout <commit-hash>
sudo systemctl restart cachepilot-api
```

### Switch Branches

Switch between stable and beta:

```bash
cd /opt/cachepilot
sudo git fetch origin
sudo git checkout develop  # Switch to beta
sudo git checkout main     # Switch to stable
sudo cachepilot system update
```

## Git Hooks

CachePilot uses Git hooks for automation:

### Post-Merge Hook

Automatically runs after `git pull`:
- Updates Python dependencies if `requirements.txt` changed
- Restarts API service if running
- Notifies about frontend dependency changes

Hook location: `/opt/cachepilot/.git/hooks/post-merge`

## Branch Strategy

### Main Branch (Stable)

- Production-ready releases
- Thoroughly tested
- Tagged versions (v2.1.0, v2.2.0, etc.)
- Recommended for production systems

### Develop Branch (Beta)

- Latest features and improvements
- Beta testing phase
- May have bugs or breaking changes
- For testing and early adopters

### Tags

Releases are tagged for easy reference:

```bash
# List all releases
git tag -l

# Install specific version
cd /opt/cachepilot
sudo git checkout v2.1.0
sudo systemctl restart cachepilot-api
```

## Troubleshooting

### Local Changes Conflict

If you have local modifications that conflict with updates:

```bash
cd /opt/cachepilot

# View local changes
git status

# Save local changes
git stash

# Update
git pull origin main

# Reapply local changes (if needed)
git stash pop
```

### Reset to Clean State

If Git state is corrupted:

```bash
cd /opt/cachepilot

# WARNING: This removes all local changes
sudo git reset --hard origin/main
sudo cachepilot system update
```

### Check Git Status

```bash
cd /opt/cachepilot
git status
git log --oneline -5
git remote -v
```

## Configuration Files

**Important**: Configuration files in `/etc/cachepilot/` are **NOT** managed by Git.

- `/etc/cachepilot/system.yaml` - System configuration
- `/etc/cachepilot/api.yaml` - API configuration  
- `/etc/cachepilot/frontend.yaml` - Frontend configuration

These files are preserved during updates and rollbacks.

## Data Preservation

The following directories are **NOT** in Git and are preserved:

- `/var/cachepilot/tenants/` - Tenant Redis data
- `/var/cachepilot/ca/` - Certificate Authority
- `/var/cachepilot/backups/` - Backup files
- `/var/log/cachepilot/` - Log files
- `/etc/cachepilot/` - Configuration files

## Best Practices

### 1. Regular Updates

Check for updates weekly:

```bash
cachepilot system check-updates
```

### 2. Test Before Production

Test updates on a development system first:

```bash
# On dev system
sudo git checkout develop
sudo cachepilot system update
# Test functionality
```

### 3. Backup Before Major Updates

Before major version updates:

```bash
# Backup tenants
cachepilot backup-enable-all

# Note current commit
git rev-parse HEAD > /root/cachepilot-version-backup.txt
```

### 4. Monitor After Updates

After updating, verify:

```bash
# Check service status
systemctl status cachepilot-api

# Check logs
cachepilot api logs 50

# Check tenants
cachepilot list
cachepilot health
```

### 5. Document Custom Changes

If you make local modifications:

```bash
cd /opt/cachepilot
git stash save "Custom change: description"
```

## Automated Update Checks

### Cron Job (Optional)

Create `/etc/cron.daily/cachepilot-update-check`:

```bash
#!/bin/bash
cd /opt/cachepilot
if bash install/scripts/update-check.sh check | grep -q "Update available"; then
    echo "CachePilot update available" | mail -s "CachePilot Update" admin@example.com
fi
```

Make executable:

```bash
sudo chmod +x /etc/cron.daily/cachepilot-update-check
```

## API Access

The REST API provides update information:

```bash
# Check for updates via API
curl http://localhost:8000/api/v1/system/updates

# Response:
{
  "available": true,
  "current_version": "abc1234",
  "latest_version": "def5678",
  "commits_behind": 5
}
```

## Migration from Legacy Installation

If you installed before v2.1.0:

1. **Backup current installation**:
   ```bash
   sudo cp -r /opt/cachepilot /opt/cachepilot.backup
   ```

2. **Convert to Git-based**:
   ```bash
   sudo bash /opt/cachepilot/install/scripts/git-setup.sh convert
   ```

3. **Verify**:
   ```bash
   cachepilot system info
   cachepilot list
   ```

4. **Remove backup** (after verification):
   ```bash
   sudo rm -rf /opt/cachepilot.backup
   ```

## FAQ

**Q: Will updates overwrite my configuration?**  
A: No, configuration in `/etc/cachepilot/` is separate from Git.

**Q: Can I rollback after an update?**  
A: Yes, use `cachepilot system rollback` or `git checkout <commit>`.

**Q: What if I have local modifications?**  
A: Git stash them before updating, then reapply if needed.

**Q: How do I check my current version?**  
A: Run `cachepilot version` or `cachepilot system info`.

**Q: Can I use a specific version?**  
A: Yes, checkout the tag: `git checkout v2.1.0`

**Q: What's the difference between main and develop?**  
A: main = stable releases, develop = beta/testing versions.

## Support

For issues related to Git-based updates:

1. Check Git status: `git status`
2. View recent changes: `git log --oneline -10`
3. Check system info: `cachepilot system info`
4. Review documentation: `/opt/cachepilot/docs/`
5. Open issue: https://github.com/MSRV-Digital/CachePilot/issues

## See Also

- [Installation Guide](DEPLOYMENT.md)
- [Configuration Guide](CONFIGURATION.md)
- [API Documentation](API.md)
- [GitHub Repository](https://github.com/MSRV-Digital/CachePilot)
