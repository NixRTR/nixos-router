"""
DNS management API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional

from ..database import get_db, DnsZoneDB, DnsRecordDB
from ..models import (
    DnsZone, DnsZoneCreate, DnsZoneUpdate,
    DnsRecord, DnsRecordCreate, DnsRecordUpdate
)
from ..api.auth import get_current_user

router = APIRouter(prefix="/api/dns", tags=["dns"])


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

