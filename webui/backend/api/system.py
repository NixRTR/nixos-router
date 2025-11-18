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
import httpx

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
    # Check environment variable first (set by NixOS service)
    env_path = os.environ.get("FASTFETCH_BIN")
    if env_path:
        return env_path
    
    # Try common locations
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


def _strip_ansi_codes(text: str) -> str:
    """Remove ANSI escape codes from text"""
    import re
    # Remove ANSI escape sequences
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)


@router.get("/fastfetch")
async def get_fastfetch(
    _: str = Depends(get_current_user)
) -> dict:
    """Run fastfetch and return plain text output (no logo, no colors)
    
    Returns:
        dict: Contains 'text' field with plain text system information
    """
    try:
        fastfetch_bin = _find_fastfetch()
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    
    try:
        # Run fastfetch with --logo none to remove logo
        # Colors will be stripped from output
        result = subprocess.run(
            [fastfetch_bin, "--logo", "none"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            # Strip ANSI codes to get plain text
            text_output = _strip_ansi_codes(result.stdout)
            return {"text": text_output}
        else:
            raise HTTPException(
                status_code=500,
                detail=f"fastfetch failed with return code {result.returncode}: {result.stderr}"
            )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error running fastfetch: {str(e)}"
        )


class GitHubStats(BaseModel):
    """GitHub repository statistics"""
    stars: int
    forks: int


@router.get("/github-stats", response_model=GitHubStats)
async def get_github_stats(
    _: str = Depends(get_current_user)
) -> GitHubStats:
    """Get GitHub repository statistics (stars and forks)
    
    Returns:
        GitHubStats: Repository stars and forks count
    """
    repo_owner = "BeardedTek"
    repo_name = "nixos-router"
    
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"https://api.github.com/repos/{repo_owner}/{repo_name}",
                headers={"Accept": "application/vnd.github.v3+json"}
            )
            response.raise_for_status()
            data = response.json()
            
            return GitHubStats(
                stars=data.get("stargazers_count", 0),
                forks=data.get("forks_count", 0)
            )
    except httpx.HTTPError as e:
        # If GitHub API fails, return zeros (don't break the UI)
        print(f"Warning: Failed to fetch GitHub stats: {e}")
        return GitHubStats(stars=0, forks=0)
    except Exception as e:
        print(f"Warning: Error fetching GitHub stats: {e}")
        return GitHubStats(stars=0, forks=0)


@router.get("/documentation")
async def get_documentation(
    _: str = Depends(get_current_user)
) -> dict:
    """Get project documentation (React site index.html)
    
    Returns:
        dict: Contains 'content' field with HTML content from React docs site
    """
    # Use environment variable set by NixOS service (points to React docs build directory)
    doc_dir = os.environ.get("DOCUMENTATION_DIR", "/var/lib/router-webui/docs")
    index_path = os.path.join(doc_dir, "index.html")
    
    try:
        with open(index_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return {"content": content}
    except FileNotFoundError:
        raise HTTPException(
            status_code=404,
            detail=f"Documentation not found at {index_path}. React docs site may not be built yet."
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error reading documentation: {str(e)}"
        )


@router.get("/documentation/{path:path}")
async def get_documentation_page(
    path: str,
    _: str = Depends(get_current_user)
):
    """Serve static files from React documentation site
    
    This allows the frontend to load CSS, JS, images, and other assets
    from the React docs site.
    """
    from fastapi.responses import FileResponse
    
    doc_dir = os.environ.get("DOCUMENTATION_DIR", "/var/lib/router-webui/docs")
    file_path = os.path.join(doc_dir, path)
    
    # Security: ensure the path is within the documentation directory
    if not os.path.abspath(file_path).startswith(os.path.abspath(doc_dir)):
        raise HTTPException(status_code=403, detail="Access denied")
    
    if os.path.isfile(file_path):
        return FileResponse(file_path)
    elif os.path.isdir(file_path):
        # Try index.html in the directory
        index_path = os.path.join(file_path, "index.html")
        if os.path.isfile(index_path):
            return FileResponse(index_path)
    
    raise HTTPException(status_code=404, detail="File not found")

