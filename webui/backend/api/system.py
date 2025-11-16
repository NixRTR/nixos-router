"""
System metrics API endpoints
"""
from fastapi import APIRouter, Depends, Query
from typing import List, Optional
from datetime import datetime, timedelta
from sqlalchemy import select
from pydantic import BaseModel

from ..auth import get_current_user
from ..models import (
    SystemMetrics, DiskIOMetrics, DiskSpaceMetrics,
    TemperatureMetrics, FanMetrics, ClientStats
)
from ..collectors.system import (
    collect_system_metrics, collect_disk_io, collect_disk_space,
    collect_temperatures, collect_fan_speeds
)
from ..collectors.clients import collect_client_stats
from ..database import AsyncSessionLocal, SystemMetricsDB

router = APIRouter(prefix="/api/system", tags=["system"])


class SystemDataPoint(BaseModel):
    """Single data point for system metrics"""
    timestamp: datetime
    cpu_percent: float
    memory_percent: float
    load_avg_1m: float


class SystemHistory(BaseModel):
    """Historical system metrics"""
    data: List[SystemDataPoint]


def parse_time_range(range_str: str) -> timedelta:
    """Parse time range string to timedelta"""
    range_str = range_str.strip().lower()
    if not range_str:
        return timedelta(minutes=30)
    
    num_str = ""
    unit = ""
    for char in range_str:
        if char.isdigit() or char == '.':
            num_str += char
        else:
            unit = range_str[len(num_str):]
            break
    
    if not num_str:
        return timedelta(minutes=30)
    
    try:
        value = float(num_str)
    except ValueError:
        return timedelta(minutes=30)
    
    if unit in ['m', 'min', 'mins', 'minute', 'minutes']:
        return timedelta(minutes=value)
    elif unit in ['h', 'hr', 'hrs', 'hour', 'hours']:
        return timedelta(hours=value)
    elif unit in ['d', 'day', 'days']:
        return timedelta(days=value)
    else:
        return timedelta(minutes=30)


@router.get("/current")
async def get_current_system_metrics(
    _: str = Depends(get_current_user)
) -> dict:
    """Get current system metrics snapshot
    
    Returns all system metrics in a single response:
    - System (CPU, memory, load)
    - Disk I/O
    - Disk space
    - Temperatures
    - Fan speeds
    - Client statistics
    """
    return {
        "timestamp": datetime.now(),
        "system": collect_system_metrics(),
        "disk_io": collect_disk_io(),
        "disk_space": collect_disk_space(),
        "temperatures": collect_temperatures(),
        "fans": collect_fan_speeds(),
        "clients": collect_client_stats()
    }


@router.get("/metrics")
async def get_system_metrics(
    _: str = Depends(get_current_user)
) -> SystemMetrics:
    """Get basic system metrics (CPU, memory, load)"""
    return collect_system_metrics()


@router.get("/disk/io")
async def get_disk_io(
    _: str = Depends(get_current_user)
) -> List[DiskIOMetrics]:
    """Get current disk I/O statistics"""
    return collect_disk_io()


@router.get("/disk/space")
async def get_disk_space(
    _: str = Depends(get_current_user)
) -> List[DiskSpaceMetrics]:
    """Get disk space usage"""
    return collect_disk_space()


@router.get("/temperatures")
async def get_temperatures(
    _: str = Depends(get_current_user)
) -> List[TemperatureMetrics]:
    """Get temperature sensor readings"""
    return collect_temperatures()


@router.get("/fans")
async def get_fan_speeds(
    _: str = Depends(get_current_user)
) -> List[FanMetrics]:
    """Get fan speed readings"""
    return collect_fan_speeds()


@router.get("/clients")
async def get_client_statistics(
    _: str = Depends(get_current_user)
) -> List[ClientStats]:
    """Get network client statistics"""
    return collect_client_stats()


@router.get("/history")
async def get_system_history(
    time_range: str = Query("30m", description="Time range (e.g., 10m, 1h, 1d)", alias="range"),
    _: str = Depends(get_current_user)
) -> SystemHistory:
    """Get historical system metrics (CPU, memory, load)
    
    Args:
        time_range: Time range string (e.g., "30m", "1h", "3h")
        
    Returns:
        SystemHistory: Historical data points
    """
    async with AsyncSessionLocal() as session:
        # Parse time range
        time_delta = parse_time_range(time_range)
        start_time = datetime.now() - time_delta
        
        # Query database for metrics in time range
        result = await session.execute(
            select(SystemMetricsDB)
            .where(SystemMetricsDB.timestamp >= start_time)
            .order_by(SystemMetricsDB.timestamp.asc())
        )
        metrics = result.scalars().all()
        
        # Convert to data points
        data_points = [
            SystemDataPoint(
                timestamp=m.timestamp,
                cpu_percent=m.cpu_percent,
                memory_percent=m.memory_percent,
                load_avg_1m=m.load_avg_1m
            )
            for m in metrics
        ]
        
        return SystemHistory(data=data_points)

