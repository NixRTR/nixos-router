"""
Device bandwidth collector using nftables counters
"""
import subprocess
import re
import time
from typing import List, Dict, Set
from datetime import datetime

from ..models import DeviceBandwidth
from .dhcp import parse_kea_leases


def get_active_device_ips() -> Set[str]:
    """
    Get all active device IPs from DHCP leases and ARP table

    Returns:
        Set of active IP addresses
    """
    active_ips = set()

    # Get IPs from DHCP leases
    dhcp_leases = parse_kea_leases()
    for lease in dhcp_leases:
        if is_local_ip(lease.ip_address):
            active_ips.add(lease.ip_address)

    # Also try to get IPs from ARP table (for static IPs)
    try:
        result = subprocess.run(
            ['/run/current-system/sw/bin/ip', 'neigh', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 4 and parts[2] == 'lladdr':
                        ip = parts[0]
                        if is_local_ip(ip):
                            active_ips.add(ip)

    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        print(f"Warning: Could not read ARP table: {e}")

    return active_ips


def setup_device_counters():
    """
    Create nftables counters for all active devices
    This should be called periodically to ensure counters exist for new devices
    """
    active_ips = get_active_device_ips()

    try:
        # Ensure the bandwidth_accounting table exists
        subprocess.run([
            'nft', 'add', 'table', 'inet', 'bandwidth_accounting'
        ], capture_output=True, timeout=10)

        # Ensure chains exist
        subprocess.run([
            'nft', 'add', 'chain', 'inet', 'bandwidth_accounting', 'accounting',
            '{', 'type', 'filter', 'hook', 'prerouting', 'priority', 'mangle', ';}'
        ], capture_output=True, timeout=10)

        subprocess.run([
            'nft', 'add', 'chain', 'inet', 'bandwidth_accounting', 'accounting_post',
            '{', 'type', 'filter', 'hook', 'postrouting', 'priority', 'mangle', ';}'
        ], capture_output=True, timeout=10)

        # Get existing counters
        result = subprocess.run([
            'nft', 'list', 'counters', 'table', 'inet', 'bandwidth_accounting'
        ], capture_output=True, text=True, timeout=10)

        existing_counters = set()
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if line.strip().startswith('counter '):
                    parts = line.split()
                    if len(parts) > 1:
                        counter_name = parts[1]
                        existing_counters.add(counter_name)

        # Determine which counters we need
        needed_counters = set()
        for ip in active_ips:
            ip_safe = ip.replace('.', '_')
            needed_counters.add(f'device_{ip_safe}_rx')
            needed_counters.add(f'device_{ip_safe}_tx')

        # Remove counters for devices that are no longer active
        counters_to_remove = existing_counters - needed_counters
        for counter_name in counters_to_remove:
            if counter_name.startswith('device_') and (counter_name.endswith('_rx') or counter_name.endswith('_tx')):
                try:
                    subprocess.run([
                        'nft', 'delete', 'counter', 'inet', 'bandwidth_accounting', counter_name
                    ], capture_output=True, timeout=5)
                except subprocess.SubprocessError:
                    pass  # Ignore errors for counters that might not exist

        # Add counters for new active devices
        counters_to_add = needed_counters - existing_counters
        for counter_name in counters_to_add:
            try:
                subprocess.run([
                    'nft', 'add', 'counter', 'inet', 'bandwidth_accounting', counter_name
                ], capture_output=True, timeout=5)
            except subprocess.SubprocessError as e:
                print(f"Warning: Could not add counter {counter_name}: {e}")

        # Update rules
        update_counter_rules(active_ips)

    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        print(f"Error setting up device counters: {e}")


def update_counter_rules(active_ips: Set[str]):
    """
    Update nftables rules to use the device counters
    """
    try:
        # Flush existing rules
        subprocess.run([
            'nft', 'flush', 'chain', 'inet', 'bandwidth_accounting', 'accounting'
        ], capture_output=True, timeout=5)

        subprocess.run([
            'nft', 'flush', 'chain', 'inet', 'bandwidth_accounting', 'accounting_post'
        ], capture_output=True, timeout=5)

        # Add rules for each active device
        for ip in active_ips:
            ip_safe = ip.replace('.', '_')

            # Prerouting rule (download - traffic coming to device)
            try:
                subprocess.run([
                    'nft', 'add', 'rule', 'inet', 'bandwidth_accounting', 'accounting',
                    'ip', 'daddr', ip, 'counter', 'name', f'device_{ip_safe}_rx'
                ], capture_output=True, timeout=5)
            except subprocess.SubprocessError as e:
                print(f"Warning: Could not add RX rule for {ip}: {e}")

            # Postrouting rule (upload - traffic leaving device)
            try:
                subprocess.run([
                    'nft', 'add', 'rule', 'inet', 'bandwidth_accounting', 'accounting_post',
                    'ip', 'saddr', ip, 'counter', 'name', f'device_{ip_safe}_tx'
                ], capture_output=True, timeout=5)
            except subprocess.SubprocessError as e:
                print(f"Warning: Could not add TX rule for {ip}: {e}")


    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        print(f"Error updating counter rules: {e}")


def get_nftables_counters() -> Dict[str, Dict[str, int]]:
    """
    Read nftables counters for per-device bandwidth accounting

    Returns:
        Dict mapping IP addresses to byte counters
        Format: { '192.168.1.10': {'rx_bytes': 12345, 'tx_bytes': 6789} }
    """
    counters = {}

    try:
        # Get nftables counters
        result = subprocess.run(
            ['nft', 'list', 'counters', 'table', 'inet', 'bandwidth_accounting'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            print(f"Warning: nft command failed: {result.stderr}")
            return counters

        # Parse output
        # Format: counter device_192_168_1_10_rx { packets 123 bytes 45678 }
        for line in result.stdout.strip().split('\n'):
            line = line.strip()
            if not line or not line.startswith('counter device_'):
                continue

            # Extract counter name and bytes
            match = re.search(r'counter (\S+) \{.*bytes (\d+)', line)
            if match:
                counter_name = match.group(1)
                bytes_count = int(match.group(2))

                # Parse counter name: device_192_168_1_10_rx
                if counter_name.startswith('device_') and (counter_name.endswith('_rx') or counter_name.endswith('_tx')):
                    # Extract IP: device_192_168_1_10_rx -> 192.168.1.10
                    ip_part = counter_name[7:-3]  # Remove 'device_' and '_rx'/'_tx'
                    ip = ip_part.replace('_', '.')

                    if not is_local_ip(ip):
                        continue

                    if ip not in counters:
                        counters[ip] = {'rx_bytes': 0, 'tx_bytes': 0}

                    if counter_name.endswith('_rx'):
                        counters[ip]['rx_bytes'] = bytes_count
                    elif counter_name.endswith('_tx'):
                        counters[ip]['tx_bytes'] = bytes_count

    except (subprocess.TimeoutExpired, subprocess.SubprocessError) as e:
        print(f"Error reading nftables counters: {e}")

    return counters


def is_local_ip(ip: str) -> bool:
    """Check if IP address is in our local networks"""
    return (
        ip.startswith('192.168.1.') or  # LAN
        ip.startswith('192.168.2.')     # HOMELAB
    )


def collect_device_bandwidth() -> List[DeviceBandwidth]:
    """
    Collect current device bandwidth rates from iptables counters

    Returns:
        List of DeviceBandwidth objects with current rates
    """
    results = []
    counters = get_iptables_counters()

    # Get current time for rate calculation
    now = datetime.now()

    for ip, counts in counters.items():
        # Determine network from IP
        if ip.startswith('192.168.1.'):
            network = 'lan'
        elif ip.startswith('192.168.2.'):
            network = 'homelab'
        else:
            continue

        # For rate calculation, we'd need previous measurements
        # For now, we'll store raw counters and calculate rates later
        # This is a simplified implementation

        results.append(DeviceBandwidth(
            timestamp=now,
            network=network,
            ip_address=ip,
            mac_address=None,  # Will be filled from DHCP leases
            hostname=None,     # Will be filled from DHCP leases
            rx_bytes_per_sec=counts['rx_bytes'],  # This is actually total bytes
            tx_bytes_per_sec=counts['tx_bytes']   # This is actually total bytes
        ))

    return results


# Global state for rate calculation
_previous_counters = {}
_previous_time = None


def collect_device_bandwidth_rates() -> List[DeviceBandwidth]:
    """
    Collect device bandwidth rates by comparing with previous measurements

    Returns:
        List of DeviceBandwidth objects with calculated rates
    """
    global _previous_counters, _previous_time

    # Setup counters for any new devices (runs periodically)
    setup_device_counters()

    current_counters = get_nftables_counters()
    current_time = time.time()

    results = []

    if _previous_counters and _previous_time:
        time_delta = current_time - _previous_time

        if time_delta > 0:
            for ip in set(current_counters.keys()) | set(_previous_counters.keys()):
                prev = _previous_counters.get(ip, {'rx_bytes': 0, 'tx_bytes': 0})
                curr = current_counters.get(ip, {'rx_bytes': 0, 'tx_bytes': 0})

                # Calculate rates (bytes per second)
                rx_rate = (curr['rx_bytes'] - prev['rx_bytes']) / time_delta
                tx_rate = (curr['tx_bytes'] - prev['tx_bytes']) / time_delta

                # Only include positive rates (counters can reset)
                if rx_rate >= 0 and tx_rate >= 0 and (rx_rate > 0 or tx_rate > 0):
                    # Determine network from IP
                    if ip.startswith('192.168.1.'):
                        network = 'lan'
                    elif ip.startswith('192.168.2.'):
                        network = 'homelab'
                    else:
                        continue

                    results.append(DeviceBandwidth(
                        timestamp=datetime.now(),
                        network=network,
                        ip_address=ip,
                        mac_address=None,  # Will be enriched from DHCP data
                        hostname=None,     # Will be enriched from DHCP data
                        rx_bytes_per_sec=max(0, rx_rate),  # Download rate
                        tx_bytes_per_sec=max(0, tx_rate)   # Upload rate
                    ))

    # Update previous state
    _previous_counters = current_counters.copy()
    _previous_time = current_time

    return results
