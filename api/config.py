"""
CachePilot - API Configuration Module

Loads and manages configuration from YAML files with environment variable
overrides and FHS-compliant path defaults.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.2-Beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

from pydantic_settings import BaseSettings
from pydantic import Field
from typing import List
import yaml
import os
from pathlib import Path

class Settings(BaseSettings):
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_workers: int = 4
    api_reload: bool = False
    
    api_key_file: str = "/etc/cachepilot/api-keys.json"
    rate_limit_requests: int = 100
    rate_limit_window: int = 60
    cors_origins: List[str] = ["*"]
    
    redis_mgr_cli: str = "/opt/cachepilot/cli/cachepilot"
    base_dir: str = "/opt/cachepilot"
    config_dir: str = "/etc/cachepilot"
    
    tenants_dir: str = "/var/cachepilot/tenants"
    ca_dir: str = "/var/cachepilot/ca"
    backups_dir: str = "/var/cachepilot/backups"
    logs_dir: str = "/var/log/cachepilot"
    
    log_level: str = "INFO"
    access_log: bool = True
    error_log: str = "/var/log/cachepilot/api-error.log"
    access_log_file: str = "/var/log/cachepilot/api-access.log"
    
    environment: str = "production"
    debug: bool = False
    
    class Config:
        env_file = "/etc/cachepilot/.env"
        case_sensitive = False
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self._load_from_yaml()
    
    def _load_from_yaml(self):
        system_yaml_path = Path("/etc/cachepilot/system.yaml")
        if system_yaml_path.exists():
            try:
                with open(system_yaml_path, 'r') as f:
                    system_config = yaml.safe_load(f)
                
                if system_config and 'paths' in system_config:
                    paths = system_config['paths']
                    self.base_dir = paths.get('base_dir', self.base_dir)
                    self.config_dir = paths.get('config_dir', self.config_dir)
                    self.tenants_dir = paths.get('tenants_dir', self.tenants_dir)
                    self.ca_dir = paths.get('ca_dir', self.ca_dir)
                    self.backups_dir = paths.get('backups_dir', self.backups_dir)
                    self.logs_dir = paths.get('logs_dir', self.logs_dir)
                    
                    self.error_log = f"{self.logs_dir}/api-error.log"
                    self.access_log_file = f"{self.logs_dir}/api-access.log"
            
            except Exception as e:
                print(f"Warning: Could not load system configuration from YAML: {e}")
        
        api_yaml_path = Path("/etc/cachepilot/api.yaml")
        
        if not api_yaml_path.exists():
            self._apply_env_overrides()
            return
        
        try:
            with open(api_yaml_path, 'r') as f:
                config = yaml.safe_load(f)
            
            if not config:
                self._apply_env_overrides()
                return
            
            if 'server' in config:
                self.api_host = config['server'].get('host', self.api_host)
                self.api_port = config['server'].get('port', self.api_port)
                self.api_workers = config['server'].get('workers', self.api_workers)
                self.api_reload = config['server'].get('reload', self.api_reload)
            
            if 'security' in config:
                self.api_key_file = config['security'].get('api_key_file', self.api_key_file)
                self.rate_limit_requests = config['security'].get('rate_limit_requests', self.rate_limit_requests)
                self.rate_limit_window = config['security'].get('rate_limit_window', self.rate_limit_window)
                self.cors_origins = config['security'].get('cors_origins', self.cors_origins)
            
            if 'paths' in config:
                self.redis_mgr_cli = config['paths'].get('redis_mgr_cli', self.redis_mgr_cli)
            
            if 'logging' in config:
                self.log_level = config['logging'].get('level', self.log_level)
                self.access_log = config['logging'].get('access_log', self.access_log)
                if 'error_log' in config['logging']:
                    self.error_log = config['logging']['error_log']
                if 'access_log_file' in config['logging']:
                    self.access_log_file = config['logging']['access_log_file']
            
            if 'environment' in config:
                self.environment = config['environment'].get('type', self.environment)
                self.debug = config['environment'].get('debug', self.debug)
            
            self._apply_env_overrides()
        
        except Exception as e:
            print(f"Warning: Could not load API configuration from YAML: {e}")
            self._apply_env_overrides()
    
    def _apply_env_overrides(self):
        if os.getenv('TENANTS_DIR'):
            self.tenants_dir = os.getenv('TENANTS_DIR')
        if os.getenv('CA_DIR'):
            self.ca_dir = os.getenv('CA_DIR')
        if os.getenv('BACKUPS_DIR'):
            self.backups_dir = os.getenv('BACKUPS_DIR')
        if os.getenv('LOGS_DIR'):
            self.logs_dir = os.getenv('LOGS_DIR')
            self.error_log = f"{self.logs_dir}/api-error.log"
            self.access_log_file = f"{self.logs_dir}/api-access.log"
    
    @property
    def redis_mgr_path(self) -> str:
        return self.base_dir

settings = Settings()
