"""
CAKE detection and WAN interface determination utilities
"""
import subprocess
import re
import os
from typing import Optional, Tuple
from ..config import settings


def _get_tc_binary() -> str:
    """Get tc binary path from environment variable or default to 'tc'
    
    Returns:
        Path to tc binary
    """
    return os.environ.get("TC_BIN", "tc")


def get_wan_interface() -> Optional[str]:
    """Determine WAN interface from router-config.nix
    
    Returns:
        WAN interface name (e.g., 'ppp0' for PPPoE or 'eno1' for DHCP)
        None if config cannot be read
    """
    try:
        with open(settings.router_config_file, 'r') as f:
            content = f.read()
        
        # Check for PPPoE configuration
        if 'type = "pppoe"' in content or "type = 'pppoe'" in content:
            # PPPoE uses ppp0 interface
            return 'ppp0'
        
        # Extract interface from DHCP configuration
        match = re.search(r'interface\s*=\s*["\']([^"\']+)["\']', content)
        if match:
            return match.group(1)
        
        # Default fallback
        return None
    except (FileNotFoundError, IOError, PermissionError):
        return None


def is_cake_service_enabled() -> bool:
    """Check if cake-setup.service exists and is active/enabled
    
    Returns:
        True if service exists and is active or enabled, False otherwise
    """
    try:
        # Check if service exists (doesn't matter if enabled, static, or indirect)
        result = subprocess.run(
            ['systemctl', 'is-enabled', 'cake-setup.service'],
            capture_output=True,
            text=True,
            timeout=5,
            check=False
        )
        # Exit code 0 = enabled/static/indirect, 1 = disabled, 2+ = doesn't exist
        if result.returncode == 0:
            # Service exists - check if it's active
            active_result = subprocess.run(
                ['systemctl', 'is-active', 'cake-setup.service'],
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


def is_cake_qdisc_configured(interface: Optional[str] = None) -> bool:
    """Check if CAKE qdisc exists on the interface
    
    Args:
        interface: Interface name (defaults to WAN interface)
        
    Returns:
        True if CAKE qdisc is configured, False otherwise
    """
    if interface is None:
        interface = get_wan_interface()
    
    if interface is None:
        return False
    
    try:
        # Get tc binary path (from environment variable if set)
        tc_bin = _get_tc_binary()
        
        # Check if CAKE qdisc exists on root
        result = subprocess.run(
            [tc_bin, 'qdisc', 'show', 'dev', interface, 'root'],
            capture_output=True,
            text=True,
            timeout=5,
            check=False
        )
        
        if result.returncode == 0:
            return 'cake' in result.stdout.lower()
        return False
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
        return False


def is_cake_enabled_in_config() -> bool:
    """Check if CAKE is enabled in router-config.nix
    
    Returns:
        True if wan.cake.enable = true, False otherwise
    """
    try:
        with open(settings.router_config_file, 'r') as f:
            content = f.read()
        
        # Look for cake configuration block
        # Check for enable = true (uncommented)
        cake_pattern = r'cake\s*=\s*\{[^}]*enable\s*=\s*true'
        if re.search(cake_pattern, content, re.DOTALL | re.IGNORECASE):
            return True
        
        return False
    except (FileNotFoundError, IOError, PermissionError):
        return False


def is_cake_enabled() -> Tuple[bool, Optional[str]]:
    """Check if CAKE is enabled using multiple detection methods
    
    Returns:
        Tuple of (is_enabled, interface_name)
        - is_enabled: True if CAKE is enabled
        - interface_name: WAN interface name if found
    """
    interface = get_wan_interface()
    
    # Primary: Check if service is enabled
    if is_cake_service_enabled():
        return (True, interface)
    
    # Secondary: Check if qdisc exists
    if interface and is_cake_qdisc_configured(interface):
        return (True, interface)
    
    # Tertiary: Check config file
    if is_cake_enabled_in_config():
        return (True, interface)
    
    return (False, interface)

