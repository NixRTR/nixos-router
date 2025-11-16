"""
Device bandwidth collector using iptables counters
"""
import subprocess
import re
import time
from typing import List, Dict, Optional
from datetime import datetime

from ..models import DeviceBandwidth


def get_nftables_counters() -> Dict[str, Dict[str, int]]:
    """
    Read nftables counters for per-device bandwidth accounting

    Returns:
        Dict mapping network ranges to byte counters
        Format: { 'lan': {'rx_bytes': 12345, 'tx_bytes': 6789}, 'homelab': {...} }
    """
    counters = {}

    try:
        # Get nftables counters from bandwidth_accounting table
        result = subprocess.run(
            ['nft', 'list', 'counters', 'table', 'inet', 'bandwidth_accounting'],
            capture_output=True,
            text=True,
            timeout=10
        )

        print(f"DEBUG: nft command result: {result.returncode}")
        print(f"DEBUG: nft stdout: {result.stdout}")
        if result.stderr:
            print(f"DEBUG: nft stderr: {result.stderr}")

        if result.returncode != 0:
            print(f"Warning: nft command failed: {result.stderr}")
            return counters

        lines = result.stdout.strip().split('\n')
        print(f"DEBUG: nft output lines: {len(lines)}")

        # Parse nftables output
        # Format: table inet bandwidth_accounting {
        #         counter lan_rx { packets 123 bytes 45678 }
        #         counter lan_tx { packets 456 bytes 78901 }
        #         ...
        # }

        for line in lines:
            print(f"DEBUG: parsing line: {line.strip()}")
            line = line.strip()

            # Look for counter lines
            if line.startswith('counter '):
                # Parse: counter lan_rx { packets 123 bytes 45678 }
                parts = line.split()
                if len(parts) >= 4 and parts[2] == '{':
                    counter_name = parts[1]
                    # Find bytes value
                    bytes_match = re.search(r'bytes (\d+)', line)
                    if bytes_match:
                        bytes_count = int(bytes_match.group(1))
                        print(f"DEBUG: Found counter {counter_name} with {bytes_count} bytes")

                        # Map counter names to our format
                        if counter_name == 'lan_rx':
                            counters['lan'] = counters.get('lan', {'rx_bytes': 0, 'tx_bytes': 0})
                            counters['lan']['rx_bytes'] = bytes_count
                        elif counter_name == 'lan_tx':
                            counters['lan'] = counters.get('lan', {'rx_bytes': 0, 'tx_bytes': 0})
                            counters['lan']['tx_bytes'] = bytes_count
                        elif counter_name == 'homelab_rx':
                            counters['homelab'] = counters.get('homelab', {'rx_bytes': 0, 'tx_bytes': 0})
                            counters['homelab']['rx_bytes'] = bytes_count
                        elif counter_name == 'homelab_tx':
                            counters['homelab'] = counters.get('homelab', {'rx_bytes': 0, 'tx_bytes': 0})
                            counters['homelab']['tx_bytes'] = bytes_count

    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError) as e:
        print(f"Error reading nftables counters: {e}")

    print(f"DEBUG: Final counters: {counters}")
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

    print("DEBUG: Starting collect_device_bandwidth_rates")
    current_counters = get_nftables_counters()
    current_time = time.time()
    print(f"DEBUG: Current counters: {current_counters}")

    results = []

    if _previous_counters and _previous_time:
        print("DEBUG: Have previous data, calculating rates")
        time_delta = current_time - _previous_time
        print(f"DEBUG: Time delta: {time_delta} seconds")

        if time_delta > 0:
            for network in set(current_counters.keys()) | set(_previous_counters.keys()):
                prev = _previous_counters.get(network, {'rx_bytes': 0, 'tx_bytes': 0})
                curr = current_counters.get(network, {'rx_bytes': 0, 'tx_bytes': 0})

                # Calculate rates (bytes per second)
                rx_rate = (curr['rx_bytes'] - prev['rx_bytes']) / time_delta
                tx_rate = (curr['tx_bytes'] - prev['tx_bytes']) / time_delta

                print(f"DEBUG: Network {network}: prev_rx={prev['rx_bytes']}, curr_rx={curr['rx_bytes']}, rx_rate={rx_rate}")
                print(f"DEBUG: Network {network}: prev_tx={prev['tx_bytes']}, curr_tx={curr['tx_bytes']}, tx_rate={tx_rate}")

                # Only include positive rates (counters can reset)
                if rx_rate >= 0 and tx_rate >= 0 and (rx_rate > 0 or tx_rate > 0):
                    print(f"DEBUG: Including network {network} with rates rx={rx_rate}, tx={tx_rate}")

                    # For now, create a dummy device entry for the network
                    # TODO: In the future, we should track per-device counters
                    results.append(DeviceBandwidth(
                        timestamp=datetime.now(),
                        network=network,
                        ip_address=f"192.168.{1 if network == 'lan' else 2}.0",  # Dummy IP for network
                        mac_address=None,
                        hostname=f"{network.upper()} Network",  # Dummy hostname
                        rx_bytes_per_sec=max(0, rx_rate),
                        tx_bytes_per_sec=max(0, tx_rate)
                    ))
                else:
                    print(f"DEBUG: Skipping network {network} - no positive rates (rx={rx_rate}, tx={tx_rate})")
        else:
            print(f"DEBUG: Time delta <= 0: {time_delta}")
    else:
        print("DEBUG: No previous data available, skipping rate calculation")

    # Update previous state
    _previous_counters = current_counters.copy()
    _previous_time = current_time
    print(f"DEBUG: Updated previous state. Results count: {len(results)}")

    return results
