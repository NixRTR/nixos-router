"""
Systemd service status collector
"""
import subprocess
import psutil
from datetime import datetime, timezone
from typing import List, Optional
from ..models import ServiceStatus


# Services to monitor
# Network Services
NETWORK_SERVICES = [
    "kea-dhcp4-server",  # DHCP Server (IPv4)
    "unbound-homelab",   # Homelab DNS
    "unbound-lan",       # LAN DNS
    "pppd-eno1",         # PPPoE Server
    "linode-dyndns",     # Linode Dynamic DNS
]

# WebUI Services
WEBUI_SERVICES = [
    "nginx",                 # WebUI Frontend (serves static files and reverse proxy)
    "router-webui-backend",  # WebUI Backend
    "postgresql",            # WebUI Database
    "speedtest",             # Speedtest monitoring
]

# All monitored services
MONITORED_SERVICES = NETWORK_SERVICES + WEBUI_SERVICES


def get_service_status(service_name: str) -> Optional[ServiceStatus]:
    """Get status of a systemd service
    
    Args:
        service_name: Name of the service
        
    Returns:
        ServiceStatus or None if service doesn't exist (unit file not found)
    """
    try:
        # Get service active state
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True,
            timeout=5,
            check=False  # Don't raise on non-zero exit
        )
        # Exit code 0 = active/activating, 3 = inactive, 4 = does not exist
        if result.returncode == 4:
            return None  # Service doesn't exist
        active_state = result.stdout.strip()
        # For one-shot services, "activating" means it's currently running
        # For regular services, "active" means it's running
        is_active = active_state in ('active', 'activating')
        
        # Get service enabled state
        result = subprocess.run(
            ['systemctl', 'is-enabled', service_name],
            capture_output=True,
            text=True,
            timeout=5,
            check=False  # Don't raise on non-zero exit
        )
        # Exit code 0 = enabled, 1 = disabled/static/indirect, 2+ = doesn't exist
        if result.returncode >= 2:
            return None  # Service doesn't exist
        enabled_state = result.stdout.strip()
        is_enabled = enabled_state == 'enabled'
        
        # Get service main PID
        result = subprocess.run(
            ['systemctl', 'show', service_name, '--property=MainPID'],
            capture_output=True,
            text=True,
            timeout=5
        )
        pid = None
        if 'MainPID=' in result.stdout:
            pid_str = result.stdout.split('=')[1].strip()
            if pid_str and pid_str != '0':
                pid = int(pid_str)
        
        # Get process stats if we have a PID
        memory_mb = None
        cpu_percent = None
        if pid and pid > 0:
            try:
                process = psutil.Process(pid)
                mem_info = process.memory_info()
                memory_mb = mem_info.rss / (1024 * 1024)  # Convert to MB
                cpu_percent = process.cpu_percent(interval=0.1)
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        # Store service type for one-shot detection
        # We'll add this to the model or use a workaround
        # For now, we'll detect it in the frontend based on service name
        
        return ServiceStatus(
            timestamp=datetime.now(timezone.utc),
            service_name=service_name,
            is_active=is_active,
            is_enabled=is_enabled,
            pid=pid,
            memory_mb=memory_mb,
            cpu_percent=cpu_percent
        )
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
        return None


def collect_service_statuses() -> List[ServiceStatus]:
    """Collect status for all monitored services
    
    Returns:
        List[ServiceStatus]: Status of all services (including non-existent ones)
    """
    statuses = []
    
    for service in MONITORED_SERVICES:
        status = get_service_status(service)
        if status:
            statuses.append(status)
        else:
            # Service doesn't exist - create a status entry indicating it's not found
            # This allows the frontend to display it as "Not Found" or "Disabled"
            statuses.append(ServiceStatus(
                timestamp=datetime.now(timezone.utc),
                service_name=service,
                is_active=False,
                is_enabled=False,
                pid=None,
                memory_mb=None,
                cpu_percent=None
            ))
    
    return statuses

