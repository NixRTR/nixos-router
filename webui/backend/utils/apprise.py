"""
Utility functions for Apprise notifications
"""
import re
import os
import logging
from urllib.parse import quote, urlparse, urlunparse, parse_qs, urlencode
from typing import Optional, List, Tuple
from apprise import Apprise
from ..config import settings

logger = logging.getLogger(__name__)


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


def url_encode_password_in_url(url: str) -> str:
    """URL-encode passwords and tokens in Apprise service URLs
    
    This function properly encodes special characters in passwords/tokens
    that appear in URLs (e.g., mailto://user:pass@host, discord://id/token)
    
    Args:
        url: Service URL that may contain unencoded passwords/tokens
        
    Returns:
        URL with properly encoded passwords/tokens
    """
    try:
        # Parse the URL
        parsed = urlparse(url)
        
        # If there's user info (user:pass), encode the password part
        if parsed.username or '@' in parsed.netloc:
            # Split netloc into userinfo and host:port
            if '@' in parsed.netloc:
                userinfo, hostport = parsed.netloc.rsplit('@', 1)
                if ':' in userinfo:
                    username, password = userinfo.split(':', 1)
                    # URL-encode the password
                    encoded_password = quote(password, safe='')
                    # Reconstruct netloc
                    encoded_netloc = f"{username}:{encoded_password}@{hostport}"
                else:
                    encoded_netloc = parsed.netloc
            else:
                encoded_netloc = parsed.netloc
        else:
            encoded_netloc = parsed.netloc
        
        # For paths that might contain tokens (like discord://id/token)
        # We need to be careful - Apprise URLs can have tokens in the path
        # For now, we'll encode the entire path if it looks like it contains tokens
        encoded_path = parsed.path
        if encoded_path and '/' in encoded_path:
            # Split path into segments
            path_parts = encoded_path.split('/')
            # URL-encode each segment (tokens might be in path segments)
            encoded_path = '/'.join(quote(part, safe='') for part in path_parts if part)
            if not encoded_path.startswith('/'):
                encoded_path = '/' + encoded_path
        
        # Reconstruct URL
        encoded_url = urlunparse((
            parsed.scheme,
            encoded_netloc,
            encoded_path,
            parsed.params,
            parsed.query,
            parsed.fragment
        ))
        
        return encoded_url
    except Exception as e:
        logger.warning(f"Failed to URL-encode password in URL, using original: {str(e)}")
        return url


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
        logger.debug(f"Loading Apprise config from: {config_path}")
        with open(config_path, 'r') as f:
            lines = f.readlines()
            logger.debug(f"Config file has {len(lines)} lines")
            # Read all lines, filter out empty lines and comments
            for line_num, line in enumerate(lines, 1):
                original_line = line
                line = line.strip()
                if line and not line.startswith('#'):
                    # Check if line contains sops placeholder (not replaced)
                    if '${' in line or '${' in line:
                        logger.warning(f"Line {line_num} contains unprocessed placeholder: {line[:100]}...")
                    
                    # URL-encode passwords/tokens in the URL before adding to Apprise
                    encoded_url = url_encode_password_in_url(line)
                    logger.debug(f"Line {line_num} - Original: {line[:50]}... (masked)")
                    logger.debug(f"Line {line_num} - Encoded: {encoded_url[:50]}... (masked)")
                    
                    try:
                        # Add each service URL to Apprise
                        apobj.add(encoded_url)
                        logger.debug(f"Successfully added service from line {line_num}")
                    except Exception as add_error:
                        logger.error(f"Failed to add service from line {line_num}: {type(add_error).__name__}: {str(add_error)}")
                        logger.error(f"Problematic URL: {line[:100]}... (masked)")
    else:
        logger.warning(f"Apprise config file does not exist: {config_path}")
    
    logger.debug(f"Apprise object contains {len(apobj)} service(s)")
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
    logger.info(f"Testing service with URL: {service_url[:50]}... (masked)")
    try:
        # Get raw service URLs to find the matching one
        logger.debug("Fetching raw and masked service URLs")
        raw_urls = get_raw_service_urls()
        masked_urls = get_configured_services()
        logger.debug(f"Found {len(raw_urls)} raw URLs and {len(masked_urls)} masked URLs")
        
        # Find the matching raw URL
        raw_url = None
        for i, masked_url in enumerate(masked_urls):
            if masked_url == service_url and i < len(raw_urls):
                raw_url = raw_urls[i]
                logger.debug(f"Matched masked URL at index {i} to raw URL: {raw_url[:50]}... (masked)")
                break
        
        # If not found, try using the service_url directly (might be raw)
        if raw_url is None:
            logger.warning(f"Could not find matching raw URL for masked URL, using service_url directly")
            raw_url = service_url
        
        if not raw_url:
            logger.error("No raw URL found or provided")
            return (False, "No service URL provided", None)
        
        # Create Apprise object with just this service
        logger.debug(f"Creating Apprise object and adding service: {get_service_name_from_url(raw_url)}")
        apobj = Apprise()
        
        # URL-encode passwords/tokens in the URL
        encoded_url = url_encode_password_in_url(raw_url)
        logger.debug(f"URL-encoded service URL: {encoded_url[:50]}... (masked)")
        
        try:
            apobj.add(encoded_url)
            logger.debug(f"Successfully added service to Apprise object")
        except Exception as add_error:
            logger.error(f"Failed to add service URL to Apprise: {type(add_error).__name__}: {str(add_error)}")
            return (False, f"Invalid service URL: {str(add_error)}", f"Failed to parse service URL: {type(add_error).__name__}")
        
        if not apobj:
            logger.error("Apprise object is empty after adding service")
            return (False, "Invalid service URL", "Service URL could not be added to Apprise")
        
        logger.debug(f"Apprise object contains {len(apobj)} service(s)")
        
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
            logger.debug(f"Mapped notification type '{notification_type}' to '{apprise_type}'")
        
        # Send notification
        logger.info(f"Sending test notification to {get_service_name_from_url(raw_url)}")
        try:
            result = apobj.notify(
                body=body,
                title=title,
                notify_type=apprise_type
            )
            logger.debug(f"Notification result: {result}")
        except Exception as notify_error:
            logger.error(f"Exception during notify(): {type(notify_error).__name__}: {str(notify_error)}", exc_info=True)
            error_msg = str(notify_error)
            error_type = type(notify_error).__name__
            if "Connection" in error_type or "timeout" in error_msg.lower():
                details = f"Connection error: {error_msg}"
            elif "Authentication" in error_type or "auth" in error_msg.lower() or "unauthorized" in error_msg.lower():
                details = f"Authentication error: {error_msg}"
            elif "Invalid" in error_type or "invalid" in error_msg.lower():
                details = f"Invalid configuration: {error_msg}"
            else:
                details = f"{error_type}: {error_msg}"
            return (False, error_msg, details)
        
        if result:
            logger.info(f"Successfully sent notification to {get_service_name_from_url(raw_url)}")
            return (True, None, f"Notification sent successfully to {get_service_name_from_url(raw_url)}")
        else:
            logger.warning(f"Notification returned False for {get_service_name_from_url(raw_url)}")
            # Try to get more information about the failure
            # Apprise doesn't expose detailed error messages easily
            return (False, "Failed to send notification", "The service may be misconfigured, unreachable, or the credentials may be invalid")
            
    except Exception as e:
        logger.error(f"Unexpected exception in test_service: {type(e).__name__}: {str(e)}", exc_info=True)
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

