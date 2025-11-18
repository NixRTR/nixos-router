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
    for path in candidates:
        try:
            p = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=2)
            if p.returncode == 0:
                return path
        except Exception:
            continue
    raise RuntimeError("conntrack binary not found")


def _run_conntrack(args: List[str]) -> subprocess.CompletedProcess:
    """Run conntrack command"""
    try:
        conntrack = _find_conntrack()
    except RuntimeError as e:
        return subprocess.CompletedProcess(["conntrack"] + args, 1, "", str(e))
    
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


def _parse_conntrack_proc(proc_output: str) -> Dict[Tuple[str, str, int], Dict[str, int]]:
    """Parse /proc/net/netfilter/nf_conntrack output
    
    Format: Each line contains connection info with byte counts
    Example: ipv4     2 tcp      6 431999 ESTABLISHED src=192.168.2.31 dst=3.13.191.95 sport=35712 dport=443 packets=12345 bytes=1234567890 src=3.13.191.95 dst=216.137.218.48 sport=443 dport=35712 packets=9876 bytes=987654321 [ASSURED] mark=0
    
    The format has TWO separate bytes= fields:
    - First bytes= is for original direction (src->dst)
    - Second bytes= is for reply direction (dst->src)
    
    Returns:
        Dict[(client_ip, remote_ip, remote_port), {rx_bytes_total, tx_bytes_total}]
    """
    connections = {}
    lines_with_bytes = 0
    lines_without_bytes = 0
    sample_line_shown = False
    
    for line in proc_output.splitlines():
        if not line.strip():
            continue
        
        # Extract src/dst/ports from first part of connection
        # Format: ipv4 ... src=IP dst=IP sport=PORT dport=PORT ...
        match = re.search(r'src=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+)', line)
        if not match:
            continue
        
        src_ip = match.group(1)
        dst_ip = match.group(2)
        src_port = int(match.group(3))
        dst_port = int(match.group(4))
        
        # Only process IPv4 addresses
        if not _is_ipv4(src_ip) or not _is_ipv4(dst_ip):
            continue
        
        # Only track connections where client is in bridge subnets
        if not (src_ip.startswith('192.168.2.') or src_ip.startswith('192.168.3.')):
            continue
        
        # Extract bytes from the line
        # Format has TWO bytes= fields:
        # 1. First bytes= is for original direction (src->dst) = upload from client
        # 2. Second bytes= is for reply direction (dst->src) = download to client
        # Find all bytes= fields in the line
        bytes_matches = re.findall(r'bytes=(\d+)', line)
        
        if len(bytes_matches) < 2:
            # Try alternative format: bytes=TX:RX (combined format)
            combined_match = re.search(r'bytes=(\d+):(\d+)', line)
            if combined_match:
                bytes_sent = int(combined_match.group(1))  # TX (src->dst)
                bytes_recv = int(combined_match.group(2))    # RX (dst->src)
                lines_with_bytes += 1
            else:
                # Debug: show sample line without bytes
                if not sample_line_shown and lines_without_bytes < 3:
                    print(f"Debug: Line without bytes field (sample): {line[:200]}")
                    lines_without_bytes += 1
                    if lines_without_bytes >= 3:
                        sample_line_shown = True
                continue
        else:
            # First bytes= is original direction (src->dst) = upload
            # Second bytes= is reply direction (dst->src) = download
            bytes_sent = int(bytes_matches[0])  # Original direction (client -> remote)
            bytes_recv = int(bytes_matches[1])  # Reply direction (remote -> client)
            lines_with_bytes += 1
        
        # For client at src_ip:
        # - tx_bytes_total = bytes_sent (client -> remote) = original direction
        # - rx_bytes_total = bytes_recv (remote -> client) = reply direction
        
        key = (src_ip, dst_ip, dst_port)
        connections[key] = {
            'rx_bytes_total': bytes_recv,
            'tx_bytes_total': bytes_sent
        }
    
    if lines_with_bytes == 0 and connections:
        # Debug: show a sample line that matched but had no bytes
        print(f"Debug: _parse_conntrack_proc: Found {len(connections)} connections but 0 had bytes fields")
        if proc_output:
            sample_lines = [l[:200] for l in proc_output.splitlines()[:2] if l.strip() and ('192.168.2.' in l or '192.168.3.' in l)]
            if sample_lines:
                print(f"Debug: Sample lines from /proc: {sample_lines}")
    
    return connections


def _parse_conntrack_stats(stats_output: str) -> Dict[Tuple[str, str, int], Dict[str, int]]:
    """Parse conntrack stats output format
    
    Returns:
        Dict[(client_ip, remote_ip, remote_port), {rx_bytes_total, tx_bytes_total}]
    """
    # Stats format parsing - this is a placeholder
    # The actual format may vary, so we'll need to adapt based on actual output
    return {}


def _parse_conntrack_xml(xml_output: str) -> Dict[Tuple[str, str, int], Dict[str, int]]:
    """Parse conntrack XML output to extract connection information
    
    Returns:
        Dict[(client_ip, remote_ip, remote_port), {rx_bytes_total, tx_bytes_total}]
    """
    connections = {}
    try:
        import xml.etree.ElementTree as ET
        root = ET.fromstring(xml_output)
        
        for flow in root.findall('.//flow'):
            # Extract connection info from XML
            meta = flow.find('meta')
            if meta is None:
                continue
            
            layer3 = meta.find('layer3')
            layer4 = meta.find('layer4')
            if layer3 is None or layer4 is None:
                continue
            
            src_elem = layer3.find('src')
            dst_elem = layer3.find('dst')
            if src_elem is None or dst_elem is None:
                continue
            
            src_ip = src_elem.text
            dst_ip = dst_elem.text
            
            # Get ports from layer4
            sport_elem = layer4.find('sport')
            dport_elem = layer4.find('dport')
            if sport_elem is None or dport_elem is None:
                continue
            
            src_port = int(sport_elem.text)
            dst_port = int(dport_elem.text)
            
            # Only process IPv4 addresses
            if not _is_ipv4(src_ip) or not _is_ipv4(dst_ip):
                continue
            
            # Only track connections where client is in bridge subnets
            if not (src_ip.startswith('192.168.2.') or src_ip.startswith('192.168.3.')):
                continue
            
            # Extract bytes from orig and reply
            orig = flow.find('orig')
            reply = flow.find('reply')
            
            bytes_sent = 0
            bytes_recv = 0
            
            if orig is not None:
                bytes_elem = orig.find('bytes')
                if bytes_elem is not None:
                    bytes_sent = int(bytes_elem.text)
            
            if reply is not None:
                bytes_elem = reply.find('bytes')
                if bytes_elem is not None:
                    bytes_recv = int(bytes_elem.text)
            
            key = (src_ip, dst_ip, dst_port)
            connections[key] = {
                'rx_bytes_total': bytes_recv,
                'tx_bytes_total': bytes_sent
            }
    except Exception as e:
        print(f"Warning: Failed to parse conntrack XML: {e}")
    
    return connections


def _parse_conntrack_output(output: str) -> Dict[Tuple[str, str, int], Dict[str, int]]:
    """Parse conntrack extended output (fallback - may not include bytes)
    
    Returns:
        Dict[(client_ip, remote_ip, remote_port), {rx_bytes_total, tx_bytes_total}]
    """
    connections = {}
    
    # Pattern to match conntrack extended output
    # Extended output format can vary, try multiple patterns
    # Pattern 1: bytes=TX:RX (most common format)
    pattern1 = r'src=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+).*?bytes=(\d+):(\d+)'
    # Pattern 2: bytes_from_src=XXX bytes_to_src=YYY (alternative format)
    pattern2 = r'src=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+).*?bytes_from_src=(\d+).*?bytes_to_src=(\d+)'
    
    lines_processed = 0
    lines_matched = 0
    
    for line in output.splitlines():
        if not line.strip():
            continue
        
        lines_processed += 1
        match = None
        bytes_sent = 0
        bytes_recv = 0
        
        # Try pattern 1 first (most common)
        match = re.search(pattern1, line)
        if match:
            bytes_sent = int(match.group(5))  # bytes from src to dst
            bytes_recv = int(match.group(6))  # bytes from dst to src
        else:
            # Try pattern 2
            match = re.search(pattern2, line)
            if match:
                bytes_sent = int(match.group(5))  # bytes from src
                bytes_recv = int(match.group(6))  # bytes to src
            else:
                # Try more flexible pattern - extract src/dst/ports, then find bytes separately
                base_match = re.search(r'src=(\S+)\s+dst=(\S+)\s+sport=(\d+)\s+dport=(\d+)', line)
                if base_match:
                    # Look for bytes field anywhere in the line
                    bytes_match = re.search(r'bytes=(\d+):(\d+)', line)
                    if bytes_match:
                        match = base_match
                        bytes_sent = int(bytes_match.group(1))  # TX (src->dst)
                        bytes_recv = int(bytes_match.group(2))  # RX (dst->src)
        
        if not match:
            continue
        
        lines_matched += 1
        
        src_ip = match.group(1)
        dst_ip = match.group(2)
        src_port = int(match.group(3))
        dst_port = int(match.group(4))
        
        # Only process IPv4 addresses
        if not _is_ipv4(src_ip) or not _is_ipv4(dst_ip):
            continue
        
        # Only track connections where client is in bridge subnets
        if not (src_ip.startswith('192.168.2.') or src_ip.startswith('192.168.3.')):
            continue
        
        # For client connections:
        # - client_ip is the source (local side)
        # - remote_ip:remote_port is the destination (remote side)
        # - rx_bytes (download) = bytes received by client = bytes_recv (from dst to src)
        # - tx_bytes (upload) = bytes sent by client = bytes_sent (from src to dst)
        
        # Conntrack format is: bytes=TX:RX where TX is from src->dst, RX is from dst->src
        # So for client at src_ip:
        # - tx_bytes_total = bytes_sent (client -> remote)
        # - rx_bytes_total = bytes_recv (remote -> client)
        
        key = (src_ip, dst_ip, dst_port)
        connections[key] = {
            'rx_bytes_total': bytes_recv,
            'tx_bytes_total': bytes_sent
        }
    
    if lines_processed > 0 and lines_matched == 0:
        # Debug: print first few lines if no matches
        print(f"Debug: conntrack parser processed {lines_processed} lines, matched 0. First line: {output.splitlines()[0] if output.splitlines() else 'empty'}")
    
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
        # Try reading from /proc/net/nf_conntrack first (most reliable for byte counts)
        # This file contains the raw conntrack data with byte counts
        proc_paths = [
            '/proc/net/nf_conntrack',  # Standard location (confirmed to exist)
            '/proc/net/netfilter/nf_conntrack',  # Alternative location
        ]
        proc_output = None
        for proc_path in proc_paths:
            try:
                with open(proc_path, 'r') as f:
                    proc_output = f.read()
                print(f"Debug: Successfully read conntrack data from {proc_path}")
                break
            except FileNotFoundError:
                continue
            except Exception as e:
                print(f"Warning: Failed to read {proc_path}: {e}")
                continue
        
        # Parse connections
        current_connections = {}
        
        if proc_output:
            # Use /proc data directly (has byte counts)
            current_connections = _parse_conntrack_proc(proc_output)
        else:
            # Fallback to conntrack command if /proc is not available
            # Query conntrack for active connections with byte counts
            # Try different output formats to get byte counts
            # First try: -o stats (includes byte counts)
            # Second try: -o xml (includes byte counts)
            # Fallback: extended output (may not have bytes)
            result = _run_conntrack([
                "-L", "-n", "-o", "stats"
            ])
            
            # If stats format doesn't work, try XML
            if result.returncode != 0 or not result.stdout:
                result = _run_conntrack([
                    "-L", "-n", "-o", "xml"
                ])
            
            if result.returncode != 0 or not result.stdout:
                print(f"Warning: conntrack query failed: {result.stderr}")
                return results
            
            # Try parsing different output formats
            if result.stdout and '<?xml' in result.stdout:
                # XML format - parse it
                current_connections = _parse_conntrack_xml(result.stdout)
                print(f"Debug: Using XML parser, found {len(current_connections)} connections")
            elif result.stdout and 'stats' in result.stdout.lower() or 'bytes' in result.stdout.lower():
                # Stats format or output with bytes - try to parse it
                # Stats format might be different, try parsing as extended first
                current_connections = _parse_conntrack_output(result.stdout)
                if not current_connections:
                    # Try parsing stats format
                    current_connections = _parse_conntrack_stats(result.stdout)
                print(f"Debug: Using stats/extended parser, found {len(current_connections)} connections")
            else:
                # Try parsing as extended format (though it might not have bytes)
                current_connections = _parse_conntrack_output(result.stdout)
                print(f"Debug: Using extended parser, found {len(current_connections)} connections")
                
                # If no connections found, try /proc fallback
                if not current_connections:
                    proc_paths = [
                        '/proc/net/nf_conntrack',  # Standard location (confirmed to exist)
                        '/proc/net/netfilter/nf_conntrack',  # Alternative location
                    ]
                    proc_output = None
                    for proc_path in proc_paths:
                        try:
                            with open(proc_path, 'r') as f:
                                proc_output = f.read()
                            print(f"Debug: Fallback: Successfully read conntrack data from {proc_path}")
                            break
                        except FileNotFoundError:
                            continue
                        except Exception as e:
                            print(f"Warning: Failed to read {proc_path}: {e}")
                            continue
                    
                    if proc_output:
                        current_connections = _parse_conntrack_proc(proc_output)
                    else:
                        print(f"Warning: Could not find conntrack data in /proc (tried: {proc_paths})")
        
        if not current_connections:
            return results
        
        # Debug: Check if we have byte counts
        total_bytes = sum(c.get('rx_bytes_total', 0) + c.get('tx_bytes_total', 0) for c in current_connections.values())
        print(f"Debug: Parsed {len(current_connections)} connections from conntrack, total bytes: {total_bytes}")
        
        # Debug: Show sample connection with bytes
        if current_connections:
            sample_key = list(current_connections.keys())[0]
            sample_data = current_connections[sample_key]
            print(f"Debug: Sample connection {sample_key}: rx={sample_data.get('rx_bytes_total', 0)}, tx={sample_data.get('tx_bytes_total', 0)}")
        
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

