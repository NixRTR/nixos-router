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
        # For mailto URLs, we need special handling because they can have query parameters
        # that also need encoding (like &from=email@domain.com)
        if url.startswith('mailto://'):
            # Parse mailto URL manually since urlparse might not handle it correctly
            # Format: mailto://user:pass@host:port?to=email&from=email
            scheme_end = url.find('://')
            if scheme_end == -1:
                return url
            
            scheme = url[:scheme_end + 3]  # Include ://
            rest = url[scheme_end + 3:]
            
            # Find query string start
            query_start = rest.find('?')
            if query_start != -1:
                url_part = rest[:query_start]
                query_part = rest[query_start + 1:]
            else:
                url_part = rest
                query_part = ""
            
            # Parse user:pass@host:port
            if '@' in url_part:
                userinfo, hostport = url_part.rsplit('@', 1)
                if ':' in userinfo:
                    username, password = userinfo.split(':', 1)
                    # URL-encode the password (decode first in case it's partially encoded)
                    try:
                        # Try to decode first to avoid double-encoding
                        decoded_password = password
                        # URL-encode the password
                        encoded_password = quote(decoded_password, safe='')
                    except:
                        encoded_password = quote(password, safe='')
                    # Reconstruct URL part
                    encoded_url_part = f"{username}:{encoded_password}@{hostport}"
                else:
                    encoded_url_part = url_part
            else:
                encoded_url_part = url_part
            
            # Encode query parameters
            if query_part:
                # Parse and encode query parameters
                query_params = []
                for param in query_part.split('&'):
                    if '=' in param:
                        key, value = param.split('=', 1)
                        # URL-encode the value
                        encoded_value = quote(value, safe='')
                        query_params.append(f"{key}={encoded_value}")
                    else:
                        query_params.append(param)
                encoded_query = '&'.join(query_params)
                return f"{scheme}{encoded_url_part}?{encoded_query}"
            else:
                return f"{scheme}{encoded_url_part}"
        
        # For other URL types, use standard URL parsing
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
        logger.debug(f"Problematic URL: {url[:100]}... (masked)", exc_info=True)
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
        logger.info(f"Loading Apprise config from: {config_path}")
        # Check file permissions and size
        stat_info = os.stat(config_path)
        logger.debug(f"Config file size: {stat_info.st_size} bytes, mode: {oct(stat_info.st_mode)}")
        
        with open(config_path, 'r') as f:
            lines = f.readlines()
            logger.info(f"Config file has {len(lines)} lines")
            
            # Log first few non-empty lines (masked) to verify sops replacement
            non_empty_lines = [line.strip() for line in lines if line.strip() and not line.strip().startswith('#')]
            logger.debug(f"Found {len(non_empty_lines)} non-empty, non-comment lines")
            for idx, line in enumerate(non_empty_lines[:5], 1):
                # Mask sensitive parts but show structure
                masked = re.sub(r':([^:@/]+)@', r':***@', line)
                masked = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked)
                logger.debug(f"Line {idx} structure (masked): {masked[:100]}...")
            
            # Read all lines, filter out empty lines and comments
            for line_num, line in enumerate(lines, 1):
                original_line = line
                line = line.strip()
                if line and not line.startswith('#'):
                    # Check if line contains sops placeholder (not replaced)
                    if '${' in line:
                        logger.error(f"Line {line_num} contains UNREPLACED sops placeholder: {line[:100]}...")
                        logger.error(f"This means sops-nix did not replace the placeholder. Check:")
                        logger.error(f"  1. Is the secret defined in modules/secrets.nix?")
                        logger.error(f"  2. Does the secret exist in secrets/secrets.yaml?")
                        logger.error(f"  3. Is sops-nix properly configured?")
                        continue  # Skip this line - it won't work
                    
                    # Log the raw line structure (masked) before encoding
                    masked_line = re.sub(r':([^:@/]+)@', r':***@', line)
                    masked_line = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked_line)
                    logger.debug(f"Line {line_num} - Raw (masked): {masked_line[:80]}...")
                    
                    # URL-encode passwords/tokens in the URL before adding to Apprise
                    encoded_url = url_encode_password_in_url(line)
                    if encoded_url != line:
                        masked_encoded = re.sub(r':([^:@/]+)@', r':***@', encoded_url)
                        masked_encoded = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked_encoded)
                        logger.debug(f"Line {line_num} - Encoded (masked): {masked_encoded[:80]}...")
                    
                    try:
                        # Store count before adding
                        count_before = len(apobj)
                        
                        # Add each service URL to Apprise
                        apobj.add(encoded_url)
                        
                        # Check if service was actually added
                        count_after = len(apobj)
                        if count_after > count_before:
                            logger.info(f"Successfully added service from line {line_num} (Apprise now has {count_after} service(s))")
                        else:
                            logger.warning(f"Service from line {line_num} was not added to Apprise (count unchanged: {count_before})")
                            logger.warning(f"This usually means Apprise rejected the URL format. Check Apprise logs above.")
                            # Try to add the original URL as a fallback
                            try:
                                logger.warning(f"Attempting to add original URL as fallback")
                                apobj.add(line)
                                if len(apobj) > count_before:
                                    logger.info(f"Successfully added original URL as fallback")
                                else:
                                    logger.error(f"Fallback also failed - URL format may be incorrect")
                            except Exception as fallback_error:
                                logger.error(f"Fallback also failed: {type(fallback_error).__name__}: {str(fallback_error)}")
                    except Exception as add_error:
                        logger.error(f"Failed to add service from line {line_num}: {type(add_error).__name__}: {str(add_error)}")
                        # Show more context about the URL structure
                        masked_orig = re.sub(r':([^:@/]+)@', r':***@', line)
                        masked_orig = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked_orig)
                        masked_enc = re.sub(r':([^:@/]+)@', r':***@', encoded_url)
                        masked_enc = re.sub(r'/([^/]+)/([^/]+)/', r'/***/***/', masked_enc)
                        logger.error(f"Problematic URL (original, masked): {masked_orig[:100]}...")
                        logger.error(f"Problematic URL (encoded, masked): {masked_enc[:100]}...")
                        # Try to add the original URL as a fallback
                        try:
                            logger.warning(f"Attempting to add original URL as fallback")
                            apobj.add(line)
                            logger.info(f"Successfully added original URL as fallback")
                        except Exception as fallback_error:
                            logger.error(f"Fallback also failed: {type(fallback_error).__name__}: {str(fallback_error)}")
    else:
        logger.warning(f"Apprise config file does not exist: {config_path}")
        logger.warning(f"Expected location: {config_path}")
        logger.warning(f"Check if apprise-api-config-init.service ran successfully")
    
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
            
            # Check if we can get more details about the result
            # Apprise stores errors in the notification response
            if not result:
                # Try to get error details from Apprise
                # Apprise doesn't expose this easily, but we can check if the service was added
                logger.warning(f"Notification returned False for {get_service_name_from_url(raw_url)}")
                # Check if the service was actually added to the Apprise object
                service_count = len(apobj)
                if service_count == 0:
                    return (False, "Service URL could not be parsed", "The service URL format may be invalid or the credentials may contain invalid characters")
                else:
                    return (False, "Failed to send notification", "The service may be misconfigured, unreachable, or the credentials may be invalid. Check the Apprise logs for details.")
            
            logger.info(f"Successfully sent notification to {get_service_name_from_url(raw_url)}")
            return (True, None, f"Notification sent successfully to {get_service_name_from_url(raw_url)}")
            
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

