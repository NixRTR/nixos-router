"""
Network device discovery collector
Discovers all devices on the network using ARP table and optional active scanning
"""
import subprocess
import re
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
from ..models import DHCPLease
import os
from ..config import settings


class NetworkDevice:
    """Represents a discovered network device"""
    def __init__(
        self,
        network: str,
        ip_address: str,
        mac_address: str,
        hostname: Optional[str] = None,
        is_dhcp: bool = False,
        is_static: bool = False,
        is_online: bool = True,
        last_seen: datetime = None,
        vendor: Optional[str] = None
    ):
        self.network = network
        self.ip_address = ip_address
        self.mac_address = mac_address
        self.hostname = hostname or f"device-{ip_address.split('.')[-1]}"
        self.is_dhcp = is_dhcp
        self.is_static = is_static
        self.is_online = is_online
        self.last_seen = last_seen or datetime.now()
        self.vendor = vendor


def parse_arp_table() -> Dict[str, Dict[str, str]]:
    """Parse system ARP table to find active devices
    
    Returns:
        Dict[ip_address, {mac_address, interface}]
    """
    devices = {}
    
    try:
        # Try using 'ip neigh' (modern Linux). Resolve ip binary path.
        # Prefer explicit env var (NixOS module sets to /nix/store/... path)
        env_ip = os.environ.get("IP_BIN")
        ip_candidates = ([env_ip] if env_ip else []) + [
            '/run/current-system/sw/bin/ip',
            '/usr/sbin/ip',
            '/sbin/ip',
            'ip'
        ]
        ip_bin = None
        for c in ip_candidates:
            try:
                p = subprocess.run([c, '-V'], capture_output=True, text=True, timeout=2)
                if p.returncode == 0:
                    ip_bin = c
                    break
            except Exception:
                continue

        result = None
        if ip_bin:
            result = subprocess.run(
                [ip_bin, 'neigh', 'show'],
                capture_output=True,
                text=True,
                timeout=5
            )
        
        if result and result.returncode == 0:
            # Parse 'ip neigh' output
            # Format: 192.168.2.100 dev br0 lladdr aa:bb:cc:dd:ee:ff REACHABLE
            for line in result.stdout.splitlines():
                parts = line.split()
                if len(parts) >= 5 and 'lladdr' in parts:
                    ip = parts[0]
                    dev_idx = parts.index('dev') + 1 if 'dev' in parts else -1
                    mac_idx = parts.index('lladdr') + 1 if 'lladdr' in parts else -1
                    
                    if dev_idx > 0 and mac_idx > 0:
                        interface = parts[dev_idx]
                        mac = parts[mac_idx]
                        
                        # Only include bridge interfaces (br0, br1) and PPP
                        if interface.startswith('br') or interface.startswith('ppp'):
                            devices[ip] = {
                                'mac_address': mac.lower(),
                                'interface': interface
                            }
    except Exception as e:
        print(f"Error parsing ARP table: {e}")
        
    # Fallback: Try /proc/net/arp
    if not devices:
        try:
            arp_file = Path('/proc/net/arp')
            if arp_file.exists():
                with open(arp_file, 'r') as f:
                    lines = f.readlines()[1:]  # Skip header
                    for line in lines:
                        parts = line.split()
                        if len(parts) >= 6:
                            ip = parts[0]
                            mac = parts[3]
                            interface = parts[5]
                            
                            # Only include bridge interfaces
                            if interface.startswith('br') or interface.startswith('ppp'):
                                devices[ip] = {
                                    'mac_address': mac.lower(),
                                    'interface': interface
                                }
        except Exception as e:
            print(f"Error reading /proc/net/arp: {e}")
    
    return devices


def determine_network(ip_address: str, interface: str) -> str:
    """Determine which network a device belongs to based on IP and interface
    
    Args:
        ip_address: IP address of device
        interface: Network interface (br0, br1, etc.)
        
    Returns:
        'homelab' or 'lan'
    """
    # Based on IP range
    if ip_address.startswith('192.168.2.'):
        return 'homelab'
    elif ip_address.startswith('192.168.3.'):
        return 'lan'
    
    # Fallback to interface mapping
    if interface == 'br0':
        return 'homelab'
    elif interface == 'br1':
        return 'lan'
    
    # Default
    return 'homelab'


def lookup_mac_vendor(mac_address: str) -> Optional[str]:
    """Look up vendor from MAC address OUI (first 3 octets)
    
    This is a simple implementation. For production, consider using:
    - manuf Python library
    - IEEE OUI database
    - Local OUI cache file
    
    Args:
        mac_address: MAC address (format: aa:bb:cc:dd:ee:ff)
        
    Returns:
        Vendor name or None
    """
    # Common vendor OUIs (expand as needed)
    oui_vendors = {
        '00:07:a6': 'Leviton',
        'd8:a0:11': 'WiZ Connected',
        '48:a2:e6': 'Ubiquiti',
        'e8:9f:80': 'Ubiquiti',
        '10:d5:61': 'Espressif',
        '70:b8:f6': 'Universal Electronics',
        '6c:29:90': 'WiZ Connected',
        '84:7a:b6': 'Honeywell',
    }
    
    if not mac_address or len(mac_address) < 8:
        return None
    
    # Extract OUI (first 3 octets)
    oui = ':'.join(mac_address.split(':')[:3]).lower()
    
    return oui_vendors.get(oui)


def discover_network_devices(dhcp_leases: List[DHCPLease] = None) -> List[NetworkDevice]:
    """Discover all devices on the network
    
    Combines:
    - ARP table entries (active devices)
    - DHCP lease data (known DHCP clients)
    
    Args:
        dhcp_leases: Optional list of DHCP leases to merge
        
    Returns:
        List of NetworkDevice objects
    """
    devices = []
    seen_macs = set()
    
    # Parse ARP table for active devices
    arp_devices = parse_arp_table()
    
    # Create DHCP lease lookup by MAC
    dhcp_by_mac = {}
    dhcp_by_ip = {}
    if dhcp_leases:
        for lease in dhcp_leases:
            dhcp_by_mac[lease.mac_address.lower()] = lease
            dhcp_by_ip[lease.ip_address] = lease
    
    # Process ARP table entries
    for ip, arp_data in arp_devices.items():
        mac = arp_data['mac_address']
        interface = arp_data['interface']
        network = determine_network(ip, interface)
        
        # Check if this device has a DHCP lease
        dhcp_lease = dhcp_by_mac.get(mac) or dhcp_by_ip.get(ip)
        
        hostname = None
        is_dhcp = False
        is_static = False
        
        if dhcp_lease:
            hostname = dhcp_lease.hostname
            is_dhcp = True
            is_static = dhcp_lease.is_static
        
        # Look up vendor
        vendor = lookup_mac_vendor(mac)
        
        device = NetworkDevice(
            network=network,
            ip_address=ip,
            mac_address=mac,
            hostname=hostname,
            is_dhcp=is_dhcp,
            is_static=is_static,
            is_online=True,
            last_seen=datetime.now(),
            vendor=vendor
        )
        
        devices.append(device)
        seen_macs.add(mac)
    
    # Add DHCP leases that aren't in ARP table (offline devices)
    if dhcp_leases:
        for lease in dhcp_leases:
            if lease.mac_address.lower() not in seen_macs:
                vendor = lookup_mac_vendor(lease.mac_address)
                
                device = NetworkDevice(
                    network=lease.network,
                    ip_address=lease.ip_address,
                    mac_address=lease.mac_address,
                    hostname=lease.hostname,
                    is_dhcp=True,
                    is_static=lease.is_static,
                    is_online=False,  # Not in ARP = offline
                    last_seen=lease.last_seen,
                    vendor=vendor
                )
                
                devices.append(device)
    
    return devices


def get_device_count_by_network() -> Dict[str, Dict[str, int]]:
    """Get device counts by network
    
    Returns:
        Dict with counts: {
            'homelab': {'total': 10, 'online': 8, 'dhcp': 7},
            'lan': {'total': 5, 'online': 4, 'dhcp': 3}
        }
    """
    from .dhcp import parse_kea_leases
    
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)
    
    counts = {
        'homelab': {'total': 0, 'online': 0, 'dhcp': 0},
        'lan': {'total': 0, 'online': 0, 'dhcp': 0}
    }
    
    for device in devices:
        if device.network in counts:
            counts[device.network]['total'] += 1
            if device.is_online:
                counts[device.network]['online'] += 1
            if device.is_dhcp:
                counts[device.network]['dhcp'] += 1
    
    return counts

