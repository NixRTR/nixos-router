"""
Systemd service status collector
"""
import subprocess
import psutil
from datetime import datetime
from typing import List, Optional
from ..models import ServiceStatus


# Services to monitor
MONITORED_SERVICES = [
    "unbound-homelab",
    "unbound-lan",
    "kea-dhcp4-server",
    "pppd-eno1",  # PPPoE service
    "router-webui-backend",
]


def get_service_status(service_name: str) -> Optional[ServiceStatus]:
    """Get status of a systemd service
    
    Args:
        service_name: Name of the service
        
    Returns:
        ServiceStatus or None if service doesn't exist
    """
    try:
        # Get service active state
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        is_active = result.stdout.strip() == 'active'
        
        # Get service enabled state
        result = subprocess.run(
            ['systemctl', 'is-enabled', service_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        is_enabled = result.stdout.strip() == 'enabled'
        
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
        
        return ServiceStatus(
            timestamp=datetime.now(),
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
        List[ServiceStatus]: Status of all services
    """
    statuses = []
    
    for service in MONITORED_SERVICES:
        status = get_service_status(service)
        if status:
            statuses.append(status)
    
    return statuses

