"""
Network interface statistics collector
"""
import psutil
from datetime import datetime
from typing import Dict, List, Optional
from ..models import InterfaceStats


# Store previous readings for rate calculation
_previous_stats: Dict[str, Dict] = {}
_previous_time: Optional[datetime] = None


def collect_interface_stats() -> List[InterfaceStats]:
    """Collect statistics for all network interfaces
    
    Returns:
        List[InterfaceStats]: Stats for each interface
    """
    global _previous_stats, _previous_time
    
    current_time = datetime.now()
    io_counters = psutil.net_io_counters(pernic=True)
    
    stats_list = []
    
    for interface, counters in io_counters.items():
        # Calculate bandwidth rates if we have previous data
        rx_rate_mbps = None
        tx_rate_mbps = None
        
        if interface in _previous_stats and _previous_time:
            time_delta = (current_time - _previous_time).total_seconds()
            if time_delta > 0:
                prev = _previous_stats[interface]
                rx_delta = counters.bytes_recv - prev['rx_bytes']
                tx_delta = counters.bytes_sent - prev['tx_bytes']
                
                # Convert to Mbps
                rx_rate_mbps = (rx_delta * 8) / (time_delta * 1_000_000)
                tx_rate_mbps = (tx_delta * 8) / (time_delta * 1_000_000)
        
        # Store current stats for next iteration
        _previous_stats[interface] = {
            'rx_bytes': counters.bytes_recv,
            'tx_bytes': counters.bytes_sent,
        }
        
        stats = InterfaceStats(
            timestamp=current_time,
            interface=interface,
            rx_bytes=counters.bytes_recv,
            tx_bytes=counters.bytes_sent,
            rx_packets=counters.packets_recv,
            tx_packets=counters.packets_sent,
            rx_errors=counters.errin,
            tx_errors=counters.errout,
            rx_dropped=counters.dropin,
            tx_dropped=counters.dropout,
            rx_rate_mbps=rx_rate_mbps,
            tx_rate_mbps=tx_rate_mbps
        )
        stats_list.append(stats)
    
    _previous_time = current_time
    return stats_list


def get_interface_status(interface: str) -> bool:
    """Check if an interface is up
    
    Args:
        interface: Interface name
        
    Returns:
        bool: True if interface is up
    """
    try:
        stats = psutil.net_if_stats()
        if interface in stats:
            return stats[interface].isup
    except Exception:
        pass
    return False

