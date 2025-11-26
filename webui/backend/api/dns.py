"""
DNS management API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
import subprocess
import shutil
import os
import re
import logging

from ..database import get_db, DnsZoneDB, DnsRecordDB
from ..models import (
    DnsZone, DnsZoneCreate, DnsZoneUpdate,
    DnsRecord, DnsRecordCreate, DnsRecordUpdate
)
from ..api.auth import get_current_user
from ..collectors.services import get_service_status

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dns", tags=["dns"])

# Map network names to systemd service names
NETWORK_SERVICE_MAP = {
    'homelab': 'unbound-homelab',
    'lan': 'unbound-lan',
}


def _find_dbus_send() -> str:
    """Find dbus-send binary path (NixOS way)"""
    logger.debug("Finding dbus-send binary...")
    
    # Check environment variable first (set by NixOS service)
    env_path = os.environ.get("DBUS_SEND_BIN")
    if env_path and os.path.exists(env_path):
        logger.debug(f"Found dbus-send via DBUS_SEND_BIN env var: {env_path}")
        return env_path
    
    # Try shutil.which first (uses PATH)
    dbus_path = shutil.which('dbus-send')
    if dbus_path:
        logger.debug(f"Found dbus-send via PATH: {dbus_path}")
        return dbus_path
    
    # Try common NixOS paths
    candidates = [
        '/run/current-system/sw/bin/dbus-send',
        '/usr/bin/dbus-send',
        '/bin/dbus-send',
    ]
    
    for path in candidates:
        if os.path.exists(path) and os.access(path, os.X_OK):
            logger.debug(f"Found dbus-send at: {path}")
            return path
    
    logger.error("dbus-send binary not found in any location")
    raise RuntimeError("dbus-send binary not found. Please ensure dbus is installed.")


def _get_service_status_via_dbus(service_name: str) -> dict:
    """Get systemd service status via D-Bus (doesn't require sudo)
    
    Args:
        service_name: Name of the service (e.g., "unbound-homelab.service")
        
    Returns:
        Dictionary with is_active, is_enabled, and other status info
    """
    dbus_send = _find_dbus_send()
    
    # Escape service name for D-Bus object path
    # D-Bus object paths escape: . -> _2e, - -> _2d, \ -> _5c
    escaped_name = service_name.replace('\\', '_5c').replace('-', '_2d').replace('.', '_2e')
    unit_path = f"/org/freedesktop/systemd1/unit/{escaped_name}"
    
    # Get ActiveState property (active, inactive, activating, deactivating, failed)
    result = subprocess.run(
        [
            dbus_send,
            '--system',
            '--type=method_call',
            '--print-reply',
            '--dest=org.freedesktop.systemd1',
            unit_path,
            'org.freedesktop.DBus.Properties.Get',
            'string:org.freedesktop.systemd1.Unit',
            'string:ActiveState'
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=False
    )
    
    is_active = False
    if result.returncode == 0:
        # Parse the response: variant string "active"
        active_state = result.stdout.strip()
        if 'string "active"' in active_state or 'string "activating"' in active_state:
            is_active = True
    
    # Get UnitFileState property (enabled, disabled, static, etc.)
    result = subprocess.run(
        [
            dbus_send,
            '--system',
            '--type=method_call',
            '--print-reply',
            '--dest=org.freedesktop.systemd1',
            unit_path,
            'org.freedesktop.DBus.Properties.Get',
            'string:org.freedesktop.systemd1.Unit',
            'string:UnitFileState'
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=False
    )
    
    is_enabled = False
    if result.returncode == 0:
        # Parse the response: variant string "enabled"
        unit_file_state = result.stdout.strip()
        if 'string "enabled"' in unit_file_state:
            is_enabled = True
    
    # Get MainPID property
    result = subprocess.run(
        [
            dbus_send,
            '--system',
            '--type=method_call',
            '--print-reply',
            '--dest=org.freedesktop.systemd1',
            unit_path,
            'org.freedesktop.DBus.Properties.Get',
            'string:org.freedesktop.systemd1.Unit',
            'string:MainPID'
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=False
    )
    
    pid = None
    if result.returncode == 0:
        # Parse the response: variant uint32 12345
        match = re.search(r'uint32 (\d+)', result.stdout)
        if match:
            pid_val = int(match.group(1))
            if pid_val > 0:
                pid = pid_val
    
    return {
        'is_active': is_active,
        'is_enabled': is_enabled,
        'pid': pid
    }


def _control_service_via_dbus(service_name: str, action: str) -> None:
    """Control a systemd service via D-Bus (doesn't require sudo)
    
    Args:
        service_name: Name of the service (e.g., "unbound-homelab.service")
        action: Action to perform ("start", "stop", "restart", "reload")
        
    Raises:
        subprocess.CalledProcessError: If the D-Bus call fails
    """
    logger.debug(f"Controlling service via D-Bus: {service_name}, action: {action}")
    dbus_send = _find_dbus_send()
    
    # Map action names to systemd Manager D-Bus method names
    manager_method_map = {
        'start': 'StartUnit',
        'stop': 'StopUnit',
        'restart': 'RestartUnit',
        'reload': 'ReloadUnit',
    }
    
    manager_method = manager_method_map.get(action.lower())
    if not manager_method:
        logger.error(f"Invalid action: {action}")
        raise ValueError(f"Invalid action: {action}")
    
    logger.debug(f"Mapped action '{action}' to Manager method '{manager_method}'")
    
    # Use systemd Manager interface to control the unit
    # Format: dbus-send --system --dest=org.freedesktop.systemd1 \
    #   /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager.StartUnit \
    #   string:unbound-homelab.service string:replace
    # Methods: StartUnit, StopUnit, RestartUnit, ReloadUnit
    # All take: (unit_name, mode) where mode is "replace", "fail", etc.
    
    cmd = [
        dbus_send,
        '--system',
        '--type=method_call',
        '--print-reply',
        '--dest=org.freedesktop.systemd1',
        '/org/freedesktop/systemd1',
        f'org.freedesktop.systemd1.Manager.{manager_method}',
        f'string:{service_name}',
        'string:replace'  # Mode: replace existing job if any
    ]
    logger.debug(f"Executing D-Bus command: {' '.join(cmd)}")
    
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        check=True
    )
    
    logger.debug(f"D-Bus command succeeded - stdout: {result.stdout[:500]}, stderr: {result.stderr[:500]}")


@router.get("/zones", response_model=List[DnsZone])
async def get_zones(
    network: Optional[str] = None,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> List[DnsZone]:
    """Get list of DNS zones
    
    Args:
        network: Optional filter by network ("homelab" or "lan")
        
    Returns:
        List of DNS zones
    """
    query = select(DnsZoneDB)
    if network:
        if network not in ['homelab', 'lan']:
            raise HTTPException(status_code=400, detail="Network must be 'homelab' or 'lan'")
        query = query.where(DnsZoneDB.network == network)
    
    query = query.order_by(DnsZoneDB.network, DnsZoneDB.name)
    result = await db.execute(query)
    zones = result.scalars().all()
    
    return [DnsZone.model_validate(zone) for zone in zones]


@router.post("/zones", response_model=DnsZone)
async def create_zone(
    zone: DnsZoneCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsZone:
    """Create a new DNS zone
    
    Args:
        zone: Zone creation data
        
    Returns:
        Created zone
    """
    # Check if zone with same name and network already exists
    result = await db.execute(
        select(DnsZoneDB).where(
            DnsZoneDB.name == zone.name,
            DnsZoneDB.network == zone.network
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Zone {zone.name} already exists for network {zone.network}"
        )
    
    db_zone = DnsZoneDB(
        name=zone.name,
        network=zone.network,
        authoritative=zone.authoritative,
        forward_to=zone.forward_to,
        delegate_to=zone.delegate_to,
        enabled=zone.enabled,
        original_config_path=zone.original_config_path
    )
    db.add(db_zone)
    await db.commit()
    await db.refresh(db_zone)
    
    return DnsZone.model_validate(db_zone)


@router.get("/zones/{zone_id}", response_model=DnsZone)
async def get_zone(
    zone_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsZone:
    """Get a specific DNS zone by ID
    
    Args:
        zone_id: Zone ID
        
    Returns:
        Zone details
    """
    result = await db.execute(
        select(DnsZoneDB).where(DnsZoneDB.id == zone_id)
    )
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=404,
            detail=f"Zone {zone_id} not found"
        )
    
    return DnsZone.model_validate(zone)


@router.put("/zones/{zone_id}", response_model=DnsZone)
async def update_zone(
    zone_id: int,
    zone_update: DnsZoneUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsZone:
    """Update a DNS zone
    
    Args:
        zone_id: Zone ID
        zone_update: Zone update data
        
    Returns:
        Updated zone
    """
    result = await db.execute(
        select(DnsZoneDB).where(DnsZoneDB.id == zone_id)
    )
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=404,
            detail=f"Zone {zone_id} not found"
        )
    
    # Check for name/network conflict if updating name or network
    if zone_update.name is not None or zone_update.network is not None:
        new_name = zone_update.name if zone_update.name is not None else zone.name
        new_network = zone_update.network if zone_update.network is not None else zone.network
        
        if new_name != zone.name or new_network != zone.network:
            result = await db.execute(
                select(DnsZoneDB).where(
                    DnsZoneDB.name == new_name,
                    DnsZoneDB.network == new_network,
                    DnsZoneDB.id != zone_id
                )
            )
            existing = result.scalar_one_or_none()
            if existing:
                raise HTTPException(
                    status_code=400,
                    detail=f"Zone {new_name} already exists for network {new_network}"
                )
    
    # Update fields
    if zone_update.name is not None:
        zone.name = zone_update.name
    if zone_update.network is not None:
        zone.network = zone_update.network
    if zone_update.authoritative is not None:
        zone.authoritative = zone_update.authoritative
    if zone_update.forward_to is not None:
        zone.forward_to = zone_update.forward_to
    if zone_update.delegate_to is not None:
        zone.delegate_to = zone_update.delegate_to
    if zone_update.enabled is not None:
        zone.enabled = zone_update.enabled
    
    await db.commit()
    await db.refresh(zone)
    
    return DnsZone.model_validate(zone)


@router.delete("/zones/{zone_id}")
async def delete_zone(
    zone_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> dict:
    """Delete a DNS zone (cascades to records)
    
    Args:
        zone_id: Zone ID
        
    Returns:
        Success message
    """
    result = await db.execute(
        select(DnsZoneDB).where(DnsZoneDB.id == zone_id)
    )
    zone = result.scalar_one_or_none()
    
    if not zone:
        raise HTTPException(
            status_code=404,
            detail=f"Zone {zone_id} not found"
        )
    
    await db.delete(zone)
    await db.commit()
    
    return {"message": f"Zone {zone_id} deleted successfully"}


@router.get("/zones/{zone_id}/records", response_model=List[DnsRecord])
async def get_zone_records(
    zone_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> List[DnsRecord]:
    """Get all records for a zone
    
    Args:
        zone_id: Zone ID
        
    Returns:
        List of DNS records
    """
    # Verify zone exists
    result = await db.execute(
        select(DnsZoneDB).where(DnsZoneDB.id == zone_id)
    )
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(
            status_code=404,
            detail=f"Zone {zone_id} not found"
        )
    
    result = await db.execute(
        select(DnsRecordDB)
        .where(DnsRecordDB.zone_id == zone_id)
        .order_by(DnsRecordDB.type, DnsRecordDB.name)
    )
    records = result.scalars().all()
    
    return [DnsRecord.model_validate(record) for record in records]


@router.post("/zones/{zone_id}/records", response_model=DnsRecord)
async def create_record(
    zone_id: int,
    record: DnsRecordCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsRecord:
    """Create a new DNS record in a zone
    
    Args:
        zone_id: Zone ID
        record: Record creation data (zone_id in record is ignored, uses path param)
        
    Returns:
        Created record
    """
    # Verify zone exists
    result = await db.execute(
        select(DnsZoneDB).where(DnsZoneDB.id == zone_id)
    )
    zone = result.scalar_one_or_none()
    if not zone:
        raise HTTPException(
            status_code=404,
            detail=f"Zone {zone_id} not found"
        )
    
    # Validate record type
    if record.type not in ['A', 'CNAME']:
        raise HTTPException(
            status_code=400,
            detail="Record type must be 'A' or 'CNAME'"
        )
    
    # Validate A record value (must be IP address)
    if record.type == 'A':
        import ipaddress
        try:
            ipaddress.IPv4Address(record.value)
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail="A record value must be a valid IPv4 address"
            )
    
    db_record = DnsRecordDB(
        zone_id=zone_id,
        name=record.name,
        type=record.type,
        value=record.value,
        comment=record.comment,
        enabled=record.enabled,
        original_config_path=record.original_config_path
    )
    db.add(db_record)
    await db.commit()
    await db.refresh(db_record)
    
    return DnsRecord.model_validate(db_record)


@router.get("/records/{record_id}", response_model=DnsRecord)
async def get_record(
    record_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsRecord:
    """Get a specific DNS record by ID
    
    Args:
        record_id: Record ID
        
    Returns:
        Record details
    """
    result = await db.execute(
        select(DnsRecordDB).where(DnsRecordDB.id == record_id)
    )
    record = result.scalar_one_or_none()
    
    if not record:
        raise HTTPException(
            status_code=404,
            detail=f"Record {record_id} not found"
        )
    
    return DnsRecord.model_validate(record)


@router.put("/records/{record_id}", response_model=DnsRecord)
async def update_record(
    record_id: int,
    record_update: DnsRecordUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> DnsRecord:
    """Update a DNS record
    
    Args:
        record_id: Record ID
        record_update: Record update data
        
    Returns:
        Updated record
    """
    result = await db.execute(
        select(DnsRecordDB).where(DnsRecordDB.id == record_id)
    )
    record = result.scalar_one_or_none()
    
    if not record:
        raise HTTPException(
            status_code=404,
            detail=f"Record {record_id} not found"
        )
    
    # If moving to a different zone, verify it exists
    if record_update.zone_id is not None and record_update.zone_id != record.zone_id:
        result = await db.execute(
            select(DnsZoneDB).where(DnsZoneDB.id == record_update.zone_id)
        )
        new_zone = result.scalar_one_or_none()
        if not new_zone:
            raise HTTPException(
                status_code=404,
                detail=f"Zone {record_update.zone_id} not found"
            )
        record.zone_id = record_update.zone_id
    
    # Validate record type if changing
    if record_update.type is not None:
        if record_update.type not in ['A', 'CNAME']:
            raise HTTPException(
                status_code=400,
                detail="Record type must be 'A' or 'CNAME'"
            )
        record.type = record_update.type
    
    # Validate A record value if changing
    if record_update.value is not None:
        record_type = record_update.type if record_update.type is not None else record.type
        if record_type == 'A':
            import ipaddress
            try:
                ipaddress.IPv4Address(record_update.value)
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail="A record value must be a valid IPv4 address"
                )
        record.value = record_update.value
    
    # Update other fields
    if record_update.name is not None:
        record.name = record_update.name
    if record_update.comment is not None:
        record.comment = record_update.comment
    if record_update.enabled is not None:
        record.enabled = record_update.enabled
    
    await db.commit()
    await db.refresh(record)
    
    return DnsRecord.model_validate(record)


@router.delete("/records/{record_id}")
async def delete_record(
    record_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> dict:
    """Delete a DNS record
    
    Args:
        record_id: Record ID
        
    Returns:
        Success message
    """
    result = await db.execute(
        select(DnsRecordDB).where(DnsRecordDB.id == record_id)
    )
    record = result.scalar_one_or_none()
    
    if not record:
        raise HTTPException(
            status_code=404,
            detail=f"Record {record_id} not found"
        )
    
    await db.delete(record)
    await db.commit()
    
    return {"message": f"Record {record_id} deleted successfully"}


@router.get("/service-status/{network}")
async def get_dns_service_status(
    network: str,
    _: str = Depends(get_current_user)
):
    """Get DNS service status for a network
    
    Uses D-Bus to retrieve status directly from systemd (doesn't require sudo).
    
    Args:
        network: Network name ("homelab" or "lan")
        
    Returns:
        Service status information
    """
    logger.debug(f"Getting DNS service status for network: {network}")
    
    if network not in NETWORK_SERVICE_MAP:
        logger.warning(f"Invalid network requested: {network}")
        raise HTTPException(status_code=400, detail="Network must be 'homelab' or 'lan'")
    
    service_name = NETWORK_SERVICE_MAP[network]
    full_service_name = f"{service_name}.service"
    logger.debug(f"Mapped network '{network}' to service '{service_name}' (full name: '{full_service_name}')")
    
    try:
        # Get status via D-Bus
        logger.debug(f"Querying service status via D-Bus for: {full_service_name}")
        status = _get_service_status_via_dbus(full_service_name)
        logger.debug(f"Retrieved status: {status}")
        
        # Get process stats if we have a PID
        memory_mb = None
        cpu_percent = None
        if status['pid']:
            try:
                import psutil
                process = psutil.Process(status['pid'])
                mem_info = process.memory_info()
                memory_mb = mem_info.rss / 1024 / 1024  # Convert to MB
                cpu_percent = process.cpu_percent(interval=0.1)
                logger.debug(f"Process stats - PID: {status['pid']}, Memory: {memory_mb}MB, CPU: {cpu_percent}%")
            except (psutil.NoSuchProcess, psutil.AccessDenied) as e:
                logger.warning(f"Could not get process stats for PID {status['pid']}: {e}")
        
        result = {
            "network": network,
            "service_name": service_name,
            "is_active": status['is_active'],
            "is_enabled": status['is_enabled'],
            "exists": True,
            "pid": status['pid'],
            "memory_mb": memory_mb,
            "cpu_percent": cpu_percent
        }
        logger.debug(f"Returning status result: {result}")
        return result
    except Exception as e:
        # If D-Bus fails, service might not exist or be inaccessible
        logger.error(f"Error getting service status for {full_service_name}: {type(e).__name__}: {e}", exc_info=True)
        return {
            "network": network,
            "service_name": service_name,
            "is_active": False,
            "is_enabled": False,
            "exists": False,
            "error": str(e)
        }


@router.post("/service/{network}/{action}")
async def control_dns_service(
    network: str,
    action: str,
    _: str = Depends(get_current_user)
):
    """Control DNS service for a network
    
    Args:
        network: Network name ("homelab" or "lan")
        action: Action to perform ("start", "stop", "restart", "reload")
        
    Returns:
        Success message
    """
    logger.debug(f"Control DNS service request - network: {network}, action: {action}")
    
    if network not in NETWORK_SERVICE_MAP:
        logger.warning(f"Invalid network requested: {network}")
        raise HTTPException(status_code=400, detail="Network must be 'homelab' or 'lan'")
    
    if action not in ['start', 'stop', 'restart', 'reload']:
        logger.warning(f"Invalid action requested: {action}")
        raise HTTPException(status_code=400, detail="Action must be 'start', 'stop', 'restart', or 'reload'")
    
    service_name = NETWORK_SERVICE_MAP[network]
    full_service_name = f"{service_name}.service"
    logger.debug(f"Mapped network '{network}' to service '{service_name}' (full name: '{full_service_name}')")
    logger.debug(f"Attempting to {action} service: {full_service_name}")
    
    try:
        # Use D-Bus to control the service (works with polkit, doesn't need sudo)
        _control_service_via_dbus(full_service_name, action)
        logger.info(f"Successfully {action}ed service {service_name} for network {network}")
        
        return {
            "message": f"Service {service_name} {action}ed successfully",
            "network": network,
            "action": action,
            "service_name": service_name
        }
    except subprocess.CalledProcessError as e:
        error_msg = e.stderr or e.stdout or str(e)
        logger.error(f"Failed to {action} service {service_name}: returncode={e.returncode}, stderr={e.stderr[:500] if e.stderr else None}, stdout={e.stdout[:500] if e.stdout else None}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to {action} service {service_name}: {error_msg}"
        )
    except (subprocess.TimeoutExpired, ValueError, RuntimeError) as e:
        logger.error(f"Error while trying to {action} service {service_name}: {type(e).__name__}: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Error while trying to {action} service {service_name}: {str(e)}"
        )

