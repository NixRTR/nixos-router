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


def _add_ip_to_nftables(ip: str) -> bool:
    """Add IP address to nftables set and create per-IP counter rules"""
    if ip in _known_ips:
        return True
    
    try:
        # Add IP to set
        result_set = _run_nft([
            "add", "element", "inet", "router_bandwidth", "client_ips", "{", ip, "}"
        ])
        
        if result_set.returncode == 0:
            # Add per-IP counter rules for rx (download)
            result_rx = _run_nft([
                "insert", "rule", "inet", "router_bandwidth", "forward",
                "ip", "daddr", ip, "counter", "name", f"rx_{ip.replace('.', '_')}"
            ])
            
            # Add per-IP counter rules for tx (upload)
            result_tx = _run_nft([
                "insert", "rule", "inet", "router_bandwidth", "forward",
                "ip", "saddr", ip, "counter", "name", f"tx_{ip.replace('.', '_')}"
            ])
            
            if result_rx.returncode == 0 and result_tx.returncode == 0:
                _known_ips.add(ip)
                return True
    except Exception as e:
        print(f"Error adding IP {ip} to nftables: {e}")
    
    return False


def _read_nftables_counters() -> Dict[str, Dict[str, int]]:
    """Read nftables counter values for all IPs with named counters
    
    Returns:
        Dict[ip_address, {rx_bytes_total, tx_bytes_total}]
    """
    counters = {}
    
    try:
        # List all counters in the table
        result = _run_nft([
            "list", "counters", "inet", "router_bandwidth"
        ])
        
        if result.returncode != 0:
            print(f"Warning: nft list counters failed: {result.stderr}")
            return counters
        
        # Parse counter output
        # Format: counter rx_192_168_1_1 { packets 1234 bytes 567890 }
        # Or multi-line format:
        # counter rx_192_168_1_1 {
        #   packets 1234
        #   bytes 567890
        # }
        rx_pattern = r'counter\s+rx_(\d+)_(\d+)_(\d+)_(\d+)'
        tx_pattern = r'counter\s+tx_(\d+)_(\d+)_(\d+)_(\d+)'
        bytes_pattern = r'bytes\s+(\d+)'
        
        current_counter = None
        current_type = None
        
        for line in result.stdout.splitlines():
            line = line.strip()
            
            # Check for RX counter declaration
            rx_match = re.search(rx_pattern, line)
            if rx_match:
                ip = f"{rx_match.group(1)}.{rx_match.group(2)}.{rx_match.group(3)}.{rx_match.group(4)}"
                current_counter = ip
                current_type = 'rx'
                if ip not in counters:
                    counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                continue
            
            # Check for TX counter declaration
            tx_match = re.search(tx_pattern, line)
            if tx_match:
                ip = f"{tx_match.group(1)}.{tx_match.group(2)}.{tx_match.group(3)}.{tx_match.group(4)}"
                current_counter = ip
                current_type = 'tx'
                if ip not in counters:
                    counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                continue
            
            # Check for bytes value (could be on same line or next line)
            bytes_match = re.search(bytes_pattern, line)
            if bytes_match and current_counter:
                bytes_val = int(bytes_match.group(1))
                if current_type == 'rx':
                    counters[current_counter]['rx_bytes_total'] = bytes_val
                elif current_type == 'tx':
                    counters[current_counter]['tx_bytes_total'] = bytes_val
                current_counter = None
                current_type = None
    
    except Exception as e:
        print(f"Error reading nftables counters: {e}")
        import traceback
        traceback.print_exc()
    
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
        
        if not current_counters:
            # No counters found - this might be normal if no traffic yet
            # But log it for debugging
            print(f"Debug: No nftables counters found. Known IPs: {len(_known_ips)}")
        
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
            
            # Ensure IP is in nftables (set + counter rules)
            _add_ip_to_nftables(ip)
            
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
        # Update _previous_counters in place to avoid scoping issues
        for ip in list(_previous_counters.keys()):
            if ip not in active_ips:
                del _previous_counters[ip]
        _known_ips.intersection_update(active_ips)
    
    except Exception as e:
        print(f"Error collecting client bandwidth: {e}")
    
    return results

