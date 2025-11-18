"""
Main FastAPI application for Router WebUI
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os
import asyncio
from datetime import datetime, time, timedelta, timezone

from .config import settings
from .database import init_db
from .websocket import manager, websocket_endpoint
from .api.auth import router as auth_router
from .api.history import router as history_router
from .api.bandwidth import router as bandwidth_router
from .api.devices import router as devices_router
from .api.system import router as system_router
from .collectors.aggregation import run_aggregation_job


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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager
    
    Handles startup and shutdown events
    """
    # Startup
    print(f"Starting {settings.app_name}...")
    
    # Initialize database
    await init_db()
    print("Database initialized")
    
    # Start WebSocket broadcast loop
    await manager.start_broadcasting()
    print("WebSocket broadcaster started")
    
    # Start daily aggregation task
    aggregation_task = asyncio.create_task(daily_aggregation_task())
    print("Daily aggregation task started")
    
    yield
    
    # Shutdown
    print("Shutting down...")
    aggregation_task.cancel()
    try:
        await aggregation_task
    except asyncio.CancelledError:
        pass
    print("Aggregation task stopped")
    
    await manager.stop_broadcasting()
    print("WebSocket broadcaster stopped")


# Create FastAPI app
app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="Router monitoring and management interface",
    lifespan=lifespan
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


# Serve documentation site at /docs route
# This allows the React docs SPA to run independently with its own routing
docs_path = os.environ.get("DOCUMENTATION_DIR", "/var/lib/router-webui/docs")
docs_assets_path = os.path.join(docs_path, "assets")

if os.path.exists(docs_assets_path) and os.path.isdir(docs_assets_path):
    # Mount docs assets
    app.mount("/docs/assets", StaticFiles(directory=docs_assets_path), name="docs-assets")
    print(f"Serving documentation assets from {docs_assets_path}")
    
    @app.get("/docs/{full_path:path}")
    async def serve_docs(full_path: str):
        """Serve React documentation site (SPA)
        
        This allows the React docs site to run as a standalone SPA with its own routing.
        All routes under /docs will serve the docs site, with index.html as fallback for SPA routing.
        """
        # Don't intercept API or WebSocket routes
        if full_path.startswith("api") or full_path.startswith("ws"):
            return
        
        # For root docs path, serve index.html
        if not full_path or full_path == "/":
            index_path = os.path.join(docs_path, "index.html")
            if os.path.isfile(index_path):
                return FileResponse(index_path)
        
        # Try to serve the requested file
        file_path = os.path.join(docs_path, full_path)
        if os.path.isfile(file_path):
            return FileResponse(file_path)
        
        # Default to index.html for SPA routing (React Router handles client-side routing)
        index_path = os.path.join(docs_path, "index.html")
        if os.path.isfile(index_path):
            return FileResponse(index_path)
else:
    print(f"Documentation not built yet. Assets directory not found at {docs_assets_path}")

# Serve frontend static files in production
# This assumes frontend is built to /var/lib/router-webui/frontend
frontend_path = "/var/lib/router-webui/frontend"
assets_path = os.path.join(frontend_path, "assets")

# Only mount static files if frontend is built and assets directory exists
if os.path.exists(assets_path) and os.path.isdir(assets_path):
    app.mount("/assets", StaticFiles(directory=assets_path), name="assets")
    print(f"Serving frontend assets from {assets_path}")
    
    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str):
        """Serve frontend application"""
        # Don't intercept API, WebSocket, or docs routes
        if full_path.startswith("api") or full_path.startswith("ws") or full_path.startswith("docs"):
            return
        
        # For root path, serve index.html
        if not full_path or full_path == "/":
            index_path = os.path.join(frontend_path, "index.html")
            if os.path.isfile(index_path):
                return FileResponse(index_path)
        
        # Try to serve the requested file
        file_path = os.path.join(frontend_path, full_path)
        if os.path.isfile(file_path):
            return FileResponse(file_path)
        
        # Default to index.html for SPA routing (if it exists)
        index_path = os.path.join(frontend_path, "index.html")
        if os.path.isfile(index_path):
            return FileResponse(index_path)
else:
    print(f"Frontend not built yet. Assets directory not found at {assets_path}")
    print("Backend API is available, but frontend UI is not served.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug
    )

