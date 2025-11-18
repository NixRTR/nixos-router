"""
Client connection collector using conntrack
Tracks per-connection bandwidth by client IP and remote IP:Port (IPv4 only)
"""
import subprocess
import os
import re
import socket
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from ..collectors.dhcp import parse_kea_leases
from ..collectors.network_devices import parse_arp_table


# In-memory state for tracking previous connection byte counts
_previous_connections: Dict[str, Dict[str, int]] = {}  # {(client_ip, remote_ip, remote_port): {rx_bytes_total, tx_bytes_total}}
_hostname_cache: Dict[str, Optional[str]] = {}  # Cache for reverse DNS lookups


def _find_conntrack() -> str:
    """Find conntrack binary path"""
    env_path = os.environ.get("CONNTRACK_BIN")
    if env_path:
        return env_path
    candidates = [
        "/run/current-system/sw/bin/conntrack",
        "/usr/sbin/conntrack",
        "/usr/bin/conntrack",
        "conntrack"
    ]
    for candidate in candidates:
        if os.path.exists(candidate) or candidate == "conntrack":
            return candidate
    return "conntrack"


def _run_conntrack(args: List[str]) -> subprocess.CompletedProcess:
    """Run conntrack command"""
    conntrack = _find_conntrack()
    try:
        result = subprocess.run(
            [conntrack] + args,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess([conntrack] + args, 1, "", "Timeout")
    except Exception as e:
        return subprocess.CompletedProcess([conntrack] + args, 1, "", str(e))


def _is_ipv4(ip: str) -> bool:
    """Check if an IP address is IPv4"""
    try:
        parts = ip.split('.')
        if len(parts) != 4:
            return False
        for part in parts:
            num = int(part)
            if num < 0 or num > 255:
                return False
        return True
    except (ValueError, AttributeError):
        return False


def _resolve_hostname(ip: str) -> Optional[str]:
    """Resolve IP address to hostname using reverse DNS with caching"""
    if not _is_ipv4(ip):
        return None
    
    # Check cache first
    if ip in _hostname_cache:
        return _hostname_cache[ip]
    
    try:
        # Try reverse DNS lookup
        hostname, _, _ = socket.gethostbyaddr(ip)
        # Cache the result (even if None)
        _hostname_cache[ip] = hostname
        return hostname
    except (socket.herror, socket.gaierror, OSError):
        # DNS lookup failed, cache None
        _hostname_cache[ip] = None
        return None
    except Exception:
        _hostname_cache[ip] = None
        return None


def _parse_conntrack_output(output: str) -> Dict[Tuple[str, str, int], Dict[str, int]]:
    """Parse conntrack output to extract connection information
    
    Format: src=IP dst=IP sport=PORT dport=PORT bytes=RX:TX packets=PACKETS
    
    Returns:
        Dict[(client_ip, remote_ip, remote_port), {rx_bytes_total, tx_bytes_total}]
    """
    connections = {}
    
    # Pattern to match conntrack extended output
    # Example: src=192.168.2.10 dst=8.8.8.8 sport=54321 dport=53 packets=5 bytes=320 [UNREPLIED] ...
    pattern = r'src=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+).*?bytes=(\d+):(\d+)'
    
    for line in output.splitlines():
        match = re.search(pattern, line)
        if not match:
            continue
        
        src_ip = match.group(1)
        dst_ip = match.group(2)
        src_port = int(match.group(3))
        dst_port = int(match.group(4))
        bytes_sent = int(match.group(5))  # bytes from src to dst
        bytes_recv = int(match.group(6))  # bytes from dst to src
        
        # Only process IPv4 addresses
        if not _is_ipv4(src_ip) or not _is_ipv4(dst_ip):
            continue
        
        # Only track connections where client is in bridge subnets
        if not (src_ip.startswith('192.168.2.') or src_ip.startswith('192.168.3.')):
            continue
        
        # For client connections:
        # - client_ip is the source (local side)
        # - remote_ip:remote_port is the destination (remote side)
        # - rx_bytes (download) = bytes received by client = bytes_sent from remote
        # - tx_bytes (upload) = bytes sent by client = bytes_sent from client
        # But conntrack shows bytes from src->dst, so:
        # - bytes_sent = bytes from src to dst (upload from client perspective)
        # - bytes_recv = bytes from dst to src (download from client perspective)
        
        # Actually, conntrack format is: bytes=TX:RX where TX is from src->dst, RX is from dst->src
        # So for client at src_ip:
        # - tx_bytes_total = bytes_sent (client -> remote)
        # - rx_bytes_total = bytes_recv (remote -> client)
        
        key = (src_ip, dst_ip, dst_port)
        connections[key] = {
            'rx_bytes_total': bytes_recv,
            'tx_bytes_total': bytes_sent
        }
    
    return connections


def _map_ip_to_mac(ip: str, arp_table: Dict[str, Dict[str, str]], dhcp_leases: List) -> Optional[str]:
    """Map IP address to MAC address
    
    Args:
        ip: IP address to map
        arp_table: ARP table from parse_arp_table()
        dhcp_leases: List of DHCP leases
        
    Returns:
        MAC address or None
    """
    # Try ARP table first (most reliable for active devices)
    if ip in arp_table:
        return arp_table[ip]['mac_address']
    
    # Fallback to DHCP leases
    for lease in dhcp_leases:
        if lease.ip_address == ip:
            return lease.mac_address
    
    return None


def collect_client_connections() -> List[Dict]:
    """Collect per-connection bandwidth statistics
    
    Returns:
        List of dicts with connection data:
        {
            'client_ip': str,
            'client_mac': str,
            'remote_ip': str,
            'remote_port': int,
            'rx_bytes': int,  # bytes in this interval
            'tx_bytes': int,  # bytes in this interval
            'rx_bytes_total': int,  # cumulative
            'tx_bytes_total': int,  # cumulative
            'timestamp': datetime
        }
    """
    current_time = datetime.now(timezone.utc)
    results = []
    
    try:
        # Query conntrack for active connections
        result = _run_conntrack([
            "-L", "-n", "--output", "extended"
        ])
        
        if result.returncode != 0:
            print(f"Warning: conntrack query failed: {result.stderr}")
            return results
        
        # Parse conntrack output
        current_connections = _parse_conntrack_output(result.stdout)
        
        if not current_connections:
            return results
        
        # Get ARP table and DHCP leases for IP-to-MAC mapping
        arp_table = parse_arp_table()
        dhcp_leases = parse_kea_leases()
        
        # Process each connection
        for (client_ip, remote_ip, remote_port), counter_data in current_connections.items():
            # Map client IP to MAC address
            client_mac = _map_ip_to_mac(client_ip, arp_table, dhcp_leases)
            if not client_mac:
                continue  # Skip if we can't map IP to MAC
            
            # Get previous counter values
            connection_key = f"{client_ip}:{remote_ip}:{remote_port}"
            prev = _previous_connections.get(connection_key, {'rx_bytes_total': 0, 'tx_bytes_total': 0})
            
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
            _previous_connections[connection_key] = {
                'rx_bytes_total': rx_bytes_total,
                'tx_bytes_total': tx_bytes_total
            }
            
            results.append({
                'client_ip': client_ip,
                'client_mac': client_mac,
                'remote_ip': remote_ip,
                'remote_port': remote_port,
                'rx_bytes': rx_bytes,
                'tx_bytes': tx_bytes,
                'rx_bytes_total': rx_bytes_total,
                'tx_bytes_total': tx_bytes_total,
                'timestamp': current_time
            })
        
        # Clean up old connections from previous_connections that are no longer active
        active_keys = {f"{ip}:{rip}:{port}" for (ip, rip, port) in current_connections.keys()}
        for key in list(_previous_connections.keys()):
            if key not in active_keys:
                del _previous_connections[key]
    
    except Exception as e:
        print(f"Error collecting client connections: {e}")
        import traceback
        traceback.print_exc()
    
    return results

