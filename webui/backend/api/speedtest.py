"""
Speedtest API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
from datetime import datetime, timezone, timedelta
from typing import Optional, List
from pydantic import BaseModel, Field
import subprocess
import asyncio

from ..database import get_db, SpeedtestResultDB
from ..config import settings
import os

router = APIRouter(prefix="/api/speedtest", tags=["speedtest"])


# Pydantic models for request/response
class SpeedtestResultCreate(BaseModel):
    download_mbps: float = Field(..., gt=0, description="Download speed in Mbps")
    upload_mbps: float = Field(..., gt=0, description="Upload speed in Mbps")
    ping_ms: float = Field(..., gt=0, description="Ping latency in milliseconds")
    server_name: Optional[str] = None
    server_location: Optional[str] = None


class SpeedtestResult(BaseModel):
    id: int
    timestamp: datetime
    download_mbps: float
    upload_mbps: float
    ping_ms: float
    server_name: Optional[str]
    server_location: Optional[str]

    class Config:
        from_attributes = True


class SpeedtestHistoryResponse(BaseModel):
    results: List[SpeedtestResult]
    total: int
    page: int
    page_size: int
    total_pages: int


class SpeedtestStatus(BaseModel):
    is_running: bool
    progress: Optional[float] = None  # 0-100
    current_phase: Optional[str] = None  # "ping", "download", "upload", "complete"
    download_mbps: Optional[float] = None
    upload_mbps: Optional[float] = None
    ping_ms: Optional[float] = None


# Global state for speedtest execution
_speedtest_status = {
    "is_running": False,
    "progress": None,
    "current_phase": None,
    "download_mbps": None,
    "upload_mbps": None,
    "ping_ms": None,
}


@router.post("/results", response_model=SpeedtestResult)
async def create_speedtest_result(
    result: SpeedtestResultCreate,
    db: AsyncSession = Depends(get_db)
):
    """Store a speedtest result in the database"""
    db_result = SpeedtestResultDB(
        timestamp=datetime.now(timezone.utc),
        download_mbps=result.download_mbps,
        upload_mbps=result.upload_mbps,
        ping_ms=result.ping_ms,
        server_name=result.server_name,
        server_location=result.server_location,
    )
    db.add(db_result)
    await db.commit()
    await db.refresh(db_result)
    return db_result


@router.get("/history", response_model=SpeedtestHistoryResponse)
async def get_speedtest_history(
    start_time: Optional[datetime] = Query(None, description="Start time for filtering results"),
    end_time: Optional[datetime] = Query(None, description="End time for filtering results"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(25, ge=1, le=200, description="Results per page"),
    db: AsyncSession = Depends(get_db)
):
    """Get speedtest history with pagination"""
    # Build query
    query = select(SpeedtestResultDB)
    
    # Apply time filters
    if start_time:
        if start_time.tzinfo is None:
            start_time = start_time.replace(tzinfo=timezone.utc)
        query = query.where(SpeedtestResultDB.timestamp >= start_time)
    
    if end_time:
        if end_time.tzinfo is None:
            end_time = end_time.replace(tzinfo=timezone.utc)
        query = query.where(SpeedtestResultDB.timestamp <= end_time)
    
    # Get total count
    count_query = select(func.count()).select_from(SpeedtestResultDB)
    if start_time:
        count_query = count_query.where(SpeedtestResultDB.timestamp >= start_time)
    if end_time:
        count_query = count_query.where(SpeedtestResultDB.timestamp <= end_time)
    
    total_result = await db.execute(count_query)
    total = total_result.scalar()
    
    # Apply pagination and ordering
    query = query.order_by(desc(SpeedtestResultDB.timestamp))
    query = query.offset((page - 1) * page_size).limit(page_size)
    
    # Execute query
    result = await db.execute(query)
    results = result.scalars().all()
    
    total_pages = (total + page_size - 1) // page_size if total > 0 else 0
    
    return SpeedtestHistoryResponse(
        results=[SpeedtestResult.from_orm(r) for r in results],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/chart-data")
async def get_speedtest_chart_data(
    hours: int = Query(24, ge=1, le=8760, description="Number of hours to retrieve data for"),
    db: AsyncSession = Depends(get_db)
):
    """Get speedtest data for charting (last N hours)"""
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=hours)
    
    query = select(SpeedtestResultDB).where(
        SpeedtestResultDB.timestamp >= start_time,
        SpeedtestResultDB.timestamp <= end_time
    ).order_by(SpeedtestResultDB.timestamp)
    
    result = await db.execute(query)
    results = result.scalars().all()
    
    return {
        "data": [
            {
                "timestamp": r.timestamp.isoformat(),
                "download_mbps": r.download_mbps,
                "upload_mbps": r.upload_mbps,
                "ping_ms": r.ping_ms,
            }
            for r in results
        ]
    }


@router.get("/status", response_model=SpeedtestStatus)
async def get_speedtest_status():
    """Get current speedtest execution status"""
    return SpeedtestStatus(
        is_running=_speedtest_status["is_running"],
        progress=_speedtest_status.get("progress"),
        current_phase=_speedtest_status.get("current_phase"),
        download_mbps=_speedtest_status.get("download_mbps"),
        upload_mbps=_speedtest_status.get("upload_mbps"),
        ping_ms=_speedtest_status.get("ping_ms"),
    )


async def _run_speedtest_async(db: AsyncSession):
    """Run speedtest asynchronously and store results"""
    try:
        _speedtest_status["is_running"] = True
        _speedtest_status["progress"] = 0.0
        _speedtest_status["current_phase"] = "ping"
        _speedtest_status["ping_ms"] = None
        _speedtest_status["download_mbps"] = None
        _speedtest_status["upload_mbps"] = None
        
        # Run speedtest - use SPEEDTEST_BIN env var if available, otherwise try "speedtest" in PATH
        # Remove --simple to get verbose output that we can parse in real-time
        speedtest_bin = os.environ.get("SPEEDTEST_BIN", "speedtest")
        # Create environment with unbuffered output
        env = dict(os.environ)
        env["PYTHONUNBUFFERED"] = "1"
        process = await asyncio.create_subprocess_exec(
            speedtest_bin,
            "--secure",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,  # Merge stderr into stdout
            env=env,
        )
        
        # Read output line by line in real-time
        ping_ms = None
        download_mbps = None
        upload_mbps = None
        output_lines = []
        in_download = False
        in_upload = False
        
        if process.stdout:
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                
                line_str = line.decode('utf-8', errors='ignore').strip()
                if line_str:  # Only process non-empty lines
                    output_lines.append(line_str)
                    
                    # Parse verbose output for real-time updates
                    # Look for ping results
                    if "Ping:" in line_str or "Latency:" in line_str:
                        try:
                            # Try to extract ping value (format varies)
                            parts = line_str.split()
                            for i, part in enumerate(parts):
                                if part in ("Ping:", "Latency:") and i + 1 < len(parts):
                                    ping_str = parts[i + 1].rstrip('ms')
                                    ping_ms = float(ping_str)
                                    _speedtest_status["ping_ms"] = ping_ms
                                    _speedtest_status["progress"] = 10.0
                                    _speedtest_status["current_phase"] = "download"
                                    break
                        except (ValueError, IndexError):
                            pass
                    
                    # Look for download phase start
                    if "download" in line_str.lower() and "testing" in line_str.lower():
                        in_download = True
                        _speedtest_status["current_phase"] = "download"
                        _speedtest_status["progress"] = 20.0
                    
                    # Look for download speed updates (format: "Download: X.XX Mbit/s" or "X.XX Mbit/s")
                    if in_download and ("Mbit/s" in line_str or "Mbps" in line_str):
                        try:
                            # Extract speed value
                            parts = line_str.split()
                            for part in parts:
                                if "Mbit/s" in part or "Mbps" in part:
                                    speed_str = part.replace("Mbit/s", "").replace("Mbps", "")
                                    download_mbps = float(speed_str)
                                    _speedtest_status["download_mbps"] = download_mbps
                                    _speedtest_status["progress"] = 50.0
                                    break
                        except (ValueError, IndexError):
                            pass
                    
                    # Look for upload phase start
                    if "upload" in line_str.lower() and "testing" in line_str.lower():
                        in_upload = True
                        in_download = False
                        _speedtest_status["current_phase"] = "upload"
                        _speedtest_status["progress"] = 60.0
                    
                    # Look for upload speed updates
                    if in_upload and ("Mbit/s" in line_str or "Mbps" in line_str):
                        try:
                            parts = line_str.split()
                            for part in parts:
                                if "Mbit/s" in part or "Mbps" in part:
                                    speed_str = part.replace("Mbit/s", "").replace("Mbps", "")
                                    upload_mbps = float(speed_str)
                                    _speedtest_status["upload_mbps"] = upload_mbps
                                    _speedtest_status["progress"] = 90.0
                                    break
                        except (ValueError, IndexError):
                            pass
                    
                    # Also check for simple format (fallback)
                    if line_str.startswith("Ping:"):
                        try:
                            ping_ms = float(line_str.split()[1])
                            _speedtest_status["ping_ms"] = ping_ms
                            _speedtest_status["progress"] = 10.0
                            _speedtest_status["current_phase"] = "download"
                        except (ValueError, IndexError):
                            pass
                    elif line_str.startswith("Download:"):
                        try:
                            download_mbps = float(line_str.split()[1])
                            _speedtest_status["download_mbps"] = download_mbps
                            _speedtest_status["progress"] = 50.0
                            _speedtest_status["current_phase"] = "upload"
                        except (ValueError, IndexError):
                            pass
                    elif line_str.startswith("Upload:"):
                        try:
                            upload_mbps = float(line_str.split()[1])
                            _speedtest_status["upload_mbps"] = upload_mbps
                            _speedtest_status["progress"] = 100.0
                            _speedtest_status["current_phase"] = "complete"
                        except (ValueError, IndexError):
                            pass
        
        # Wait for process to complete
        returncode = await process.wait()
        
        if returncode != 0:
            error_output = "\n".join(output_lines)
            raise Exception(f"Speedtest failed with return code {returncode}: {error_output}")
        
        # Final parse from output (in case we missed something)
        output = "\n".join(output_lines)
        for line in output_lines:
            if line.startswith("Ping:") and ping_ms is None:
                try:
                    ping_ms = float(line.split()[1])
                    _speedtest_status["ping_ms"] = ping_ms
                except (ValueError, IndexError):
                    pass
            elif line.startswith("Download:") and download_mbps is None:
                try:
                    download_mbps = float(line.split()[1])
                    _speedtest_status["download_mbps"] = download_mbps
                except (ValueError, IndexError):
                    pass
            elif line.startswith("Upload:") and upload_mbps is None:
                try:
                    upload_mbps = float(line.split()[1])
                    _speedtest_status["upload_mbps"] = upload_mbps
                except (ValueError, IndexError):
                    pass
        
        if ping_ms is None or download_mbps is None or upload_mbps is None:
            raise Exception(f"Failed to parse speedtest output. Got: ping={ping_ms}, download={download_mbps}, upload={upload_mbps}")
        
        # Store result in database
        db_result = SpeedtestResultDB(
            timestamp=datetime.now(timezone.utc),
            download_mbps=download_mbps,
            upload_mbps=upload_mbps,
            ping_ms=ping_ms,
        )
        db.add(db_result)
        await db.commit()
        
    except Exception as e:
        print(f"Error running speedtest: {e}")
        raise
    finally:
        _speedtest_status["is_running"] = False
        _speedtest_status["progress"] = None
        _speedtest_status["current_phase"] = None


@router.post("/trigger")
async def trigger_speedtest(db: AsyncSession = Depends(get_db)):
    """Trigger a speedtest run"""
    if _speedtest_status["is_running"]:
        raise HTTPException(status_code=409, detail="Speedtest is already running")
    
    # Reset status
    _speedtest_status["download_mbps"] = None
    _speedtest_status["upload_mbps"] = None
    _speedtest_status["ping_ms"] = None
    
    # Run speedtest in background
    asyncio.create_task(_run_speedtest_async(db))
    
    return {"message": "Speedtest started", "status": "running"}

