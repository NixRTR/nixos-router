"""
Historical data API endpoints
"""
from fastapi import APIRouter, Depends, Query
from datetime import datetime, timedelta, timezone
from typing import List, Optional
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from ..database import get_db, SystemMetricsDB, InterfaceStatsDB, ServiceStatusDB
from ..auth import get_current_user


router = APIRouter(prefix="/api/history", tags=["history"], dependencies=[Depends(get_current_user)])


@router.get("/system")
async def get_system_history(
    start: Optional[datetime] = Query(None, description="Start timestamp"),
    end: Optional[datetime] = Query(None, description="End timestamp"),
    interval: int = Query(300, ge=60, le=3600, description="Data point interval in seconds"),
    db: AsyncSession = Depends(get_db)
):
    """Get historical system metrics
    
    Args:
        start: Start time (default: 1 hour ago)
        end: End time (default: now)
        interval: Aggregation interval in seconds
        db: Database session
        
    Returns:
        List of aggregated system metrics
    """
    if end is None:
        end = datetime.now(timezone.utc)
    if start is None:
        start = end - timedelta(hours=1)
    
    # Calculate time buckets for aggregation
    bucket_size = interval
    
    query = select(
        func.date_trunc('minute', SystemMetricsDB.timestamp).label('time_bucket'),
        func.avg(SystemMetricsDB.cpu_percent).label('avg_cpu'),
        func.avg(SystemMetricsDB.memory_percent).label('avg_memory'),
        func.avg(SystemMetricsDB.load_avg_1m).label('avg_load'),
    ).where(
        and_(
            SystemMetricsDB.timestamp >= start,
            SystemMetricsDB.timestamp <= end
        )
    ).group_by('time_bucket').order_by('time_bucket')
    
    result = await db.execute(query)
    rows = result.all()
    
    return [
        {
            "timestamp": row.time_bucket.isoformat(),
            "cpu_percent": float(row.avg_cpu) if row.avg_cpu else None,
            "memory_percent": float(row.avg_memory) if row.avg_memory else None,
            "load_avg": float(row.avg_load) if row.avg_load else None,
        }
        for row in rows
    ]


@router.get("/interface/{interface_name}")
async def get_interface_history(
    interface_name: str,
    start: Optional[datetime] = Query(None, description="Start timestamp"),
    end: Optional[datetime] = Query(None, description="End timestamp"),
    interval: int = Query(300, ge=60, le=3600, description="Data point interval in seconds"),
    db: AsyncSession = Depends(get_db)
):
    """Get historical interface statistics
    
    Args:
        interface_name: Network interface name
        start: Start time (default: 1 hour ago)
        end: End time (default: now)
        interval: Aggregation interval in seconds
        db: Database session
        
    Returns:
        List of aggregated interface stats
    """
    if end is None:
        end = datetime.now(timezone.utc)
    if start is None:
        start = end - timedelta(hours=1)
    
    query = select(
        func.date_trunc('minute', InterfaceStatsDB.timestamp).label('time_bucket'),
        func.max(InterfaceStatsDB.rx_bytes).label('max_rx_bytes'),
        func.max(InterfaceStatsDB.tx_bytes).label('max_tx_bytes'),
        func.sum(InterfaceStatsDB.rx_packets).label('total_rx_packets'),
        func.sum(InterfaceStatsDB.tx_packets).label('total_tx_packets'),
    ).where(
        and_(
            InterfaceStatsDB.interface == interface_name,
            InterfaceStatsDB.timestamp >= start,
            InterfaceStatsDB.timestamp <= end
        )
    ).group_by('time_bucket').order_by('time_bucket')
    
    result = await db.execute(query)
    rows = result.all()
    
    # Calculate bandwidth rates between data points
    data = []
    prev_row = None
    
    for row in rows:
        point = {
            "timestamp": row.time_bucket.isoformat(),
            "rx_bytes": int(row.max_rx_bytes) if row.max_rx_bytes else 0,
            "tx_bytes": int(row.max_tx_bytes) if row.max_tx_bytes else 0,
            "rx_packets": int(row.total_rx_packets) if row.total_rx_packets else 0,
            "tx_packets": int(row.total_tx_packets) if row.total_tx_packets else 0,
        }
        
        # Calculate rates if we have previous data
        if prev_row:
            time_delta = 60  # 1 minute buckets
            rx_delta = point["rx_bytes"] - prev_row["rx_bytes"]
            tx_delta = point["tx_bytes"] - prev_row["tx_bytes"]
            
            # Convert to Mbps
            point["rx_rate_mbps"] = (rx_delta * 8) / (time_delta * 1_000_000) if rx_delta >= 0 else 0
            point["tx_rate_mbps"] = (tx_delta * 8) / (time_delta * 1_000_000) if tx_delta >= 0 else 0
        else:
            point["rx_rate_mbps"] = 0
            point["tx_rate_mbps"] = 0
        
        data.append(point)
        prev_row = point
    
    return data


@router.get("/bandwidth/{network}")
async def get_bandwidth_history(
    network: str,
    period: str = Query("1h", regex="^(1h|24h|7d|30d)$", description="Time period"),
    db: AsyncSession = Depends(get_db)
):
    """Get bandwidth history for a network
    
    Args:
        network: 'homelab' or 'lan'
        period: Time period (1h, 24h, 7d, 30d)
        db: Database session
        
    Returns:
        Bandwidth history data
    """
    # Map network to interface name
    interface_map = {
        "homelab": "br0",
        "lan": "br1",
        "wan": "ppp0"
    }
    
    interface_name = interface_map.get(network, network)
    
    # Map period to time delta
    period_map = {
        "1h": timedelta(hours=1),
        "24h": timedelta(hours=24),
        "7d": timedelta(days=7),
        "30d": timedelta(days=30)
    }
    
    end = datetime.now()
    start = end - period_map[period]
    
    # Adjust interval based on period
    interval_map = {
        "1h": 60,      # 1 minute
        "24h": 300,    # 5 minutes
        "7d": 1800,    # 30 minutes
        "30d": 3600    # 1 hour
    }
    interval = interval_map[period]
    
    return await get_interface_history(interface_name, start, end, interval, db)


@router.get("/services")
async def get_service_history(
    service_name: Optional[str] = Query(None, description="Filter by service name"),
    start: Optional[datetime] = Query(None, description="Start timestamp"),
    end: Optional[datetime] = Query(None, description="End timestamp"),
    db: AsyncSession = Depends(get_db)
):
    """Get historical service status
    
    Args:
        service_name: Optional service name filter
        start: Start time (default: 1 hour ago)
        end: End time (default: now)
        db: Database session
        
    Returns:
        List of service status records
    """
    if end is None:
        end = datetime.now(timezone.utc)
    if start is None:
        start = end - timedelta(hours=1)
    
    conditions = [
        ServiceStatusDB.timestamp >= start,
        ServiceStatusDB.timestamp <= end
    ]
    
    if service_name:
        conditions.append(ServiceStatusDB.service_name == service_name)
    
    query = select(ServiceStatusDB).where(and_(*conditions)).order_by(ServiceStatusDB.timestamp.desc()).limit(1000)
    
    result = await db.execute(query)
    rows = result.scalars().all()
    
    return [
        {
            "timestamp": row.timestamp.isoformat(),
            "service_name": row.service_name,
            "is_active": row.is_active,
            "is_enabled": row.is_enabled,
            "pid": row.pid,
            "memory_mb": row.memory_mb,
            "cpu_percent": row.cpu_percent
        }
        for row in rows
    ]

