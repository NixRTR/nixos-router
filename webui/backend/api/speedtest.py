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
        
        # Run speedtest-cli
        process = await asyncio.create_subprocess_exec(
            "speedtest-cli",
            "--simple",
            "--secure",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            error_msg = stderr.decode() if stderr else "Unknown error"
            raise Exception(f"Speedtest failed: {error_msg}")
        
        output = stdout.decode()
        
        # Parse output (format: "Ping: X ms\nDownload: X Mbit/s\nUpload: X Mbit/s")
        lines = output.strip().split("\n")
        ping_ms = None
        download_mbps = None
        upload_mbps = None
        
        for line in lines:
            if line.startswith("Ping:"):
                ping_ms = float(line.split()[1])
                _speedtest_status["ping_ms"] = ping_ms
                _speedtest_status["progress"] = 33.0
            elif line.startswith("Download:"):
                download_mbps = float(line.split()[1])
                _speedtest_status["download_mbps"] = download_mbps
                _speedtest_status["current_phase"] = "upload"
                _speedtest_status["progress"] = 66.0
            elif line.startswith("Upload:"):
                upload_mbps = float(line.split()[1])
                _speedtest_status["upload_mbps"] = upload_mbps
                _speedtest_status["progress"] = 100.0
                _speedtest_status["current_phase"] = "complete"
        
        if ping_ms is None or download_mbps is None or upload_mbps is None:
            raise Exception("Failed to parse speedtest output")
        
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

