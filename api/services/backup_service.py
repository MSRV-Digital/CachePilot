"""
CachePilot - Backup Service

Business logic for backup creation, restoration, verification, and management.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from typing import Dict, Any, List
from api.utils.executor import executor
from api.config import settings
from pathlib import Path
import json

class BackupService:
    def __init__(self):
        """Initialize backup service with configuration"""
        self.settings = settings
    
    def create_backup(self, tenant: str) -> Dict[str, Any]:
        """Create backup by calling bash function directly"""
        import subprocess
        from datetime import datetime
        
        bash_cmd = f'''
        source /opt/cachepilot/cli/lib/common.sh 2>/dev/null
        source /opt/cachepilot/cli/lib/backup.sh 2>/dev/null
        backup_init
        backup_create "{tenant}" "manual"
        '''
        
        try:
            result = subprocess.run(
                ['bash', '-c', bash_cmd],
                capture_output=True,
                text=True,
                timeout=120,
                check=False
            )
            
            if result.returncode == 0:
                return {
                    "success": True,
                    "message": f"Backup created for tenant {tenant}",
                    "data": {"tenant": tenant, "output": result.stdout.strip()}
                }
            else:
                return {
                    "success": False,
                    "message": "Failed to create backup",
                    "error": result.stderr or result.stdout or "Backup creation failed"
                }
        except subprocess.TimeoutExpired:
            return {
                "success": False,
                "message": "Backup creation timed out",
                "error": "Operation exceeded 120 second timeout"
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to create backup",
                "error": str(e)
            }
    
    def list_backups(self, tenant: str) -> Dict[str, Any]:
        """List backups by directly accessing backup directory"""
        import os
        import glob
        
        backup_dir = self.settings.backups_dir
        pattern = os.path.join(backup_dir, f"{tenant}_*.tar.gz")
        
        try:
            backup_files = glob.glob(pattern)
            backups = []
            
            for backup_path in sorted(backup_files, reverse=True):
                filename = os.path.basename(backup_path)
                size_bytes = os.path.getsize(backup_path)
                # Convert bytes to human readable format
                if size_bytes < 1024:
                    size = f"{size_bytes}B"
                elif size_bytes < 1024 * 1024:
                    size = f"{size_bytes / 1024:.1f}KB"
                elif size_bytes < 1024 * 1024 * 1024:
                    size = f"{size_bytes / (1024 * 1024):.1f}MB"
                else:
                    size = f"{size_bytes / (1024 * 1024 * 1024):.1f}GB"
                
                backups.append({
                    "file": filename,
                    "size": size
                })
            
            return {
                "success": True,
                "message": f"Found {len(backups)} backups",
                "data": {"tenant": tenant, "backups": backups}
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to list backups",
                "error": str(e)
            }
    
    def restore_backup(self, tenant: str, backup_file: str) -> Dict[str, Any]:
        """Restore a tenant from backup"""
        import os
        import subprocess
        import shutil
        from datetime import datetime
        
        # Build full path to backup file using configured paths
        backup_dir = self.settings.backups_dir
        tenants_dir = self.settings.tenants_dir
        
        # If backup_file is just a filename, prepend the backup directory
        if not backup_file.startswith('/'):
            backup_file_path = os.path.join(backup_dir, backup_file)
        else:
            backup_file_path = backup_file
        
        # Check if file exists
        if not Path(backup_file_path).exists():
            return {
                "success": False,
                "message": "Backup file not found",
                "error": f"Backup file {backup_file} does not exist"
            }
        
        tenant_dir = Path(tenants_dir) / tenant
        if not tenant_dir.exists():
            return {
                "success": False,
                "message": "Tenant not found",
                "error": f"Tenant {tenant} does not exist"
            }
        
        try:
            # Create backup of current tenant directory
            backup_temp = f"{tenant_dir}.backup_{int(datetime.now().timestamp())}"
            shutil.move(str(tenant_dir), backup_temp)
            
            # Create new tenant directory
            tenant_dir.mkdir(parents=True, exist_ok=True)
            
            # Extract backup
            result = subprocess.run(
                ['tar', '-xzf', backup_file_path, '-C', str(tenant_dir)],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if result.returncode == 0:
                # Success - remove temporary backup
                shutil.rmtree(backup_temp)
                
                # Restart the tenant
                executor.execute("restart", tenant)
                
                return {
                    "success": True,
                    "message": f"Tenant {tenant} restored from backup successfully",
                    "data": {"tenant": tenant, "backup_file": backup_file}
                }
            else:
                # Failed - restore from temporary backup
                shutil.rmtree(str(tenant_dir))
                shutil.move(backup_temp, str(tenant_dir))
                
                return {
                    "success": False,
                    "message": "Failed to restore backup",
                    "error": result.stderr or "Extraction failed"
                }
                
        except Exception as e:
            # Try to restore from temporary backup if it exists
            if Path(backup_temp).exists():
                if tenant_dir.exists():
                    shutil.rmtree(str(tenant_dir))
                shutil.move(backup_temp, str(tenant_dir))
            
            return {
                "success": False,
                "message": "Failed to restore backup",
                "error": str(e)
            }
    
    def verify_backup(self, backup_file: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("verify-backup", backup_file)
        
        if success:
            return {
                "success": True,
                "message": "Backup verification successful",
                "data": {"backup_file": backup_file, "valid": True}
            }
        else:
            return {
                "success": False,
                "message": "Backup verification failed",
                "error": stderr or stdout
            }
    
    def enable_auto_backup(self, tenant: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("backup-enable", tenant)
        
        if success:
            return {
                "success": True,
                "message": f"Automated backups enabled for {tenant}",
                "data": {"tenant": tenant, "auto_backup": True}
            }
        else:
            return {
                "success": False,
                "message": "Failed to enable automated backups",
                "error": stderr or stdout
            }
    
    def disable_auto_backup(self, tenant: str) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("backup-disable", tenant)
        
        if success:
            return {
                "success": True,
                "message": f"Automated backups disabled for {tenant}",
                "data": {"tenant": tenant, "auto_backup": False}
            }
        else:
            return {
                "success": False,
                "message": "Failed to disable automated backups",
                "error": stderr or stdout
            }
    
    def delete_backup(self, tenant: str, backup_file: str) -> Dict[str, Any]:
        """Delete a specific backup file"""
        import os
        
        # Use configured backup directory
        backup_dir = self.settings.backups_dir
        backup_path = Path(backup_dir) / backup_file
        
        # Security check: ensure the backup file belongs to the tenant
        if not backup_file.startswith(f"{tenant}_"):
            return {
                "success": False,
                "message": "Invalid backup file",
                "error": "Backup file does not belong to this tenant"
            }
        
        if not backup_path.exists():
            return {
                "success": False,
                "message": "Backup file not found",
                "error": f"Backup file {backup_file} does not exist"
            }
        
        try:
            os.remove(backup_path)
            return {
                "success": True,
                "message": f"Backup {backup_file} deleted successfully",
                "data": {"tenant": tenant, "backup_file": backup_file}
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to delete backup",
                "error": str(e)
            }
    
    def _parse_backup_list(self, output: str) -> List[Dict[str, str]]:
        import os
        lines = output.strip().split('\n')
        backups = []
        
        for line in lines:
            if line.strip() and '.tar.gz' in line:
                parts = line.split()
                if len(parts) >= 2:
                    # parts[0] is the full path, extract just the filename
                    filename = os.path.basename(parts[0])
                    backups.append({
                        "file": filename,
                        "size": parts[1] if len(parts) > 1 else "unknown"
                    })
        
        return backups

backup_service = BackupService()
