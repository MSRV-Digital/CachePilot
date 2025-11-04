"""
CachePilot - Monitoring Service

Business logic for health checks, metrics collection, alerts, and statistics.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from typing import Dict, Any, List
from api.utils.executor import executor
from api.config import settings
from pathlib import Path
import json
from datetime import datetime

class MonitoringService:
    def __init__(self):
        """Initialize monitoring service with configuration"""
        self.settings = settings
    
    def get_health_status(self) -> Dict[str, Any]:
        success, stdout, stderr = executor.execute("health", "--json")
        
        if success:
            try:
                health_data = json.loads(stdout)
                return {
                    "success": True,
                    "message": "Health check completed",
                    "data": health_data
                }
            except json.JSONDecodeError as e:
                return {
                    "success": False,
                    "message": "Failed to parse health data",
                    "error": f"JSON decode error: {str(e)}"
                }
        else:
            return {
                "success": False,
                "message": "Health check failed",
                "error": stderr or stdout
            }
    
    def get_global_stats(self) -> Dict[str, Any]:
        # Call the bash function directly to avoid subprocess issues
        import subprocess
        
        bash_cmd = '''
        source /opt/cachepilot/cli/lib/common.sh 2>/dev/null
        source /opt/cachepilot/cli/lib/docker.sh 2>/dev/null  
        source /opt/cachepilot/cli/lib/monitoring.sh 2>/dev/null
        show_global_stats_json
        '''
        
        try:
            result = subprocess.run(
                ['bash', '-c', bash_cmd],
                capture_output=True,
                text=True,
                timeout=30,
                check=False
            )
            
            if result.returncode == 0 and result.stdout:
                stats_data = json.loads(result.stdout)
                # Transform the data to match frontend expectations (all values as strings)
                formatted_stats = {
                    "total_tenants": str(stats_data.get("total_tenants", 0)),
                    "running": str(stats_data.get("running_tenants", 0)),
                    "stopped": str(stats_data.get("stopped_tenants", 0)),
                    "total_memory_used": str(stats_data.get("total_memory_used", 0)),
                    "total_clients": str(stats_data.get("total_clients", 0)),
                    "total_keys": str(stats_data.get("total_keys", 0))
                }
                return {
                    "success": True,
                    "message": "Statistics retrieved",
                    "data": formatted_stats
                }
            else:
                return {
                    "success": False,
                    "message": "Failed to retrieve statistics",
                    "error": result.stderr or "Command execution failed"
                }
        except json.JSONDecodeError as e:
            return {
                "success": False,
                "message": "Failed to parse statistics data",
                "error": f"JSON decode error: {str(e)}"
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to retrieve statistics",
                "error": str(e)
            }
    
    def get_alerts(self, severity: str = None, tenant: str = None, resolved: bool = None) -> Dict[str, Any]:
        # Use configured logs directory
        alert_file = Path(self.settings.logs_dir) / "alerts" / "history.json"
        
        if not alert_file.exists():
            return {
                "success": True,
                "message": "No alerts found",
                "data": {"alerts": []}
            }
        
        try:
            with open(alert_file, 'r') as f:
                all_alerts = json.load(f)
            
            filtered = all_alerts
            
            if severity:
                filtered = [a for a in filtered if a.get('severity') == severity]
            
            if tenant:
                filtered = [a for a in filtered if a.get('tenant') == tenant]
            
            if resolved is not None:
                filtered = [a for a in filtered if a.get('resolved') == resolved]
            
            return {
                "success": True,
                "message": f"Found {len(filtered)} alerts",
                "data": {"alerts": filtered}
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to retrieve alerts",
                "error": str(e)
            }
    
    def resolve_alert(self, alert_id: str) -> Dict[str, Any]:
        # Use configured logs directory
        alert_file = Path(self.settings.logs_dir) / "alerts" / "history.json"
        
        if not alert_file.exists():
            return {
                "success": False,
                "message": "Alert not found",
                "error": "No alerts file exists"
            }
        
        try:
            with open(alert_file, 'r') as f:
                alerts = json.load(f)
            
            found = False
            for alert in alerts:
                if alert.get('id') == alert_id:
                    alert['resolved'] = True
                    alert['resolved_at'] = datetime.utcnow().isoformat() + 'Z'
                    found = True
                    break
            
            if found:
                with open(alert_file, 'w') as f:
                    json.dump(alerts, f, indent=2)
                
                return {
                    "success": True,
                    "message": f"Alert {alert_id} resolved",
                    "data": {"alert_id": alert_id}
                }
            else:
                return {
                    "success": False,
                    "message": "Alert not found",
                    "error": f"No alert with ID {alert_id}"
                }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to resolve alert",
                "error": str(e)
            }
    
    def get_tenant_metrics(self, tenant: str, hours: int = 24) -> Dict[str, Any]:
        # Use configured logs directory
        metrics_file = Path(self.settings.logs_dir) / "metrics" / f"{tenant}.jsonl"
        
        if not metrics_file.exists():
            return {
                "success": True,
                "message": "No metrics found for tenant",
                "data": {"metrics": []}
            }
        
        try:
            metrics = []
            with open(metrics_file, 'r') as f:
                for line in f:
                    if line.strip():
                        metrics.append(json.loads(line))
            
            cutoff_time = datetime.utcnow().timestamp() - (hours * 3600)
            filtered = [
                m for m in metrics 
                if datetime.fromisoformat(m['timestamp'].replace('Z', '+00:00')).timestamp() > cutoff_time
            ]
            
            return {
                "success": True,
                "message": f"Retrieved {len(filtered)} metrics",
                "data": {"metrics": filtered}
            }
        except Exception as e:
            return {
                "success": False,
                "message": "Failed to retrieve metrics",
                "error": str(e)
            }
    
    def _parse_health_text(self, output: str) -> Dict[str, Any]:
        lines = output.strip().split('\n')
        health = {
            "status": "unknown",
            "services": {},
            "issues": []
        }
        
        for line in lines:
            if "System Health:" in line:
                health["status"] = line.split(":")[-1].strip().lower()
            elif "✓" in line or "✗" in line or "⚠" in line:
                parts = line.split(":", 1)
                if len(parts) == 2:
                    service = parts[0].strip().replace("✓", "").replace("✗", "").replace("⚠", "").strip()
                    status = "healthy" if "✓" in line else ("degraded" if "⚠" in line else "unhealthy")
                    health["services"][service] = status
                    if status != "healthy":
                        health["issues"].append(f"{service}: {parts[1].strip()}")
        
        return {
            "success": True,
            "message": "Health check completed",
            "data": health
        }
    
    def _parse_stats(self, output: str) -> Dict[str, Any]:
        lines = output.strip().split('\n')
        stats = {}
        
        for line in lines:
            if ':' in line:
                key, value = line.split(':', 1)
                stats[key.strip().lower().replace(' ', '_')] = value.strip()
        
        return stats

monitoring_service = MonitoringService()
