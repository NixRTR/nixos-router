"""
Main FastAPI application for Router WebUI
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os

from .config import settings
from .database import init_db
from .websocket import manager, websocket_endpoint
from .api.auth import router as auth_router
from .api.history import router as history_router


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
    
    yield
    
    # Shutdown
    print("Shutting down...")
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


@app.get("/")
async def root():
    """Root endpoint"""
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


# Serve frontend static files in production
# This assumes frontend is built to /var/lib/router-webui/frontend
frontend_path = "/var/lib/router-webui/frontend"
if os.path.exists(frontend_path):
    app.mount("/assets", StaticFiles(directory=f"{frontend_path}/assets"), name="assets")
    
    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str):
        """Serve frontend application"""
        # Serve index.html for all routes (SPA routing)
        if not full_path or full_path.startswith("api/") or full_path.startswith("ws"):
            return
        
        file_path = os.path.join(frontend_path, full_path)
        if os.path.isfile(file_path):
            return FileResponse(file_path)
        
        # Default to index.html for SPA routing
        return FileResponse(os.path.join(frontend_path, "index.html"))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug
    )

