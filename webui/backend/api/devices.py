"""
Network devices API endpoints
"""
from fastapi import APIRouter, Depends
from typing import List
from datetime import datetime
from pydantic import BaseModel

from ..auth import get_current_user
from ..collectors.network_devices import discover_network_devices, get_device_count_by_network
from ..collectors.dhcp import parse_kea_leases


router = APIRouter(prefix="/api/devices", tags=["devices"])


class NetworkDevice(BaseModel):
    """Network device information"""
    network: str
    ip_address: str
    mac_address: str
    hostname: str
    vendor: str | None = None
    is_dhcp: bool
    is_static: bool
    is_online: bool
    last_seen: datetime


class DeviceCounts(BaseModel):
    """Device counts by network"""
    network: str
    total: int
    online: int
    dhcp: int
    static: int


@router.get("/all")
async def get_all_devices(
    _: str = Depends(get_current_user)
) -> List[NetworkDevice]:
    """Get all discovered network devices
    
    Returns devices from:
    - ARP table (currently active)
    - DHCP leases (known clients)
    
    Returns:
        List[NetworkDevice]: All discovered devices
    """
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)
    
    return [
        NetworkDevice(
            network=device.network,
            ip_address=device.ip_address,
            mac_address=device.mac_address,
            hostname=device.hostname,
            vendor=device.vendor,
            is_dhcp=device.is_dhcp,
            is_static=device.is_static,
            is_online=device.is_online,
            last_seen=device.last_seen
        )
        for device in devices
    ]


@router.get("/counts")
async def get_device_counts(
    _: str = Depends(get_current_user)
) -> List[DeviceCounts]:
    """Get device counts by network
    
    Returns:
        List[DeviceCounts]: Device counts for each network
    """
    counts = get_device_count_by_network()
    
    result = []
    for network, data in counts.items():
        result.append(DeviceCounts(
            network=network,
            total=data['total'],
            online=data['online'],
            dhcp=data['dhcp'],
            static=data['total'] - data['dhcp']
        ))
    
    return result


@router.get("/by-network/{network}")
async def get_devices_by_network(
    network: str,
    _: str = Depends(get_current_user)
) -> List[NetworkDevice]:
    """Get devices for a specific network
    
    Args:
        network: Network name ('homelab' or 'lan')
        
    Returns:
        List[NetworkDevice]: Devices on the specified network
    """
    dhcp_leases = parse_kea_leases()
    all_devices = discover_network_devices(dhcp_leases)
    
    # Filter by network
    filtered = [d for d in all_devices if d.network == network]
    
    return [
        NetworkDevice(
            network=device.network,
            ip_address=device.ip_address,
            mac_address=device.mac_address,
            hostname=device.hostname,
            vendor=device.vendor,
            is_dhcp=device.is_dhcp,
            is_static=device.is_static,
            is_online=device.is_online,
            last_seen=device.last_seen
        )
        for device in filtered
    ]

