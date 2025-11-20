"""
CAKE traffic shaping API endpoints
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from datetime import datetime, timezone, timedelta
from typing import Optional, List
import json

from ..auth import get_current_user
from ..models import CakeStats, CakeStatus, CakeStatsHistory, CakeDataPoint, CakeTrafficClass
from ..collectors.cake import collect_cake_stats
from ..utils.cake import is_cake_enabled, get_wan_interface
from ..database import get_db, AsyncSessionLocal, CakeStatsDB


router = APIRouter(prefix="/api/cake", tags=["cake"])


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


@router.get("/status", response_model=CakeStatus)
async def get_cake_status(
    _: str = Depends(get_current_user)
) -> CakeStatus:
    """Check if CAKE is enabled
    
    Returns:
        CakeStatus: Enabled status and interface name
    """
    enabled, interface = is_cake_enabled()
    return CakeStatus(
        enabled=enabled,
        interface=interface
    )


@router.get("/current")
async def get_current_cake_stats(
    interface: Optional[str] = Query(None, description="Interface name (e.g., ppp0)"),
    _: str = Depends(get_current_user)
) -> Optional[CakeStats]:
    """Get current CAKE statistics
    
    Args:
        interface: Optional interface name (defaults to WAN interface)
        
    Returns:
        CakeStats or None if CAKE is not configured
    """
    stats = collect_cake_stats(interface=interface)
    return stats


@router.get("/history", response_model=CakeStatsHistory)
async def get_cake_history(
    interface: Optional[str] = Query(None, description="Interface name (e.g., ppp0)"),
    time_range: str = Query("1h", description="Time range (e.g., 10m, 1h, 1d)", alias="range"),
    _: str = Depends(get_current_user)
) -> CakeStatsHistory:
    """Get historical CAKE statistics
    
    Args:
        interface: Optional interface filter (defaults to WAN interface)
        time_range: Time range string (e.g., "10m", "1h", "1d")
        
    Returns:
        CakeStatsHistory: Historical data points
    """
    # Determine interface
    if interface is None:
        interface = get_wan_interface()
    
    if interface is None:
        # No interface found, return empty history
        return CakeStatsHistory(interface="unknown", data=[])
    
    async with AsyncSessionLocal() as session:
        # Parse time range
        time_delta = parse_time_range(time_range)
        start_time = datetime.now(timezone.utc) - time_delta
        
        # Query database for CAKE stats in time range
        query = select(CakeStatsDB).where(
            CakeStatsDB.timestamp >= start_time,
            CakeStatsDB.interface == interface
        ).order_by(CakeStatsDB.timestamp.asc())
        
        result = await session.execute(query)
        stats = result.scalars().all()
        
        # Convert to data points
        data_points = []
        for s in stats:
            # Parse classes from JSONB
            classes_dict = {}
            if s.classes:
                try:
                    if isinstance(s.classes, str):
                        classes_data = json.loads(s.classes)
                    else:
                        classes_data = s.classes
                    
                    for class_name, class_data in classes_data.items():
                        classes_dict[class_name] = CakeTrafficClass(
                            pk_delay_ms=class_data.get('pk_delay_ms'),
                            av_delay_ms=class_data.get('av_delay_ms'),
                            sp_delay_ms=class_data.get('sp_delay_ms'),
                            bytes=class_data.get('bytes'),
                            packets=class_data.get('packets'),
                            drops=class_data.get('drops'),
                            marks=class_data.get('marks'),
                        )
                except (json.JSONDecodeError, TypeError, AttributeError):
                    pass
            
            data_points.append(CakeDataPoint(
                timestamp=s.timestamp,
                rate_mbps=s.rate_mbps,
                target_ms=s.target_ms,
                interval_ms=s.interval_ms,
                classes=classes_dict,
                way_inds=s.way_inds,
                way_miss=s.way_miss,
                way_cols=s.way_cols,
            ))
        
        return CakeStatsHistory(interface=interface, data=data_points)

