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


def _add_ip_to_nftables(ip: str) -> bool:
    """Add IP address to nftables set and create per-IP counter rules (IPv4 only)"""
    # Only process IPv4 addresses
    if not _is_ipv4(ip):
        return False
    
    if ip in _known_ips:
        return True
    
    try:
        # First verify the table and chain exist
        result_check = _run_nft([
            "list", "chain", "inet", "router_bandwidth", "forward"
        ])
        if result_check.returncode != 0:
            print(f"Warning: Chain inet router_bandwidth forward does not exist: {result_check.stderr}")
            return False
        
        # Add IP to set
        result_set = _run_nft([
            "add", "element", "inet", "router_bandwidth", "client_ips", "{", ip, "}"
        ])
        
        if result_set.returncode != 0:
            # Set add might fail if IP already exists, that's okay
            if "File exists" not in result_set.stderr and "already exists" not in result_set.stderr.lower():
                # Only warn if it's not an IPv6 address (which we intentionally skip)
                if "Address family" not in result_set.stderr:
                    print(f"Warning: Failed to add IP {ip} to set: {result_set.stderr}")
            else:
                # IP already in set, mark as known
                _known_ips.add(ip)
                return True
        
        # Create named counters first, then add rules that reference them
        counter_name_rx = f"rx_{ip.replace('.', '_')}"
        counter_name_tx = f"tx_{ip.replace('.', '_')}"
        
        nft = _find_nft()
        
        # Create RX counter (ignore if it already exists)
        result_counter_rx = _run_nft([
            "add", "counter", "inet", "router_bandwidth", counter_name_rx
        ])
        # Ignore "File exists" errors - counter might already exist
        
        # Create TX counter (ignore if it already exists)
        result_counter_tx = _run_nft([
            "add", "counter", "inet", "router_bandwidth", counter_name_tx
        ])
        # Ignore "File exists" errors - counter might already exist
        
        # Now add rules that reference the counters
        # Use stdin approach for better reliability
        rx_rule_cmd = f"insert rule inet router_bandwidth forward ip daddr {ip} counter name {counter_name_rx}\n"
        result_rx = subprocess.run(
            [nft, "-f", "-"],
            input=rx_rule_cmd,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result_rx.returncode != 0:
            # Rule might already exist
            if "File exists" not in result_rx.stderr and "already exists" not in result_rx.stderr.lower():
                # Try using "add" instead of "insert"
                rx_rule_cmd = f"add rule inet router_bandwidth forward ip daddr {ip} counter name {counter_name_rx}\n"
                result_rx = subprocess.run(
                    [nft, "-f", "-"],
                    input=rx_rule_cmd,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result_rx.returncode != 0 and "File exists" not in result_rx.stderr and "already exists" not in result_rx.stderr.lower():
                    # Don't warn if it's just that the rule already exists
                    if "File exists" not in result_rx.stderr:
                        print(f"Warning: Failed to add RX rule for IP {ip}: {result_rx.stderr}")
        
        # Add TX rule
        tx_rule_cmd = f"insert rule inet router_bandwidth forward ip saddr {ip} counter name {counter_name_tx}\n"
        result_tx = subprocess.run(
            [nft, "-f", "-"],
            input=tx_rule_cmd,
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result_tx.returncode != 0:
            # Rule might already exist
            if "File exists" not in result_tx.stderr and "already exists" not in result_tx.stderr.lower():
                # Try using "add" instead of "insert"
                tx_rule_cmd = f"add rule inet router_bandwidth forward ip saddr {ip} counter name {counter_name_tx}\n"
                result_tx = subprocess.run(
                    [nft, "-f", "-"],
                    input=tx_rule_cmd,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result_tx.returncode != 0 and "File exists" not in result_tx.stderr and "already exists" not in result_tx.stderr.lower():
                    # Don't warn if it's just that the rule already exists
                    if "File exists" not in result_tx.stderr:
                        print(f"Warning: Failed to add TX rule for IP {ip}: {result_tx.stderr}")
        
        # Consider it successful if set was added (rules might already exist)
        if result_set.returncode == 0 or "File exists" in result_set.stderr or "already exists" in result_set.stderr.lower():
            _known_ips.add(ip)
            return True
            
    except Exception as e:
        print(f"Error adding IP {ip} to nftables: {e}")
        import traceback
        traceback.print_exc()
    
    return False


def _read_nftables_counters() -> Dict[str, Dict[str, int]]:
    """Read nftables counter values for all IPs with named counters
    
    Returns:
        Dict[ip_address, {rx_bytes_total, tx_bytes_total}]
    """
    counters = {}
    
    try:
        # First, try listing counters directly
        result = _run_nft([
            "list", "counters", "inet", "router_bandwidth"
        ])
        
        if result.returncode != 0:
            # Try listing the full ruleset to see counters in rules
            result = _run_nft([
                "list", "ruleset", "inet", "router_bandwidth"
            ])
            
            if result.returncode != 0:
                print(f"Warning: nft list failed: {result.stderr}")
                return counters
            
            # Parse counters from ruleset output
            # Format: ip daddr 192.168.1.1 counter name rx_192_168_1_1 packets 1234 bytes 567890
            rx_rule_pattern = r'ip\s+daddr\s+(\d+\.\d+\.\d+\.\d+)\s+counter\s+name\s+rx_\d+_\d+_\d+_\d+\s+packets\s+\d+\s+bytes\s+(\d+)'
            tx_rule_pattern = r'ip\s+saddr\s+(\d+\.\d+\.\d+\.\d+)\s+counter\s+name\s+tx_\d+_\d+_\d+_\d+\s+packets\s+\d+\s+bytes\s+(\d+)'
            
            for line in result.stdout.splitlines():
                rx_match = re.search(rx_rule_pattern, line)
                if rx_match:
                    ip = rx_match.group(1)
                    bytes_val = int(rx_match.group(2))
                    if ip not in counters:
                        counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                    counters[ip]['rx_bytes_total'] = bytes_val
                
                tx_match = re.search(tx_rule_pattern, line)
                if tx_match:
                    ip = tx_match.group(1)
                    bytes_val = int(tx_match.group(2))
                    if ip not in counters:
                        counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                    counters[ip]['tx_bytes_total'] = bytes_val
            
            return counters
        
        # Also try listing ruleset to find counters in rules
        result_ruleset = _run_nft([
            "list", "ruleset", "inet", "router_bandwidth"
        ])
        
        if result_ruleset.returncode == 0:
            # Parse counters from ruleset - look for per-IP rules with named counters
            # Format can be:
            # - Single line: ip daddr 192.168.1.1 counter name rx_192_168_1_1 packets 1234 bytes 567890
            # - Multi-line: ip daddr 192.168.1.1 counter name rx_192_168_1_1 { packets 1234 bytes 567890 }
            # - Or: ip daddr 192.168.1.1 counter name rx_192_168_1_1
            #       packets 1234
            #       bytes 567890
            rx_rule_pattern = r'ip\s+daddr\s+(\d+\.\d+\.\d+\.\d+)\s+counter\s+name\s+rx_(\d+)_(\d+)_(\d+)_(\d+)'
            tx_rule_pattern = r'ip\s+saddr\s+(\d+\.\d+\.\d+\.\d+)\s+counter\s+name\s+tx_(\d+)_(\d+)_(\d+)_(\d+)'
            bytes_pattern = r'bytes\s+(\d+)'
            
            current_ip = None
            current_type = None
            in_counter_block = False
            
            for i, line in enumerate(result_ruleset.stdout.splitlines()):
                line_stripped = line.strip()
                
                # Check for RX rule
                rx_match = re.search(rx_rule_pattern, line_stripped)
                if rx_match:
                    ip = f"{rx_match.group(2)}.{rx_match.group(3)}.{rx_match.group(4)}.{rx_match.group(5)}"
                    current_ip = ip
                    current_type = 'rx'
                    in_counter_block = True
                    if ip not in counters:
                        counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                    
                    # Check if bytes is on same line
                    bytes_match = re.search(bytes_pattern, line_stripped)
                    if bytes_match:
                        bytes_val = int(bytes_match.group(1))
                        counters[ip]['rx_bytes_total'] = bytes_val
                        current_ip = None
                        current_type = None
                        in_counter_block = False
                    continue
                
                # Check for TX rule
                tx_match = re.search(tx_rule_pattern, line_stripped)
                if tx_match:
                    ip = f"{tx_match.group(2)}.{tx_match.group(3)}.{tx_match.group(4)}.{tx_match.group(5)}"
                    current_ip = ip
                    current_type = 'tx'
                    in_counter_block = True
                    if ip not in counters:
                        counters[ip] = {'rx_bytes_total': 0, 'tx_bytes_total': 0}
                    
                    # Check if bytes is on same line
                    bytes_match = re.search(bytes_pattern, line_stripped)
                    if bytes_match:
                        bytes_val = int(bytes_match.group(1))
                        counters[ip]['tx_bytes_total'] = bytes_val
                        current_ip = None
                        current_type = None
                        in_counter_block = False
                    continue
                
                # If we're in a counter block, look for bytes value
                if in_counter_block and current_ip:
                    bytes_match = re.search(bytes_pattern, line_stripped)
                    if bytes_match:
                        bytes_val = int(bytes_match.group(1))
                        if current_type == 'rx':
                            counters[current_ip]['rx_bytes_total'] = bytes_val
                        elif current_type == 'tx':
                            counters[current_ip]['tx_bytes_total'] = bytes_val
                        current_ip = None
                        current_type = None
                        in_counter_block = False
        
        # Parse counter output (if counters were listed separately)
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


# Global state for client rotation (to ensure all clients are processed over time)
_last_processed_index = 0

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
    global _last_processed_index
    
    # Check CPU threshold
    if not _check_cpu_threshold():
        # Log when collection is skipped due to CPU
        cpu_usage = _get_cpu_usage()
        print(f"Bandwidth collection skipped: CPU usage {cpu_usage:.1f}% exceeds threshold {settings.bandwidth_max_cpu_percent}%")
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
        
        # Proactively add all known client IPs to nftables (from ARP and DHCP)
        # This ensures counters are created even before traffic flows
        # Filter to IPv4 only and bridge subnets only (192.168.2.x for br0/homelab, 192.168.3.x for br1/lan)
        all_known_ips = set()
        for ip in arp_table.keys():
            if _is_ipv4(ip):
                # Only track IPs in bridge subnets
                if ip.startswith('192.168.2.') or ip.startswith('192.168.3.'):
                    all_known_ips.add(ip)
        for lease in dhcp_leases:
            if _is_ipv4(lease.ip_address):
                # Only track IPs in bridge subnets
                if lease.ip_address.startswith('192.168.2.') or lease.ip_address.startswith('192.168.3.'):
                    all_known_ips.add(lease.ip_address)
        
        for ip in all_known_ips:
            if ip not in _known_ips:
                _add_ip_to_nftables(ip)
        
        # Read current counter values from nftables
        current_counters = _read_nftables_counters()
        
        # Process clients (limit to max_clients_per_cycle for CPU governance)
        # Use rotation to ensure all clients are processed over time
        processed = 0
        
        # Convert counters dict to list for rotation
        counter_items = list(current_counters.items())
        total_clients = len(counter_items)
        
        # Rotate starting position to process different clients each cycle
        if total_clients > settings.bandwidth_max_clients_per_cycle:
            start_index = _last_processed_index % total_clients
            # Rotate the list to start from last processed position
            counter_items = counter_items[start_index:] + counter_items[:start_index]
        
        # First process IPs with counters (up to max_clients_per_cycle)
        for ip, counter_data in counter_items:
            if processed >= settings.bandwidth_max_clients_per_cycle:
                break
            
            # Only track IPs in bridge subnets
            if not (ip.startswith('192.168.2.') or ip.startswith('192.168.3.')):
                continue
            
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
        
        # Update rotation index for next cycle
        if total_clients > 0:
            _last_processed_index = (_last_processed_index + processed) % total_clients
        
        # Also process IPs that are known but don't have counters yet (no traffic)
        # This ensures we track them even if they haven't sent/received data
        # Convert to list and rotate if needed
        known_ips_list = list(all_known_ips)
        if len(known_ips_list) > settings.bandwidth_max_clients_per_cycle - processed:
            # Rotate known IPs list too
            start_index = _last_processed_index % len(known_ips_list) if len(known_ips_list) > 0 else 0
            known_ips_list = known_ips_list[start_index:] + known_ips_list[:start_index]
        
        for ip in known_ips_list:
            if processed >= settings.bandwidth_max_clients_per_cycle:
                break
            
            # Skip if already processed (has counters)
            if ip in current_counters:
                continue
            
            # Only track IPs in bridge subnets
            if not (ip.startswith('192.168.2.') or ip.startswith('192.168.3.')):
                continue
            
            # Map IP to MAC address
            mac_network = _map_ip_to_mac(ip, arp_table, dhcp_leases)
            if not mac_network:
                continue
            
            mac_address, network = mac_network
            
            # Add entry with zero bytes (no traffic yet)
            results.append({
                'mac_address': mac_address,
                'ip_address': ip,
                'network': network,
                'rx_bytes': 0,
                'tx_bytes': 0,
                'rx_bytes_total': 0,
                'tx_bytes_total': 0,
                'timestamp': current_time
            })
            
            processed += 1
        
        # Clean up old IPs from previous_counters that are no longer active
        active_ips = set(current_counters.keys())
        # Update _previous_counters in place to avoid scoping issues
        for ip in list(_previous_counters.keys()):
            if ip not in active_ips:
                del _previous_counters[ip]
        # Keep known IPs that are still in ARP/DHCP
        _known_ips.intersection_update(all_known_ips)
    
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"Error collecting client bandwidth: {e}")
        print(f"Error details: {error_details}")
        # Return empty list on error to avoid breaking the collection cycle
        return []
    
    return results

