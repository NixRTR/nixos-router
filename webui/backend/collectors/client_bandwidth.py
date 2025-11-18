"""
Client bandwidth collector using nftables counters
Tracks per-client bandwidth by MAC address (IPv4 only)
"""
import subprocess
import os
import psutil
import re
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple
from pathlib import Path

from ..config import settings
from ..collectors.dhcp import parse_kea_leases
from ..collectors.network_devices import parse_arp_table, determine_network


# In-memory state for tracking previous counter values
_previous_counters: Dict[str, Dict[str, int]] = {}  # {ip: {rx_bytes_total, tx_bytes_total}}
_known_ips: set = set()  # Track which IPs we've added to nftables maps


def _find_nft() -> str:
    """Find nftables binary path"""
    env_path = os.environ.get("NFT_BIN")
    if env_path:
        return env_path
    candidates = [
        "/run/current-system/sw/bin/nft",
        "/usr/sbin/nft",
        "/sbin/nft",
        "nft",
    ]
    for path in candidates:
        try:
            p = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=2)
            if p.returncode == 0:
                return path
        except Exception:
            continue
    raise RuntimeError("nft binary not found")


def _run_nft(args: List[str], timeout: int = 5) -> subprocess.CompletedProcess:
    """Run nftables command"""
    nft = _find_nft()
    return subprocess.run(
        [nft] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False
    )


def _get_cpu_usage() -> float:
    """Get current CPU usage percentage"""
    try:
        return psutil.cpu_percent(interval=0.1)
    except Exception:
        return 0.0


def _check_cpu_threshold() -> bool:
    """Check if CPU usage is below threshold"""
    if not settings.bandwidth_collection_enabled:
        return False
    cpu_usage = _get_cpu_usage()
    return cpu_usage < settings.bandwidth_max_cpu_percent


def _add_ip_to_nftables_maps(ip: str) -> bool:
    """Add IP address to nftables counter maps if not already present"""
    if ip in _known_ips:
        return True
    
    try:
        # Add to rx counter map
        result_rx = _run_nft([
            "add", "element", "inet", "router_bandwidth", "client_rx_counters",
            "{", ip, ":", "counter", "}"
        ])
        
        # Add to tx counter map
        result_tx = _run_nft([
            "add", "element", "inet", "router_bandwidth", "client_tx_counters",
            "{", ip, ":", "counter", "}"
        ])
        
        if result_rx.returncode == 0 and result_tx.returncode == 0:
            _known_ips.add(ip)
            return True
    except Exception as e:
        print(f"Error adding IP {ip} to nftables maps: {e}")
    
    return False


def _read_nftables_counters() -> Dict[str, Dict[str, int]]:
    """Read nftables counter values for all IPs in the maps
    
    Returns:
        Dict[ip_address, {rx_bytes_total, tx_bytes_total}]
    """
    counters = {}
    
    try:
        # List counters with numeric output
        result = _run_nft([
            "list", "map", "inet", "router_bandwidth", "client_rx_counters"
        ])
        
        if result.returncode != 0:
            return counters
        
        # Parse counter map output
        # Format: elements = { 192.168.1.1 : counter packets 1234 bytes 567890 }
        rx_pattern = r'(\d+\.\d+\.\d+\.\d+)\s*:\s*counter\s+packets\s+\d+\s+bytes\s+(\d+)'
        for line in result.stdout.splitlines():
            matches = re.findall(rx_pattern, line)
            for ip, bytes_str in matches:
                if ip not in counters:
                    counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                counters[ip]['rx_bytes_total'] = int(bytes_str)
        
        # Read tx counters
        result = _run_nft([
            "list", "map", "inet", "router_bandwidth", "client_tx_counters"
        ])
        
        if result.returncode == 0:
            tx_pattern = r'(\d+\.\d+\.\d+\.\d+)\s*:\s*counter\s+packets\s+\d+\s+bytes\s+(\d+)'
            for line in result.stdout.splitlines():
                matches = re.findall(tx_pattern, line)
                for ip, bytes_str in matches:
                    if ip not in counters:
                        counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                    counters[ip]['tx_bytes_total'] = int(bytes_str)
    
    except Exception as e:
        print(f"Error reading nftables counters: {e}")
    
    return counters


def _map_ip_to_mac(ip: str, arp_table: Dict[str, Dict[str, str]], dhcp_leases: List) -> Optional[Tuple[str, str]]:
    """Map IP address to MAC address and network
    
    Args:
        ip: IP address to map
        arp_table: ARP table from parse_arp_table()
        dhcp_leases: List of DHCP leases
        
    Returns:
        Tuple[mac_address, network] or None
    """
    # Try ARP table first (most reliable for active devices)
    if ip in arp_table:
        mac = arp_table[ip]['mac_address']
        interface = arp_table[ip]['interface']
        network = determine_network(ip, interface)
        return (mac, network)
    
    # Fallback to DHCP leases
    for lease in dhcp_leases:
        if lease.ip_address == ip:
            return (lease.mac_address, lease.network)
    
    return None


def collect_client_bandwidth() -> List[Dict]:
    """Collect per-client bandwidth statistics
    
    Returns:
        List of dicts with client bandwidth data:
        {
            'mac_address': str,
            'ip_address': str,
            'network': str,
            'rx_bytes': int,  # bytes in this interval
            'tx_bytes': int,  # bytes in this interval
            'rx_bytes_total': int,  # cumulative
            'tx_bytes_total': int,  # cumulative
            'timestamp': datetime
        }
    """
    # Check CPU threshold
    if not _check_cpu_threshold():
        return []
    
    # Set process priority (nice value)
    try:
        os.nice(settings.bandwidth_collection_priority)
    except Exception:
        pass  # May not have permission, continue anyway
    
    current_time = datetime.now(timezone.utc)
    results = []
    
    try:
        # Get ARP table and DHCP leases for IP-to-MAC mapping
        arp_table = parse_arp_table()
        dhcp_leases = parse_kea_leases()
        
        # Read current counter values from nftables
        current_counters = _read_nftables_counters()
        
        # Process clients (limit to max_clients_per_cycle for CPU governance)
        processed = 0
        for ip, counter_data in current_counters.items():
            if processed >= settings.bandwidth_max_clients_per_cycle:
                break
            
            # Map IP to MAC address
            mac_network = _map_ip_to_mac(ip, arp_table, dhcp_leases)
            if not mac_network:
                continue  # Skip if we can't map IP to MAC
            
            mac_address, network = mac_network
            
            # Ensure IP is in nftables maps
            _add_ip_to_nftables_maps(ip)
            
            # Get previous counter values
            prev = _previous_counters.get(ip, {'rx_bytes_total': 0, 'tx_bytes_total': 0})
            
            rx_bytes_total = counter_data.get('rx_bytes_total', 0)
            tx_bytes_total = counter_data.get('tx_bytes_total', 0)
            
            # Calculate deltas (bytes in this interval)
            rx_bytes = max(0, rx_bytes_total - prev.get('rx_bytes_total', 0))
            tx_bytes = max(0, tx_bytes_total - prev.get('tx_bytes_total', 0))
            
            # Handle counter wraparound (unlikely but possible)
            if rx_bytes < 0:
                rx_bytes = rx_bytes_total
            if tx_bytes < 0:
                tx_bytes = tx_bytes_total
            
            # Update previous counters
            _previous_counters[ip] = {
                'rx_bytes_total': rx_bytes_total,
                'tx_bytes_total': tx_bytes_total
            }
            
            results.append({
                'mac_address': mac_address,
                'ip_address': ip,
                'network': network,
                'rx_bytes': rx_bytes,
                'tx_bytes': tx_bytes,
                'rx_bytes_total': rx_bytes_total,
                'tx_bytes_total': tx_bytes_total,
                'timestamp': current_time
            })
            
            processed += 1
        
        # Clean up old IPs from previous_counters that are no longer active
        active_ips = set(current_counters.keys())
        _previous_counters = {ip: data for ip, data in _previous_counters.items() if ip in active_ips}
        _known_ips.intersection_update(active_ips)
    
    except Exception as e:
        print(f"Error collecting client bandwidth: {e}")
    
    return results

