"""
Main FastAPI application for Router WebUI
"""
import logging
import sys
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
import os
import asyncio
from datetime import datetime, time, timedelta, timezone

from .config import settings

# Configure logging
logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)

# Enable verbose logging for Apprise (equivalent to -vvvv)
# Set Apprise logger to DEBUG level for maximum verbosity
apprise_logger = logging.getLogger('apprise')
apprise_logger.setLevel(logging.DEBUG)

# Also enable debug for apprise.plugins and apprise.attachment modules
logging.getLogger('apprise.plugins').setLevel(logging.DEBUG)
logging.getLogger('apprise.attachment').setLevel(logging.DEBUG)

# Disable SQLAlchemy engine INFO logging (suppress INSERT/UPDATE/DELETE statements)
# Only show WARNING and above for SQLAlchemy engine
logging.getLogger('sqlalchemy.engine').setLevel(logging.WARNING)
from .database import init_db, AsyncSessionLocal
from .websocket import manager, websocket_endpoint
from .api.auth import router as auth_router
from .api.history import router as history_router
from .api.bandwidth import router as bandwidth_router
from .api.devices import router as devices_router
from .api.system import router as system_router
from .api.speedtest import router as speedtest_router
from .api.cake import router as cake_router
from .api.apprise import router as apprise_router
from .api.notifications import router as notifications_router
from .api.dns import router as dns_router
from .api.dhcp import router as dhcp_router
from .collectors.aggregation import run_aggregation_job
from .collectors.notifications import NotificationEvaluator
from .utils.apprise import migrate_secrets_to_database
from .utils.dns import migrate_dns_config_to_database
from .utils.dhcp import migrate_dhcp_config_to_database

notification_evaluator = NotificationEvaluator(AsyncSessionLocal)


async def daily_aggregation_task():
    """Background task that runs aggregation job daily at 2 AM"""
    while True:
        try:
            # Calculate time until next 2 AM UTC
            now = datetime.now(timezone.utc)
            target_hour = 2  # 2 AM UTC
            
            # If it's already past 2 AM today, schedule for tomorrow
            if now.hour >= target_hour:
                next_run = datetime(now.year, now.month, now.day, target_hour, 0, 0, tzinfo=timezone.utc) + timedelta(days=1)
            else:
                next_run = datetime(now.year, now.month, now.day, target_hour, 0, 0, tzinfo=timezone.utc)
            
            wait_seconds = (next_run - now).total_seconds()
            print(f"Aggregation job scheduled for {next_run} (in {wait_seconds/3600:.1f} hours)")
            
            await asyncio.sleep(wait_seconds)
            
            # Run aggregation job
            await run_aggregation_job()
            
        except asyncio.CancelledError:
            break
        except Exception as e:
            print(f"Error in daily aggregation task: {e}")
            # Wait 1 hour before retrying on error
            await asyncio.sleep(3600)


async def notification_evaluator_task():
    """Background task that periodically evaluates notification rules"""
    while True:
        try:
            await notification_evaluator.evaluate_all()
            await asyncio.sleep(settings.notification_check_interval)
        except asyncio.CancelledError:
            break
        except Exception as exc:
            logging.getLogger(__name__).error(
                "Notification evaluator error: %s", exc, exc_info=True
            )
            await asyncio.sleep(settings.notification_check_interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager
    
    Handles startup and shutdown events
    """
    # Startup
    print(f"Starting {settings.app_name}...")
    
    # Initialize database
    await init_db()
    
    # Migrate Apprise services from secrets/config file to database
    try:
        async with AsyncSessionLocal() as session:
            await migrate_secrets_to_database(session)
    except Exception as e:
        logging.getLogger(__name__).error(
            f"Error migrating Apprise services: {e}", exc_info=True
        )
        # Don't fail startup if migration fails
    
    # Migrate DNS configuration from router-config.nix to database
    try:
        async with AsyncSessionLocal() as session:
            await migrate_dns_config_to_database(session)
    except Exception as e:
        logging.getLogger(__name__).error(
            f"Error migrating DNS configuration: {e}", exc_info=True
        )
        # Don't fail startup if migration fails
    
    # Migrate DHCP configuration from router-config.nix to database
    try:
        async with AsyncSessionLocal() as session:
            await migrate_dhcp_config_to_database(session)
    except Exception as e:
        logging.getLogger(__name__).error(
            f"Error migrating DHCP configuration: {e}", exc_info=True
        )
        # Don't fail startup if migration fails
    
    # Start WebSocket broadcast loop
    await manager.start_broadcasting()
    print("WebSocket broadcaster started")
    
    # Start daily aggregation task
    aggregation_task = asyncio.create_task(daily_aggregation_task())
    print("Daily aggregation task started")
    notification_task = asyncio.create_task(notification_evaluator_task())
    print("Notification evaluator task started")
    
    yield
    
    # Shutdown
    print("Shutting down...")
    aggregation_task.cancel()
    try:
        await aggregation_task
    except asyncio.CancelledError:
        pass
    print("Aggregation task stopped")

    notification_task.cancel()
    try:
        await notification_task
    except asyncio.CancelledError:
        pass
    print("Notification evaluator task stopped")
    
    await manager.stop_broadcasting()
    print("WebSocket broadcaster stopped")


# Create FastAPI app
# Disable default /docs and /redoc routes to avoid conflict with our documentation site
app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="Router monitoring and management interface",
    lifespan=lifespan,
    docs_url="/api/docs",  # Move API docs to /api/docs instead of /docs
    redoc_url="/api/redoc"  # Move ReDoc to /api/redoc
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routers
app.include_router(auth_router)
app.include_router(history_router)
app.include_router(bandwidth_router)
app.include_router(devices_router)
app.include_router(system_router)
app.include_router(speedtest_router)
app.include_router(cake_router)
app.include_router(apprise_router)
app.include_router(notifications_router)
app.include_router(dns_router)
app.include_router(dhcp_router)


@app.get("/api")
async def root():
    """API root endpoint"""
    return {
        "name": settings.app_name,
        "version": "1.0.0",
        "status": "operational"
    }


@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "active_connections": len(manager.active_connections)
    }


@app.websocket("/ws")
async def websocket_route(
    websocket: WebSocket,
    token: str = Query(..., description="JWT authentication token")
):
    """WebSocket endpoint for real-time metrics
    
    Args:
        websocket: WebSocket connection
        token: JWT token for authentication
    """
    await websocket_endpoint(websocket, token)

# Note: Static file serving (frontend and docs) is now handled by nginx
# FastAPI only handles API routes and WebSocket connections


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug
    )

