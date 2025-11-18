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


def _ansi_to_image(ansi_text: str) -> bytes:
    """Convert ANSI escape codes to WebP image using Pillow
    
    Renders ANSI text with proper font metrics and accurate spacing.
    Returns WebP image bytes.
    """
    from PIL import Image, ImageDraw, ImageFont
    
    # ANSI color codes mapping (standard 16 colors) - RGB tuples
    ansi_colors = {
        '30': (0, 0, 0),        # Black
        '31': (205, 0, 0),      # Red
        '32': (0, 205, 0),      # Green
        '33': (205, 205, 0),    # Yellow
        '34': (0, 0, 238),      # Blue
        '35': (205, 0, 205),    # Magenta
        '36': (0, 205, 205),    # Cyan
        '37': (229, 229, 229),  # White
        '90': (127, 127, 127),  # Bright Black
        '91': (255, 0, 0),      # Bright Red
        '92': (0, 255, 0),      # Bright Green
        '93': (255, 255, 0),    # Bright Yellow
        '94': (92, 92, 255),    # Bright Blue
        '95': (255, 0, 255),    # Bright Magenta
        '96': (0, 255, 255),    # Bright Cyan
        '97': (255, 255, 255),  # Bright White
    }
    
    # Background colors
    bg_colors = {
        '40': (0, 0, 0),
        '41': (205, 0, 0),
        '42': (0, 205, 0),
        '43': (205, 205, 0),
        '44': (0, 0, 238),
        '45': (205, 0, 205),
        '46': (0, 205, 205),
        '47': (229, 229, 229),
        '100': (127, 127, 127),
        '101': (255, 0, 0),
        '102': (0, 255, 0),
        '103': (255, 255, 0),
        '104': (92, 92, 255),
        '105': (255, 0, 255),
        '106': (0, 255, 255),
        '107': (255, 255, 255),
    }
    
    # Try to use a monospace font with larger size for better quality
    font_size = 16
    font = None
    font_bold = None
    
    font_paths = [
        # NixOS font locations
        "/run/current-system/sw/share/X11/fonts/TTF/DejaVuSansMono.ttf",
        "/run/current-system/sw/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/nix/store/*/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/nix/store/*/share/X11/fonts/TTF/DejaVuSansMono.ttf",
        # Standard Linux locations
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    ]
    
    for path in font_paths:
        try:
            if '*' in path:
                # Try to find font in nix store
                import glob
                matches = glob.glob(path)
                if matches:
                    font = ImageFont.truetype(matches[0], font_size)
                    try:
                        font_bold = ImageFont.truetype(matches[0].replace('DejaVuSansMono', 'DejaVuSansMono-Bold'), font_size)
                    except:
                        font_bold = font
                    break
            else:
                font = ImageFont.truetype(path, font_size)
                try:
                    bold_path = path.replace('DejaVuSansMono', 'DejaVuSansMono-Bold')
                    font_bold = ImageFont.truetype(bold_path, font_size)
                except:
                    font_bold = font
                break
        except:
            continue
    
    if font is None:
        try:
            font = ImageFont.truetype("Courier", font_size)
            font_bold = font
        except:
            font = ImageFont.load_default()
            font_bold = font
    
    # Get actual font metrics
    test_img = Image.new('RGB', (100, 100), (0, 0, 0))
    test_draw = ImageDraw.Draw(test_img)
    bbox = test_draw.textbbox((0, 0), "M", font=font)
    char_width = bbox[2] - bbox[0]
    char_height = bbox[3] - bbox[1]
    line_height = char_height + 2  # Small spacing between lines
    
    # Parse ANSI text and build lines with color/style info
    lines = []
    current_fg = (229, 229, 229)  # Default white
    current_bg = (0, 0, 0)  # Default black
    current_bold = False
    
    i = 0
    current_line = []
    
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
                            # Reset
                            current_fg = (229, 229, 229)
                            current_bg = (0, 0, 0)
                            current_bold = False
                        else:
                            codes = seq.split(';')
                            for c in codes:
                                if c == '':
                                    continue
                                elif c in ansi_colors:
                                    current_fg = ansi_colors[c]
                                elif c in bg_colors:
                                    current_bg = bg_colors[c]
                                elif c == '1':
                                    current_bold = True
                                elif c == '22':
                                    current_bold = False
                                elif c == '39':  # Default foreground
                                    current_fg = (229, 229, 229)
                                elif c == '49':  # Default background
                                    current_bg = (0, 0, 0)
                    
                    i = j + 1
                    continue
        
        # Regular character
        char = ansi_text[i]
        if char == '\n':
            lines.append(current_line)
            current_line = []
        elif char == '\r':
            pass  # Ignore carriage return
        elif char == '\t':
            # Tab as 4 spaces
            for _ in range(4):
                current_line.append((' ', current_fg, current_bg, current_bold))
        else:
            current_line.append((char, current_fg, current_bg, current_bold))
        
        i += 1
    
    if current_line:
        lines.append(current_line)
    
    if not lines:
        lines = [[('No output', (229, 229, 229), (0, 0, 0), False)]]
    
    # Calculate image dimensions using actual font metrics
    max_line_length = max(len(line) for line in lines) if lines else 1
    padding = 20
    img_width = max_line_length * char_width + (padding * 2)
    img_height = len(lines) * line_height + (padding * 2)
    
    # Create image with black background
    img = Image.new('RGB', (img_width, img_height), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw text line by line, grouping consecutive characters with same style
    y = padding
    for line in lines:
        x = padding
        i = 0
        while i < len(line):
            # Group consecutive characters with same style
            char, fg, bg, bold = line[i]
            start_i = i
            while i < len(line) and line[i][1:] == (fg, bg, bold):
                i += 1
            
            # Get the text segment
            text_segment = ''.join(line[j][0] for j in range(start_i, i))
            
            # Draw background for the segment
            if bg != (0, 0, 0):
                segment_width = len(text_segment) * char_width
                draw.rectangle([x, y, x + segment_width, y + char_height], fill=bg)
            
            # Draw text segment
            font_to_use = font_bold if bold else font
            draw.text((x, y), text_segment, fill=fg, font=font_to_use)
            
            x += len(text_segment) * char_width
        
        y += line_height
    
    # Convert to WebP
    import io
    output = io.BytesIO()
    img.save(output, format='WEBP', quality=90)
    return output.getvalue()


@router.get("/fastfetch")
async def get_fastfetch(
    _: str = Depends(get_current_user)
) -> dict:
    """Run fastfetch and return the output as WebP image
    
    Returns:
        dict: Contains 'image' field with base64-encoded WebP image data
    """
    import base64
    
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
        
        # Convert ANSI output to WebP image
        image_bytes = _ansi_to_image(result.stdout)
        
        # Return as base64-encoded string
        image_base64 = base64.b64encode(image_bytes).decode('utf-8')
        
        return {"image": image_base64}
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="fastfetch timed out")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error running fastfetch: {str(e)}")

