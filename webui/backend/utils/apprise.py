"""
Utility functions for checking Apprise status
"""
import subprocess
import re
from typing import Tuple, Optional
from ..config import settings


def is_apprise_service_enabled() -> bool:
    """Check if apprise-api.service exists and is active/enabled
    
    Returns:
        True if service exists and is active or enabled, False otherwise
    """
    try:
        # Check if service exists (doesn't matter if enabled, static, or indirect)
        result = subprocess.run(
            ['systemctl', 'is-enabled', 'apprise-api.service'],
            capture_output=True,
            text=True,
            timeout=5,
            check=False
        )
        # Exit code 0 = enabled/static/indirect, 1 = disabled, 2+ = doesn't exist
        if result.returncode == 0:
            # Service exists - check if it's active
            active_result = subprocess.run(
                ['systemctl', 'is-active', 'apprise-api.service'],
                capture_output=True,
                text=True,
                timeout=5,
                check=False
            )
            if active_result.returncode == 0:
                active_state = active_result.stdout.strip()
                # Service is active if state is 'active' or 'activating'
                return active_state in ('active', 'activating')
        return False
    except (subprocess.TimeoutExpired, subprocess.SubprocessError):
        return False


def is_apprise_enabled_in_config() -> bool:
    """Check if Apprise is enabled in router-config.nix
    
    Returns:
        True if apprise.enable = true, False otherwise
    """
    try:
        with open(settings.router_config_file, 'r') as f:
            content = f.read()
        
        # Look for apprise configuration block
        # Check for enable = true (uncommented)
        apprise_pattern = r'apprise\s*=\s*\{[^}]*enable\s*=\s*true'
        if re.search(apprise_pattern, content, re.DOTALL | re.IGNORECASE):
            return True
        
        return False
    except (FileNotFoundError, IOError, PermissionError):
        return False


def is_apprise_enabled() -> bool:
    """Check if Apprise is enabled using multiple detection methods
    
    Returns:
        True if Apprise is enabled, False otherwise
    """
    # Primary: Check if service is enabled
    if is_apprise_service_enabled():
        return True
    
    # Secondary: Check config file
    if is_apprise_enabled_in_config():
        return True
    
    return False

