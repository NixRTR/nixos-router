"""
Client statistics collector
"""
from datetime import datetime
from typing import List
from ..models import ClientStats
from .network_devices import collect_network_devices


async def collect_client_stats() -> List[ClientStats]:
    """Collect client statistics for each network
    
    Returns:
        List[ClientStats]: Statistics for HOMELAB and LAN networks
    """
    results = []
    
    # Get all network devices
    devices = await collect_network_devices()
    
    # Group by network
    for network in ['homelab', 'lan']:
        network_devices = [d for d in devices if d.network == network]
        
        dhcp_count = sum(1 for d in network_devices if d.is_dhcp and not d.is_static)
        static_dhcp_count = sum(1 for d in network_devices if d.is_static)
        static_ip_count = sum(1 for d in network_devices if not d.is_dhcp)
        online_count = sum(1 for d in network_devices if d.is_online)
        offline_count = sum(1 for d in network_devices if not d.is_online)
        
        results.append(ClientStats(
            timestamp=datetime.now(),
            network=network,
            dhcp_clients=dhcp_count,
            static_clients=static_dhcp_count + static_ip_count,
            total_clients=len(network_devices),
            online_clients=online_count,
            offline_clients=offline_count
        ))
    
    return results

