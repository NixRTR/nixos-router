"""
DHCP lease collector - parses Kea DHCP lease file
"""
import csv
from datetime import datetime
from pathlib import Path
from typing import List
from ..models import DHCPLease
from ..config import settings


def parse_kea_leases() -> List[DHCPLease]:
    """Parse Kea DHCP lease file (CSV format)
    
    Returns:
        List[DHCPLease]: List of active DHCP leases (deduplicated by IP)
    """
    lease_file = Path(settings.kea_lease_file)
    
    if not lease_file.exists():
        return []
    
    # Use dict to automatically deduplicate by IP (keeps last occurrence)
    leases_dict = {}
    
    try:
        with open(lease_file, 'r') as f:
            reader = csv.DictReader(f)
            
            for row in reader:
                # Determine network based on IP address
                ip = row.get('address', '')
                if not ip:
                    continue
                    
                network = 'homelab' if ip.startswith('192.168.2.') else 'lan'
                
                # Parse timestamps
                expire_ts = row.get('expire')
                valid_lifetime = int(row.get('valid_lifetime', 3600))
                
                lease_start = None
                lease_end = None
                
                if expire_ts:
                    try:
                        expire_timestamp = int(expire_ts)
                        lease_end = datetime.fromtimestamp(expire_timestamp)
                        lease_start = datetime.fromtimestamp(expire_timestamp - valid_lifetime)
                    except (ValueError, OSError):
                        pass
                
                dhcp_lease = DHCPLease(
                    network=network,
                    ip_address=ip,
                    mac_address=row.get('hwaddr', '00:00:00:00:00:00'),
                    hostname=row.get('hostname', '') or f"client-{ip.split('.')[-1]}",
                    lease_start=lease_start,
                    lease_end=lease_end,
                    last_seen=datetime.now(),
                    is_static=False
                )
                # Store in dict by IP - this automatically keeps the last (most recent) entry
                leases_dict[ip] = dhcp_lease
            
    except (csv.Error, IOError) as e:
        # Silently fail - lease file might be empty or being written
        pass
    except Exception as e:
        print(f"Error parsing Kea leases: {e}")
    
    return list(leases_dict.values())


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

