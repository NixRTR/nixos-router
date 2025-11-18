"""
System metrics API endpoints
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from typing import List, Optional
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from pydantic import BaseModel
import subprocess
import os

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
from ..database import AsyncSessionLocal, SystemMetricsDB, DiskIOMetricsDB, TemperatureMetricsDB

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
        "timestamp": datetime.now(timezone.utc),
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
        start_time = datetime.now(timezone.utc) - time_delta
        
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
        start_time = datetime.now(timezone.utc) - time_delta
        
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
        start_time = datetime.now(timezone.utc) - time_delta
        
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


def _find_fastfetch() -> str:
    """Find fastfetch binary path (Nix way)"""
    env_path = os.environ.get("FASTFETCH_BIN")
    if env_path:
        return env_path
    candidates = [
        "/run/current-system/sw/bin/fastfetch",
        "/usr/bin/fastfetch",
        "/usr/local/bin/fastfetch",
        "fastfetch"
    ]
    for path in candidates:
        try:
            p = subprocess.run([path, "--version"], capture_output=True, text=True, timeout=2)
            if p.returncode == 0:
                return path
        except Exception:
            continue
    raise RuntimeError("fastfetch binary not found")


def _ansi_to_html(ansi_text: str) -> str:
    """Convert ANSI escape codes to HTML with proper styling
    
    Converts ANSI escape sequences to HTML spans with CSS styling.
    Handles colors, backgrounds, and text styles (bold, italic, underline).
    """
    import re
    
    # ANSI color codes mapping (standard 16 colors)
    ansi_colors = {
        '30': '#000000',  # Black
        '31': '#cd0000',  # Red
        '32': '#00cd00',  # Green
        '33': '#cdcd00',  # Yellow
        '34': '#0000ee',  # Blue
        '35': '#cd00cd',  # Magenta
        '36': '#00cdcd',  # Cyan
        '37': '#e5e5e5',  # White
        '90': '#7f7f7f',  # Bright Black
        '91': '#ff0000',  # Bright Red
        '92': '#00ff00',  # Bright Green
        '93': '#ffff00',  # Bright Yellow
        '94': '#5c5cff',  # Bright Blue
        '95': '#ff00ff',  # Bright Magenta
        '96': '#00ffff',  # Bright Cyan
        '97': '#ffffff',  # Bright White
    }
    
    # Background colors
    bg_colors = {
        '40': '#000000',
        '41': '#cd0000',
        '42': '#00cd00',
        '43': '#cdcd00',
        '44': '#0000ee',
        '45': '#cd00cd',
        '46': '#00cdcd',
        '47': '#e5e5e5',
        '100': '#7f7f7f',
        '101': '#ff0000',
        '102': '#00ff00',
        '103': '#ffff00',
        '104': '#5c5cff',
        '105': '#ff00ff',
        '106': '#00ffff',
        '107': '#ffffff',
    }
    
    html_parts = []
    i = 0
    open_spans = []  # Stack of open span tags
    
    def close_spans():
        while open_spans:
            html_parts.append('</span>')
            open_spans.pop()
    
    while i < len(ansi_text):
        if ansi_text[i] == '\x1b' or ansi_text[i] == '\033':
            # Found escape sequence
            if i + 1 < len(ansi_text) and ansi_text[i + 1] == '[':
                # Find the end of the escape sequence
                j = i + 2
                while j < len(ansi_text) and ansi_text[j] not in 'mHfABCDJK':
                    j += 1
                
                if j < len(ansi_text):
                    seq = ansi_text[i + 2:j]
                    code = ansi_text[j]
                    
                    if code == 'm':
                        # SGR (Select Graphic Rendition) - colors and styles
                        if seq == '' or seq == '0':
                            # Reset - close all spans
                            close_spans()
                        else:
                            codes = seq.split(';')
                            styles = []
                            
                            for c in codes:
                                if c == '':
                                    continue
                                elif c in ansi_colors:
                                    styles.append(f'color: {ansi_colors[c]}')
                                elif c in bg_colors:
                                    styles.append(f'background-color: {bg_colors[c]}')
                                elif c == '1':
                                    styles.append('font-weight: bold')
                                elif c == '3':
                                    styles.append('font-style: italic')
                                elif c == '4':
                                    styles.append('text-decoration: underline')
                                elif c == '22':
                                    # Normal intensity (not bold)
                                    styles.append('font-weight: normal')
                                elif c == '23':
                                    # Not italic
                                    styles.append('font-style: normal')
                                elif c == '24':
                                    # Not underlined
                                    styles.append('text-decoration: none')
                            
                            if styles:
                                # Close previous spans and open new one
                                close_spans()
                                style_str = '; '.join(styles)
                                html_parts.append(f'<span style="{style_str}">')
                                open_spans.append(style_str)
                    
                    i = j + 1
                    continue
        
        # Regular character - escape HTML
        char = ansi_text[i]
        if char == '<':
            html_parts.append('&lt;')
        elif char == '>':
            html_parts.append('&gt;')
        elif char == '&':
            html_parts.append('&amp;')
        elif char == '\n':
            html_parts.append('<br>')
        elif char == '\r':
            pass  # Ignore carriage return
        elif char == '\t':
            html_parts.append('&nbsp;&nbsp;&nbsp;&nbsp;')  # Tab as 4 spaces
        elif char == ' ':
            html_parts.append('&nbsp;')
        else:
            html_parts.append(char)
        
        i += 1
    
    # Close any remaining open spans
    close_spans()
    
    return ''.join(html_parts)


@router.get("/fastfetch")
async def get_fastfetch(
    _: str = Depends(get_current_user)
) -> dict:
    """Run fastfetch and return the output as HTML with ANSI colors rendered
    
    Returns:
        dict: Contains 'html' field with HTML-rendered fastfetch output
    """
    try:
        fastfetch_bin = _find_fastfetch()
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    
    try:
        result = subprocess.run(
            [fastfetch_bin],
            capture_output=True,
            text=True,
            timeout=10,
            env=os.environ.copy()  # Preserve environment for proper colors/formatting
        )
        
        if result.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail=f"fastfetch failed: {result.stderr or 'Unknown error'}"
            )
        
        # Convert ANSI output to HTML
        html_content = _ansi_to_html(result.stdout)
        
        return {"html": html_content}
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="fastfetch timed out")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error running fastfetch: {str(e)}")

