"""
Utility functions for Apprise notifications
"""
import re
import os
from typing import Optional, List, Tuple
from apprise import Apprise
from ..config import settings


# Default config file path (matches modules/apprise.nix default)
DEFAULT_APPRISE_CONFIG = "/var/lib/apprise/config/apprise"


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
    """Check if Apprise is enabled
    
    Returns:
        True if Apprise is enabled, False otherwise
    """
    if not is_apprise_enabled_in_config():
        return False
    
    # Check if config file exists
    config_path = os.getenv('APPRISE_CONFIG_FILE', DEFAULT_APPRISE_CONFIG)
    return os.path.exists(config_path)


def load_apprise_config(config_path: Optional[str] = None) -> Apprise:
    """Load Apprise configuration from file
    
    Args:
        config_path: Path to apprise config file (defaults to /var/lib/apprise/config/apprise)
        
    Returns:
        Apprise object configured with services from config file
    """
    if config_path is None:
        config_path = os.getenv('APPRISE_CONFIG_FILE', DEFAULT_APPRISE_CONFIG)
    
    # Create Apprise object
    apobj = Apprise()
    
    # Load configuration from file
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            # Read all lines, filter out empty lines and comments
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Add each service URL to Apprise
                    apobj.add(line)
    
    return apobj


def send_notification(
    body: str,
    title: Optional[str] = None,
    notification_type: Optional[str] = None,
    config_path: Optional[str] = None
) -> Tuple[bool, Optional[str]]:
    """Send notification using Apprise
    
    Args:
        body: Message body (required)
        title: Optional message title
        notification_type: Optional notification type (info, success, warning, failure)
        config_path: Optional path to apprise config file
        
    Returns:
        Tuple of (success: bool, error_message: Optional[str])
    """
    try:
        # Load Apprise configuration
        apobj = load_apprise_config(config_path)
        
        # Check if any services are configured
        if not apobj:
            return (False, "No notification services configured")
        
        # Map notification type
        apprise_type = None
        if notification_type:
            type_map = {
                'info': 'info',
                'success': 'success',
                'warning': 'warning',
                'failure': 'failure',
            }
            apprise_type = type_map.get(notification_type.lower())
        
        # Send notification
        result = apobj.notify(
            body=body,
            title=title,
            notify_type=apprise_type
        )
        
        if result:
            return (True, None)
        else:
            return (False, "Failed to send notification to all services")
            
    except Exception as e:
        return (False, str(e))


def get_configured_services(config_path: Optional[str] = None) -> List[str]:
    """Get list of configured service URLs
    
    Args:
        config_path: Optional path to apprise config file
        
    Returns:
        List of service URLs (with sensitive parts masked)
    """
    if config_path is None:
        config_path = os.getenv('APPRISE_CONFIG_FILE', DEFAULT_APPRISE_CONFIG)
    
    services = []
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Mask passwords/tokens in URLs for display
                    # Format: scheme://user:***@host/path
                    masked = re.sub(r':([^:@/]+)@', r':***@', line)
                    masked = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked)
                    services.append(masked)
    
    return services


def get_raw_service_urls(config_path: Optional[str] = None) -> List[str]:
    """Get list of raw (unmasked) service URLs from config file
    
    Args:
        config_path: Optional path to apprise config file
        
    Returns:
        List of raw service URLs
    """
    if config_path is None:
        config_path = os.getenv('APPRISE_CONFIG_FILE', DEFAULT_APPRISE_CONFIG)
    
    services = []
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    services.append(line)
    
    return services


def test_service(
    service_url: str,
    body: str = "Test notification from NixOS Router WebUI",
    title: str = "Test Notification",
    notification_type: Optional[str] = None
) -> Tuple[bool, Optional[str], Optional[str]]:
    """Test a single notification service
    
    Args:
        service_url: The service URL to test (can be masked or raw)
        body: Message body
        title: Message title
        notification_type: Optional notification type
        
    Returns:
        Tuple of (success: bool, error_message: Optional[str], details: Optional[str])
    """
    try:
        # Get raw service URLs to find the matching one
        raw_urls = get_raw_service_urls()
        masked_urls = get_configured_services()
        
        # Find the matching raw URL
        raw_url = None
        for i, masked_url in enumerate(masked_urls):
            if masked_url == service_url and i < len(raw_urls):
                raw_url = raw_urls[i]
                break
        
        # If not found, try using the service_url directly (might be raw)
        if raw_url is None:
            raw_url = service_url
        
        # Create Apprise object with just this service
        apobj = Apprise()
        apobj.add(raw_url)
        
        if not apobj:
            return (False, "Invalid service URL", None)
        
        # Map notification type
        apprise_type = None
        if notification_type:
            type_map = {
                'info': 'info',
                'success': 'success',
                'warning': 'warning',
                'failure': 'failure',
            }
            apprise_type = type_map.get(notification_type.lower())
        
        # Send notification
        result = apobj.notify(
            body=body,
            title=title,
            notify_type=apprise_type
        )
        
        if result:
            return (True, None, f"Notification sent successfully to {get_service_name_from_url(raw_url)}")
        else:
            # Apprise returns False but doesn't provide detailed error messages
            # We can check the Apprise object's response for more details
            # Get the last error if available
            error_details = []
            for service in apobj:
                # Try to get error information from the service
                # Apprise doesn't expose this easily, so we'll provide a generic message
                pass
            
            return (False, "Failed to send notification", "The service may be misconfigured, unreachable, or the credentials may be invalid")
            
    except Exception as e:
        error_msg = str(e)
        error_type = type(e).__name__
        # Provide more context for common errors
        if "Connection" in error_type or "timeout" in error_msg.lower():
            details = f"Connection error: {error_msg}"
        elif "Authentication" in error_type or "auth" in error_msg.lower() or "unauthorized" in error_msg.lower():
            details = f"Authentication error: {error_msg}"
        elif "Invalid" in error_type or "invalid" in error_msg.lower():
            details = f"Invalid configuration: {error_msg}"
        else:
            details = f"{error_type}: {error_msg}"
        
        return (False, error_msg, details)


def get_service_name_from_url(url: str) -> str:
    """Extract service name from URL
    
    Args:
        url: Service URL
        
    Returns:
        Service name
    """
    match = re.match(r'^([^:]+):', url)
    if match:
        return match.group(1).capitalize()
    return "Unknown Service"

