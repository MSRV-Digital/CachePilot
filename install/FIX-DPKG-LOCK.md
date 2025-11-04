# Fix for dpkg Lock Error During Installation

## Problem

During the CachePilot installation, when the script attempts to install packages (nginx, certbot, etc.), it may encounter this error:

```
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 7141 (unattended-upgr)
N: Be aware that removing the lock file is not a solution and may break your system.
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process using it?
```

This occurs because Ubuntu/Debian's automatic update service (`unattended-upgrades`) is running in the background and has locked the package manager.

## Solution Implemented

A `wait_for_apt_lock()` function has been added to both installation scripts that:

1. **Checks for actual lock files** - Only monitors lock files (not running processes):
   - `/var/lib/dpkg/lock-frontend`
   - `/var/lib/dpkg/lock`
   - `/var/cache/apt/archives/lock`
   
   This is more accurate - `unattended-upgrades` may run in the background without holding locks

2. **Waits patiently** - The script will wait up to 5 minutes for the lock to be released, checking every 5 seconds

3. **Provides user feedback** - Shows:
   - Initial notification that it's waiting
   - Progress updates every 30 seconds
   - Confirmation when the lock is released

4. **Handles timeouts gracefully** - If the lock persists beyond 5 minutes, it provides clear instructions for manual resolution

## Modified Files

### 1. `install/scripts/setup-nginx.sh`
- Added `wait_for_apt_lock()` function before nginx installation
- Added wait mechanism before certbot installation
- Graceful degradation: If certbot installation fails due to lock timeout, continues with HTTP-only configuration

### 2. `install/scripts/install-deps.sh`
- Added `wait_for_apt_lock()` function at the start
- Added wait mechanism before `apt-get update`
- Added wait mechanism before installing required packages
- Added wait mechanism before installing optional packages (Node.js/npm)

## How It Works

When the script encounters a locked package manager:

```bash
# User sees:
⏳ Waiting for other package management processes to complete...
  (This may be automatic system updates running in the background)

# Every 30 seconds:
  Still waiting... (30s elapsed)
  Still waiting... (60s elapsed)
  ...

# When lock is released:
✓ Package management lock released (waited 45s)
```

If the timeout is reached (5 minutes):

```bash
✗ Timeout waiting for package management lock (waited 300s)

Another process is using the package manager. Please try one of these:
  1. Wait for automatic updates to complete and run the script again
  2. Kill the blocking process manually:
     sudo killall apt apt-get unattended-upgr
     sudo rm /var/lib/dpkg/lock-frontend
     sudo rm /var/lib/dpkg/lock
     sudo dpkg --configure -a
```

## Benefits

1. **Automatic resolution** - Waits only when locks are actually held, resolves automatically
2. **User-friendly** - Clear feedback on what's happening and how long it's been waiting
3. **Precise** - Only checks actual lock files, not background processes (avoids false positives)
4. **Safe** - Doesn't force-remove locks or kill processes automatically
5. **Graceful degradation** - Script continues where possible even if package installation fails
6. **No unnecessary waits** - `unattended-upgrades` running in background won't block installation

## Testing

Syntax validation confirmed both scripts are syntactically correct:
```bash
bash -n install/scripts/setup-nginx.sh
bash -n install/scripts/install-deps.sh
# Both passed
```

## Manual Testing Recommendation

To verify the fix works in your environment:

1. **Simulate the lock** (optional):
   ```bash
   # In one terminal, hold the lock:
   sudo apt-get update &
   
   # In another terminal, run installation:
   sudo bash install/install.sh
   ```

2. **Normal installation**:
   ```bash
   sudo bash install/install.sh
   ```
   If unattended-upgrades is running, you should see the wait message and the script will proceed automatically once it completes.

## Version

- **Fix implemented**: 2025-01-04
- **CachePilot version**: 2.1.0-beta
- **Affected scripts**: install-deps.sh, setup-nginx.sh
