"""
DHCP lease collector - parses Kea DHCP lease file
"""
import json
from datetime import datetime
from pathlib import Path
from typing import List
from ..models import DHCPLease
from ..config import settings


def parse_kea_leases() -> List[DHCPLease]:
    """Parse Kea DHCP lease file
    
    Returns:
        List[DHCPLease]: List of active DHCP leases
    """
    lease_file = Path(settings.kea_lease_file)
    
    if not lease_file.exists():
        return []
    
    leases = []
    
    try:
        with open(lease_file, 'r') as f:
            data = json.load(f)
            
        # Kea stores leases in the 'leases' array
        for lease in data.get('leases', []):
            # Determine network based on IP address
            ip = lease.get('ip-address', '')
            network = 'homelab' if ip.startswith('192.168.2.') else 'lan'
            
            # Parse timestamps
            cltt = lease.get('cltt')  # Client last transaction time
            valid_lifetime = lease.get('valid-lifetime', 3600)
            
            lease_start = None
            lease_end = None
            if cltt:
                lease_start = datetime.fromtimestamp(cltt)
                lease_end = datetime.fromtimestamp(cltt + valid_lifetime)
            
            dhcp_lease = DHCPLease(
                network=network,
                ip_address=ip,
                mac_address=lease.get('hw-address', '00:00:00:00:00:00'),
                hostname=lease.get('hostname'),
                lease_start=lease_start,
                lease_end=lease_end,
                last_seen=datetime.now(),
                is_static=False  # Could be enhanced to check against router-config.nix
            )
            leases.append(dhcp_lease)
            
    except (json.JSONDecodeError, IOError) as e:
        print(f"Error parsing Kea leases: {e}")
        return []
    
    return leases


def get_client_count_by_network() -> dict[str, int]:
    """Get count of DHCP clients by network
    
    Returns:
        dict: {'homelab': count, 'lan': count}
    """
    leases = parse_kea_leases()
    counts = {'homelab': 0, 'lan': 0}
    
    for lease in leases:
        if lease.network in counts:
            counts[lease.network] += 1
    
    return counts

