"""
Network devices API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional, Dict
from datetime import datetime
from pydantic import BaseModel
import subprocess
from sqlalchemy import select, or_
from sqlalchemy.sql import cast
from sqlalchemy.types import String
from sqlalchemy.ext.asyncio import AsyncSession
import os

from ..auth import get_current_user
from ..collectors.network_devices import discover_network_devices, get_device_count_by_network
from ..collectors.dhcp import parse_kea_leases
from ..database import AsyncSessionLocal, DeviceOverrideDB, NetworkDeviceDB


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
    nickname: Optional[str] = None
    favorite: bool = False


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
    - Database (historical offline devices)
    
    Returns:
        List[NetworkDevice]: All discovered devices
    """
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)

    # Filter to IPv4 only
    devices = [d for d in devices if _is_ipv4(d.ip_address)]
    
    # Create a set of MAC addresses we already have from discovery
    seen_macs = {d.mac_address.lower() for d in devices}
    
    # Also query database for offline devices that might not be in current discovery
    async with AsyncSessionLocal() as session:
        # Get all devices from database that are in bridge subnets
        # Use cast to string for LIKE comparison with INET type
        result = await session.execute(
            select(NetworkDeviceDB).where(
                or_(
                    cast(NetworkDeviceDB.ip_address, String).like('192.168.2.%'),
                    cast(NetworkDeviceDB.ip_address, String).like('192.168.3.%')
                )
            )
        )
        db_devices = result.scalars().all()
        
        # Add devices from database that we haven't seen yet
        for db_dev in db_devices:
            mac_lower = str(db_dev.mac_address).lower()
            # Only add if IPv4 and not already in discovered devices
            if _is_ipv4(str(db_dev.ip_address)) and mac_lower not in seen_macs:
                # Create a NetworkDevice from database entry
                from ..collectors.network_devices import NetworkDevice as ND
                device = ND(
                    network=db_dev.network,
                    ip_address=str(db_dev.ip_address),
                    mac_address=str(db_dev.mac_address),
                    hostname=db_dev.hostname,
                    vendor=db_dev.vendor,
                    is_dhcp=db_dev.is_dhcp,
                    is_static=db_dev.is_static,
                    is_online=db_dev.is_online,
                    last_seen=db_dev.last_seen,
                )
                devices.append(device)
                seen_macs.add(mac_lower)

    # Load overrides for all MACs
    macs = [d.mac_address for d in devices]
    overrides: Dict[str, DeviceOverrideDB] = {}
    if macs:
        async with AsyncSessionLocal() as session:
            result = await session.execute(select(DeviceOverrideDB).where(DeviceOverrideDB.mac_address.in_(macs)))
            for ov in result.scalars().all():
                overrides[str(ov.mac_address).lower()] = ov

    enriched: List[NetworkDevice] = []
    for device in devices:
        key = device.mac_address.lower()
        ov = overrides.get(key)
        enriched.append(NetworkDevice(
            network=device.network,
            ip_address=device.ip_address,
            mac_address=device.mac_address,
            hostname=device.hostname,
            vendor=device.vendor,
            is_dhcp=device.is_dhcp,
            is_static=device.is_static,
            is_online=device.is_online,
            last_seen=device.last_seen,
            nickname=ov.nickname if ov else None,
            favorite=ov.favorite if ov else False,
        ))

    # Sort: favorites first, then by nickname/hostname
    enriched.sort(key=lambda d: (not d.favorite, (d.nickname or d.hostname or "").lower()))
    return enriched


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
    
    # Filter to IPv4 only and by network
    filtered = [d for d in all_devices if _is_ipv4(d.ip_address) and d.network == network]
    
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


def _find_nft() -> str:
    # Prefer explicit env var (set by NixOS module to /nix/store/... path)
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
    raise HTTPException(status_code=500, detail="nft binary not found")


def _run_nft(args: list[str]) -> None:
    nft = _find_nft()
    try:
        subprocess.run([nft] + args, check=True, capture_output=True, text=True, timeout=3)
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"nft failed: {e.stderr or e.stdout}")
    except FileNotFoundError:
        raise HTTPException(status_code=500, detail="nft command not found")


@router.get("/blocked")
async def list_blocked(_: str = Depends(get_current_user)) -> dict:
    """List blocked devices from nft sets (IPs and MACs)"""
    result = {"ipv4": [], "ipv6": [], "macs": []}
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
    try:
        out_macs = subprocess.run(
            ["nft", "list", "set", "bridge", "router_block_mac", "blocked_macs"],
            capture_output=True, text=True, timeout=2
        )
        if out_macs.returncode == 0:
            for line in out_macs.stdout.splitlines():
                line = line.strip()
                if line.startswith("elements ="):
                    inside = line.split("{",1)[1].split("}",1)[0]
                    items = [i.strip() for i in inside.split(",") if i.strip()]
                    result["macs"] = [i.lower() for i in items]
                    break
    except Exception:
        pass
    return result


@router.post("/block")
async def block_device(req: BlockRequest, _: str = Depends(get_current_user)) -> dict:
    """Block a device by adding MAC and/or IPs to nft sets"""
    if not any([req.ip_address, req.ip6_address, req.mac_address]):
        raise HTTPException(status_code=400, detail="Must supply mac_address or ip_address/ip6_address")

    if req.ip_address:
        _run_nft(["add", "element", "inet", "router_block", "blocked_v4", "{", req.ip_address, "}"])
    if req.ip6_address:
        _run_nft(["add", "element", "inet", "router_block", "blocked_v6", "{", req.ip6_address, "}"])
    if req.mac_address:
        _run_nft(["add", "element", "bridge", "router_block_mac", "blocked_macs", "{", req.mac_address.lower(), "}"])
    return {"status": "blocked", "ipv4": req.ip_address, "ipv6": req.ip6_address, "mac": req.mac_address}


@router.post("/unblock")
async def unblock_device(req: BlockRequest, _: str = Depends(get_current_user)) -> dict:
    """Unblock a device by removing MAC/IPs from nft sets"""
    if not any([req.ip_address, req.ip6_address, req.mac_address]):
        raise HTTPException(status_code=400, detail="Must supply mac_address or ip_address/ip6_address")

    if req.ip_address:
        _run_nft(["delete", "element", "inet", "router_block", "blocked_v4", "{", req.ip_address, "}"])
    if req.ip6_address:
        _run_nft(["delete", "element", "inet", "router_block", "blocked_v6", "{", req.ip6_address, "}"])
    if req.mac_address:
        _run_nft(["delete", "element", "bridge", "router_block_mac", "blocked_macs", "{", req.mac_address.lower(), "}"])
    return {"status": "unblocked", "ipv4": req.ip_address, "ipv6": req.ip6_address, "mac": req.mac_address}


class OverrideRequest(BaseModel):
    mac_address: str
    nickname: Optional[str] = None
    favorite: Optional[bool] = None


@router.get("/overrides")
async def list_overrides(_: str = Depends(get_current_user)) -> List[OverrideRequest]:
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(DeviceOverrideDB))
        rows = result.scalars().all()
        return [OverrideRequest(mac_address=str(r.mac_address), nickname=r.nickname, favorite=r.favorite) for r in rows]


@router.post("/override")
async def upsert_override(req: OverrideRequest, _: str = Depends(get_current_user)) -> dict:
    if not req.mac_address:
        raise HTTPException(status_code=400, detail="mac_address is required")
    async with AsyncSessionLocal() as session:
        # Try find existing
        result = await session.execute(select(DeviceOverrideDB).where(DeviceOverrideDB.mac_address == req.mac_address))
        row = result.scalar_one_or_none()
        if row:
            if req.nickname is not None:
                row.nickname = req.nickname
            if req.favorite is not None:
                row.favorite = bool(req.favorite)
        else:
            row = DeviceOverrideDB(mac_address=req.mac_address, nickname=req.nickname, favorite=bool(req.favorite))
            session.add(row)
        await session.commit()
        return {"status": "ok"}


@router.delete("/override/{mac}")
async def delete_override(mac: str, _: str = Depends(get_current_user)) -> dict:
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(DeviceOverrideDB).where(DeviceOverrideDB.mac_address == mac))
        row = result.scalar_one_or_none()
        if row:
            await session.delete(row)
            await session.commit()
        return {"status": "ok"}

