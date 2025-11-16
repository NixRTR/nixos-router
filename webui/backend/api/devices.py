"""
Network devices API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional, Dict
from datetime import datetime
from pydantic import BaseModel
import subprocess
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth import get_current_user
from ..collectors.network_devices import discover_network_devices, get_device_count_by_network
from ..collectors.dhcp import parse_kea_leases
from ..database import AsyncSessionLocal, DeviceOverrideDB


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
    
    Returns:
        List[NetworkDevice]: All discovered devices
    """
    dhcp_leases = parse_kea_leases()
    devices = discover_network_devices(dhcp_leases)

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


def _find_nft() -> str:
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

