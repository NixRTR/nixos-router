"""
Network devices API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel
import subprocess

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


class BlockRequest(BaseModel):
    """Request payload for blocking/unblocking a device"""
    ip_address: Optional[str] = None
    ip6_address: Optional[str] = None
    mac_address: Optional[str] = None


def _run_nft(args: list[str]) -> None:
    try:
        subprocess.run(["nft"] + args, check=True, capture_output=True, text=True, timeout=3)
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"nft failed: {e.stderr or e.stdout}")
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="nft command not found")


@router.get("/blocked")
async def list_blocked(_: str = Depends(get_current_user)) -> dict:
    """List blocked devices from nft sets"""
    result = {"ipv4": [], "ipv6": []}
    try:
        out_v4 = subprocess.run(
            ["nft", "list", "set", "inet", "router_block", "blocked_v4"],
            capture_output=True, text=True, timeout=2
        )
        if out_v4.returncode == 0:
            # Parse elements = { 192.168.1.2, 192.168.1.3 }
            for line in out_v4.stdout.splitlines():
                line = line.strip()
                if line.startswith("elements ="):
                    inside = line.split("{",1)[1].split("}",1)[0]
                    items = [i.strip() for i in inside.split(",") if i.strip()]
                    result["ipv4"] = items
                    break
    except Exception:
        pass
    try:
        out_v6 = subprocess.run(
            ["nft", "list", "set", "inet", "router_block", "blocked_v6"],
            capture_output=True, text=True, timeout=2
        )
        if out_v6.returncode == 0:
            for line in out_v6.stdout.splitlines():
                line = line.strip()
                if line.startswith("elements ="):
                    inside = line.split("{",1)[1].split("}",1)[0]
                    items = [i.strip() for i in inside.split(",") if i.strip()]
                    result["ipv6"] = items
                    break
    except Exception:
        pass
    return result


@router.post("/block")
async def block_device(req: BlockRequest, _: str = Depends(get_current_user)) -> dict:
    """Block a device by adding IPs to nft sets"""
    if not any([req.ip_address, req.ip6_address]):
        raise HTTPException(status_code=400, detail="Must supply ip_address or ip6_address")

    if req.ip_address:
        _run_nft(["add", "element", "inet", "router_block", "blocked_v4", "{", req.ip_address, "}"])
    if req.ip6_address:
        _run_nft(["add", "element", "inet", "router_block", "blocked_v6", "{", req.ip6_address, "}"])
    return {"status": "blocked", "ipv4": req.ip_address, "ipv6": req.ip6_address}


@router.post("/unblock")
async def unblock_device(req: BlockRequest, _: str = Depends(get_current_user)) -> dict:
    """Unblock a device by removing IPs from nft sets"""
    if not any([req.ip_address, req.ip6_address]):
        raise HTTPException(status_code=400, detail="Must supply ip_address or ip6_address")

    if req.ip_address:
        _run_nft(["delete", "element", "inet", "router_block", "blocked_v4", "{", req.ip_address, "}"])
    if req.ip6_address:
        _run_nft(["delete", "element", "inet", "router_block", "blocked_v6", "{", req.ip6_address, "}"])
    return {"status": "unblocked", "ipv4": req.ip_address, "ipv6": req.ip6_address}

