"""
Device bandwidth collector using iptables counters
"""
import subprocess
import re
import time
from typing import List, Dict, Optional
from datetime import datetime

from ..models import DeviceBandwidth


def get_iptables_counters() -> Dict[str, Dict[str, int]]:
    """
    Read iptables counters for per-device bandwidth accounting

    Returns:
        Dict mapping IP addresses to byte counters
        Format: { '192.168.1.10': {'rx_bytes': 12345, 'tx_bytes': 6789} }
    """
    counters = {}

    try:
        # Get iptables counters from DEVICE_ACCOUNTING chain
        # This will show us bytes per IP address
        result = subprocess.run(
            ['iptables', '-t', 'mangle', '-nvx', '-L', 'DEVICE_ACCOUNTING'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            print(f"Warning: iptables command failed: {result.stderr}")
            return counters

        lines = result.stdout.strip().split('\n')

        # Parse iptables output
        # Format: pkts bytes target prot opt in out source destination
        for line in lines:
            if not line.strip() or 'source' in line.lower():
                continue

            # Split by whitespace, handling multiple spaces
            parts = re.split(r'\s+', line.strip())

            if len(parts) >= 8:
                try:
                    pkts = int(parts[0])
                    bytes_count = int(parts[1])
                    source_ip = parts[7] if len(parts) > 7 else None
                    dest_ip = parts[8] if len(parts) > 8 else None

                    # Track download (incoming to device)
                    if dest_ip and is_local_ip(dest_ip):
                        if dest_ip not in counters:
                            counters[dest_ip] = {'rx_bytes': 0, 'tx_bytes': 0}
                        counters[dest_ip]['rx_bytes'] += bytes_count

                    # Track upload (outgoing from device)
                    if source_ip and is_local_ip(source_ip):
                        if source_ip not in counters:
                            counters[source_ip] = {'rx_bytes': 0, 'tx_bytes': 0}
                        counters[source_ip]['tx_bytes'] += bytes_count

                except (ValueError, IndexError) as e:
                    continue

    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError) as e:
        print(f"Error reading iptables counters: {e}")

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

    current_counters = get_iptables_counters()
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
