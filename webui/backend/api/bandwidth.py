"""
Bandwidth history API endpoints
"""
from fastapi import APIRouter, Depends, Query
from typing import List, Optional
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from pydantic import BaseModel

from ..auth import get_current_user
from ..database import AsyncSessionLocal, InterfaceStatsDB


router = APIRouter(prefix="/api/bandwidth", tags=["bandwidth"])


class InterfaceDataPoint(BaseModel):
    """Single data point for interface bandwidth"""
    timestamp: datetime
    rx_mbps: float
    tx_mbps: float


class BandwidthHistory(BaseModel):
    """Bandwidth history for an interface"""
    interface: str
    data: List[InterfaceDataPoint]


def parse_time_range(range_str: str) -> timedelta:
    """Parse time range string to timedelta
    
    Supports: 5m, 30m, 1h, 3h, 12h, 1d, 1w, 1M (30 days), 1y (365 days)
    
    Args:
        range_str: Time range string (e.g., "1h", "30m", "1d")
        
    Returns:
        timedelta: Parsed time delta
    """
    range_str = range_str.strip().lower()
    
    # Extract number and unit
    if not range_str:
        return timedelta(hours=1)  # Default to 1 hour
    
    # Find where the number ends and unit begins
    num_str = ""
    unit = ""
    
    for char in range_str:
        if char.isdigit() or char == '.':
            num_str += char
        else:
            unit = range_str[len(num_str):]
            break
    
    if not num_str:
        return timedelta(hours=1)
    
    try:
        value = float(num_str)
    except ValueError:
        return timedelta(hours=1)
    
    # Parse unit
    if unit in ['m', 'min', 'mins', 'minute', 'minutes']:
        return timedelta(minutes=value)
    elif unit in ['h', 'hr', 'hrs', 'hour', 'hours']:
        return timedelta(hours=value)
    elif unit in ['d', 'day', 'days']:
        return timedelta(days=value)
    elif unit in ['w', 'week', 'weeks']:
        return timedelta(weeks=value)
    elif unit in ['M', 'month', 'months']:
        return timedelta(days=value * 30)  # Approximate
    elif unit in ['y', 'year', 'years']:
        return timedelta(days=value * 365)  # Approximate
    else:
        return timedelta(hours=1)  # Default


@router.get("/history")
async def get_bandwidth_history(
    interface: Optional[str] = Query(None, description="Interface name (e.g., ppp0, br0)"),
    time_range: str = Query("1h", description="Time range (e.g., 10m, 1h, 1d, 1w)", alias="range"),
    _: str = Depends(get_current_user)
) -> List[BandwidthHistory]:
    """Get historical bandwidth data
    
    Args:
        interface: Optional interface filter (returns all if not specified)
        time_range: Time range string (default: 1h)
        
    Returns:
        List[BandwidthHistory]: Bandwidth history per interface
    """
    # Parse time range
    time_delta = parse_time_range(time_range)
    start_time = datetime.now(timezone.utc) - time_delta
    
    async with AsyncSessionLocal() as session:
        # Build query
        query = select(InterfaceStatsDB).where(
            InterfaceStatsDB.timestamp >= start_time
        ).order_by(InterfaceStatsDB.timestamp.asc())
        
        if interface:
            query = query.where(InterfaceStatsDB.interface == interface)
        
        result = await session.execute(query)
        stats = result.scalars().all()
    
    # Group by interface
    interfaces = {}
    for stat in stats:
        if stat.interface not in interfaces:
            interfaces[stat.interface] = []
        
        # Calculate bandwidth in Mbps
        # Note: We store cumulative bytes, need to calculate rate
        # For now, we'll use the raw bytes and let frontend calculate rate
        interfaces[stat.interface].append({
            'timestamp': stat.timestamp,
            'rx_bytes': stat.rx_bytes,
            'tx_bytes': stat.tx_bytes,
            'rx_mbps': 0.0,  # Will be calculated from deltas
            'tx_mbps': 0.0
        })
    
    # Calculate rates (Mbps) from byte deltas
    history_list = []
    for iface, data_points in interfaces.items():
        processed_points = []
        
        for i in range(len(data_points)):
            if i == 0:
                # First point, no rate calculation possible
                processed_points.append(InterfaceDataPoint(
                    timestamp=data_points[i]['timestamp'],
                    rx_mbps=0.0,
                    tx_mbps=0.0
                ))
            else:
                # Calculate rate from previous point
                prev = data_points[i - 1]
                curr = data_points[i]
                
                time_diff = (curr['timestamp'] - prev['timestamp']).total_seconds()
                if time_diff > 0:
                    # Bytes per second -> Megabits per second
                    rx_mbps = ((curr['rx_bytes'] - prev['rx_bytes']) * 8) / (time_diff * 1_000_000)
                    tx_mbps = ((curr['tx_bytes'] - prev['tx_bytes']) * 8) / (time_diff * 1_000_000)
                    
                    # Clamp to reasonable values (ignore spikes/anomalies)
                    rx_mbps = max(0, min(rx_mbps, 10000))  # Max 10 Gbps
                    tx_mbps = max(0, min(tx_mbps, 10000))
                else:
                    rx_mbps = 0.0
                    tx_mbps = 0.0
                
                processed_points.append(InterfaceDataPoint(
                    timestamp=curr['timestamp'],
                    rx_mbps=round(rx_mbps, 2),
                    tx_mbps=round(tx_mbps, 2)
                ))
        
        history_list.append(BandwidthHistory(
            interface=iface,
            data=processed_points
        ))
    
    return history_list


@router.get("/interfaces")
async def get_available_interfaces(
    _: str = Depends(get_current_user)
) -> List[str]:
    """Get list of interfaces with bandwidth data
    
    Returns:
        List[str]: Interface names
    """
    async with AsyncSessionLocal() as session:
        # Get distinct interfaces from last hour
        one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
        
        query = select(InterfaceStatsDB.interface).distinct().where(
            InterfaceStatsDB.timestamp >= one_hour_ago
        )
        
        result = await session.execute(query)
        interfaces = [row[0] for row in result.all()]
    
    return sorted(interfaces)

