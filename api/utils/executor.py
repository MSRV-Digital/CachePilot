"""
CachePilot - CLI Command Executor

Secure command execution wrapper for calling CachePilot CLI from API with
validation, sanitization, and comprehensive logging.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.1.0-beta
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
"""

import subprocess
import json
import logging
from typing import Tuple, Optional, Dict, Any, List
from api.config import settings
from api.utils.input_sanitization import sanitize_command_argument, ValidationError

logger = logging.getLogger(__name__)

class CommandExecutor:
    ALLOWED_COMMANDS = {
        "tenant", "create", "delete", "list", "status",
        "backup", "restore", "list-backups", "verify-backup",
        "backup-enable", "backup-disable", "backup-status", "backup-enable-all",
        "cert", "renew",
        "health", "check", "stats",
        "monitoring", "metrics",
        "config", "get", "set",
        "redis", "cli", "info", "restart", "start", "stop",
        "new", "rm", "set-memory", "rotate", "handover"
    }
    
    def __init__(self, cli_path: str = None):
        self.cli_path = cli_path or settings.redis_mgr_cli
        self._validate_cli_path()
    
    def _validate_cli_path(self) -> None:
        import os
        if not os.path.exists(self.cli_path):
            logger.error(f"CLI path does not exist: {self.cli_path}")
            raise ValueError(f"CLI executable not found: {self.cli_path}")
        
        if not os.access(self.cli_path, os.X_OK):
            logger.error(f"CLI path is not executable: {self.cli_path}")
            raise ValueError(f"CLI executable not accessible: {self.cli_path}")
    
    def _validate_command(self, command: str) -> None:
        if not command or not isinstance(command, str):
            raise ValidationError("Command must be a non-empty string")
        
        if command not in self.ALLOWED_COMMANDS:
            logger.warning(f"Attempted to execute non-whitelisted command: {command}")
            raise ValidationError(f"Command '{command}' is not allowed")
    
    def _sanitize_arguments(self, args: tuple) -> List[str]:
        sanitized = []
        for arg in args:
            if not isinstance(arg, str):
                arg = str(arg)
            try:
                sanitized_arg = sanitize_command_argument(arg)
                sanitized.append(sanitized_arg)
            except ValidationError as e:
                logger.warning(f"Argument validation failed: {e}")
                raise
        return sanitized
    
    def _log_execution(self, command: str, args: tuple, success: bool, stderr: str = "") -> None:
        log_entry = {
            "command": command,
            "args": [str(arg) for arg in args],
            "success": success,
            "cli_path": self.cli_path
        }
        
        if success:
            logger.info(f"Command executed successfully: {log_entry}")
        else:
            logger.error(f"Command execution failed: {log_entry}, stderr: {stderr}")
    
    def execute(self, command: str, *args) -> Tuple[bool, str, str]:
        try:
            self._validate_command(command)
            sanitized_args = self._sanitize_arguments(args)
        except ValidationError as e:
            error_msg = str(e)
            logger.warning(f"Command validation failed: {error_msg}")
            return False, "", error_msg
        
        cmd = [self.cli_path, command] + sanitized_args
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=settings.redis_mgr_path,
                check=False
            )
            
            success = result.returncode == 0
            self._log_execution(command, args, success, result.stderr)
            
            return (
                success,
                result.stdout,
                result.stderr
            )
        except subprocess.TimeoutExpired:
            error_msg = "Command timeout"
            self._log_execution(command, args, False, error_msg)
            return False, "", error_msg
        except Exception as e:
            error_msg = "Command execution error"
            logger.error(f"Unexpected error executing command: {e}")
            self._log_execution(command, args, False, error_msg)
            return False, "", error_msg
    
    def execute_json(self, command: str, *args) -> Tuple[bool, Optional[Dict[Any, Any]], str]:
        success, stdout, stderr = self.execute(command, "--json", *args)
        
        if not success:
            return False, None, stderr
        
        try:
            data = json.loads(stdout)
            return True, data, ""
        except json.JSONDecodeError as e:
            return False, None, f"JSON parse error: {str(e)}"
    
    def execute_with_timeout(self, command: str, timeout: int, *args) -> Tuple[bool, str, str]:
        try:
            self._validate_command(command)
            sanitized_args = self._sanitize_arguments(args)
        except ValidationError as e:
            error_msg = str(e)
            logger.warning(f"Command validation failed: {error_msg}")
            return False, "", error_msg
        
        cmd = [self.cli_path, command] + sanitized_args
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=settings.redis_mgr_path,
                check=False
            )
            
            success = result.returncode == 0
            self._log_execution(command, args, success, result.stderr)
            
            return (
                success,
                result.stdout,
                result.stderr
            )
        except subprocess.TimeoutExpired:
            error_msg = f"Command timeout after {timeout}s"
            self._log_execution(command, args, False, error_msg)
            return False, "", error_msg
        except Exception as e:
            error_msg = "Command execution error"
            logger.error(f"Unexpected error executing command with timeout: {e}")
            self._log_execution(command, args, False, error_msg)
            return False, "", error_msg

executor = CommandExecutor()
