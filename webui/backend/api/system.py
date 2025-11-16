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
from ..database import AsyncSessionLocal, SystemMetricsDB, DiskIOMetricsDB, TemperatureMetricsDB, DeviceBandwidthDB

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


class DiskIODataPoint(BaseModel):
    """Single data point for disk I/O metrics"""
    timestamp: datetime
    read_mbps: float
    write_mbps: float


class DiskIOHistory(BaseModel):
    """Historical disk I/O metrics for a device"""
    device: str
    data: List[DiskIODataPoint]


class TemperatureDataPoint(BaseModel):
    """Single data point for temperature metrics"""
    timestamp: datetime
    temperature_c: float


class TemperatureHistory(BaseModel):
    """Historical temperature metrics for a sensor"""
    sensor_name: str
    data: List[TemperatureDataPoint]


class DeviceBandwidthDataPoint(BaseModel):
    """Single data point for device bandwidth metrics"""
    timestamp: datetime
    rx_mbps: float
    tx_mbps: float


class DeviceBandwidthHistory(BaseModel):
    """Historical device bandwidth metrics"""
    network: str
    ip_address: str
    mac_address: Optional[str]
    hostname: Optional[str]
    data: List[DeviceBandwidthDataPoint]


class DeviceBandwidthSummary(BaseModel):
    """Device bandwidth summary with current rates and historical totals"""
    network: str
    ip_address: str
    mac_address: Optional[str] = None
    hostname: Optional[str] = None
    current_rx_mbps: float
    current_tx_mbps: float
    last_hour_rx_mb: float
    last_hour_tx_mb: float
    last_day_rx_mb: float
    last_day_tx_mb: float
    last_month_rx_mb: float
    last_month_tx_mb: float


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


@router.get("/disk-io/history")
async def get_disk_io_history(
    device: Optional[str] = Query(None, description="Device name (e.g., sda, nvme0n1)"),
    time_range: str = Query("30m", description="Time range (e.g., 10m, 1h, 1d)", alias="range"),
    _: str = Depends(get_current_user)
) -> List[DiskIOHistory]:
    """Get historical disk I/O metrics
    
    Args:
        device: Optional device filter
        time_range: Time range string (e.g., "30m", "1h", "3h")
        
    Returns:
        List[DiskIOHistory]: Historical data per device
    """
    async with AsyncSessionLocal() as session:
        # Parse time range
        time_delta = parse_time_range(time_range)
        start_time = datetime.now() - time_delta
        
        # Query database for disk I/O metrics
        query = select(DiskIOMetricsDB).where(DiskIOMetricsDB.timestamp >= start_time)
        if device:
            query = query.where(DiskIOMetricsDB.device == device)
        query = query.order_by(DiskIOMetricsDB.timestamp.asc())
        
        result = await session.execute(query)
        metrics = result.scalars().all()
        
        # Group by device
        devices = {}
        for m in metrics:
            if m.device not in devices:
                devices[m.device] = []
            devices[m.device].append(
                DiskIODataPoint(
                    timestamp=m.timestamp,
                    read_mbps=m.read_bytes_per_sec / (1024 * 1024) if m.read_bytes_per_sec else 0,
                    write_mbps=m.write_bytes_per_sec / (1024 * 1024) if m.write_bytes_per_sec else 0
                )
            )
        
        return [
            DiskIOHistory(device=dev, data=data)
            for dev, data in devices.items()
        ]


@router.get("/temperatures/history")
async def get_temperature_history(
    sensor: Optional[str] = Query(None, description="Sensor name"),
    time_range: str = Query("30m", description="Time range (e.g., 10m, 1h, 1d)", alias="range"),
    _: str = Depends(get_current_user)
) -> List[TemperatureHistory]:
    """Get historical temperature metrics
    
    Args:
        sensor: Optional sensor filter
        time_range: Time range string (e.g., "30m", "1h", "3h")
        
    Returns:
        List[TemperatureHistory]: Historical data per sensor
    """
    async with AsyncSessionLocal() as session:
        # Parse time range
        time_delta = parse_time_range(time_range)
        start_time = datetime.now() - time_delta
        
        # Query database for temperature metrics
        query = select(TemperatureMetricsDB).where(TemperatureMetricsDB.timestamp >= start_time)
        if sensor:
            query = query.where(TemperatureMetricsDB.sensor_name == sensor)
        query = query.order_by(TemperatureMetricsDB.timestamp.asc())
        
        result = await session.execute(query)
        metrics = result.scalars().all()
        
        # Group by sensor name (using label if available, otherwise sensor_name)
        sensors = {}
        for m in metrics:
            key = m.label if m.label else m.sensor_name
            if key not in sensors:
                sensors[key] = []
            sensors[key].append(
                TemperatureDataPoint(
                    timestamp=m.timestamp,
                    temperature_c=m.temperature_c
                )
            )
        
        return [
            TemperatureHistory(sensor_name=sensor, data=data)
            for sensor, data in sensors.items()
        ]


@router.get("/device-bandwidth/history")
async def get_device_bandwidth_history(
    ip_address: Optional[str] = Query(None, description="IP address filter"),
    network: Optional[str] = Query(None, description="Network filter (homelab/lan)"),
    time_range: str = Query("30m", description="Time range (e.g., 10m, 1h, 1d)", alias="range"),
    _: str = Depends(get_current_user)
) -> List[DeviceBandwidthHistory]:
    """Get historical device bandwidth metrics

    Args:
        ip_address: Optional IP address filter
        network: Optional network filter
        time_range: Time range string (e.g., "30m", "1h", "3h")

    Returns:
        List[DeviceBandwidthHistory]: Historical data per device
    """
    async with AsyncSessionLocal() as session:
        # Parse time range
        time_delta = parse_time_range(time_range)
        start_time = datetime.now() - time_delta

        # Query database for device bandwidth metrics
        query = select(DeviceBandwidthDB).where(DeviceBandwidthDB.timestamp >= start_time)
        if ip_address:
            query = query.where(DeviceBandwidthDB.ip_address == ip_address)
        if network:
            query = query.where(DeviceBandwidthDB.network == network)
        query = query.order_by(DeviceBandwidthDB.ip_address, DeviceBandwidthDB.timestamp.asc())

        result = await session.execute(query)
        metrics = result.scalars().all()

        # Group by device (IP address)
        devices = {}
        for m in metrics:
            key = m.ip_address
            if key not in devices:
                devices[key] = {
                    'network': m.network,
                    'ip_address': m.ip_address,
                    'mac_address': m.mac_address,
                    'hostname': m.hostname,
                    'data': []
                }
            devices[key]['data'].append(
                DeviceBandwidthDataPoint(
                    timestamp=m.timestamp,
                    rx_mbps=m.rx_bytes_per_sec / (1024 * 1024) if m.rx_bytes_per_sec else 0,
                    tx_mbps=m.tx_bytes_per_sec / (1024 * 1024) if m.tx_bytes_per_sec else 0
                )
            )

        return [
            DeviceBandwidthHistory(**device_data)
            for device_data in devices.values()
        ]


@router.get("/device-bandwidth/summary")
async def get_device_bandwidth_summary(
    network: Optional[str] = Query(None, description="Network filter (homelab/lan)"),
    _: str = Depends(get_current_user)
) -> List[DeviceBandwidthSummary]:
    """Get device bandwidth summary with current rates and historical totals

    Args:
        network: Optional network filter

    Returns:
        List[DeviceBandwidthSummary]: Device bandwidth summaries
    """
    async with AsyncSessionLocal() as session:
        now = datetime.now()

        # Get all devices that have had bandwidth in the last hour
        one_hour_ago = now - timedelta(hours=1)
        query = select(DeviceBandwidthDB).where(DeviceBandwidthDB.timestamp >= one_hour_ago)
        if network:
            query = query.where(DeviceBandwidthDB.network == network)
        query = query.distinct(DeviceBandwidthDB.ip_address)

        result = await session.execute(query)
        recent_devices = result.scalars().all()

        summaries = []

        for device in recent_devices:
            # Get current rates (latest measurement in last 5 minutes)
            five_min_ago = now - timedelta(minutes=5)
            current_query = select(DeviceBandwidthDB).where(
                DeviceBandwidthDB.ip_address == device.ip_address,
                DeviceBandwidthDB.timestamp >= five_min_ago
            ).order_by(DeviceBandwidthDB.timestamp.desc()).limit(1)

            current_result = await session.execute(current_query)
            current = current_result.scalar_one_or_none()

            current_rx = (current.rx_bytes_per_sec / (1024 * 1024)) if current and current.rx_bytes_per_sec else 0
            current_tx = (current.tx_bytes_per_sec / (1024 * 1024)) if current and current.tx_bytes_per_sec else 0

            # Calculate totals for different periods
            periods = [
                ('last_hour', one_hour_ago, now),
                ('last_day', now - timedelta(days=1), now),
                ('last_month', now - timedelta(days=30), now)
            ]

            period_totals = {}
            for period_name, start_time, end_time in periods:
                period_query = select(DeviceBandwidthDB).where(
                    DeviceBandwidthDB.ip_address == device.ip_address,
                    DeviceBandwidthDB.timestamp >= start_time,
                    DeviceBandwidthDB.timestamp <= end_time
                )

                period_result = await session.execute(period_query)
                period_metrics = period_result.scalars().all()

                # Sum all bytes in the period (simple integration)
                total_rx = sum(m.rx_bytes_per_sec or 0 for m in period_metrics)
                total_tx = sum(m.tx_bytes_per_sec or 0 for m in period_metrics)

                # Convert to MB (bytes * seconds = total bytes, divide by 1024^2 for MB)
                # This is approximate - real integration would use time deltas
                period_seconds = (end_time - start_time).total_seconds()
                period_totals[f'{period_name}_rx_mb'] = (total_rx * period_seconds) / (1024 * 1024)
                period_totals[f'{period_name}_tx_mb'] = (total_tx * period_seconds) / (1024 * 1024)

            summaries.append(DeviceBandwidthSummary(
                network=device.network,
                ip_address=device.ip_address,
                mac_address=device.mac_address,
                hostname=device.hostname,
                current_rx_mbps=current_rx,
                current_tx_mbps=current_tx,
                last_hour_rx_mb=period_totals['last_hour_rx_mb'],
                last_hour_tx_mb=period_totals['last_hour_tx_mb'],
                last_day_rx_mb=period_totals['last_day_rx_mb'],
                last_day_tx_mb=period_totals['last_day_tx_mb'],
                last_month_rx_mb=period_totals['last_month_rx_mb'],
                last_month_tx_mb=period_totals['last_month_tx_mb']
            ))

        return summaries

