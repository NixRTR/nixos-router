"""
Authentication API endpoints
"""
from fastapi import APIRouter, Depends, HTTPException, status
from ..models import LoginRequest, LoginResponse
from ..auth import authenticate_user, get_current_user


router = APIRouter(prefix="/api/auth", tags=["authentication"])


@router.post("/login", response_model=LoginResponse)
async def login(credentials: LoginRequest):
    """Login endpoint - authenticate user and return JWT token
    
    Args:
        credentials: Username and password
        
    Returns:
        LoginResponse: JWT access token and user info
    """
    return await authenticate_user(credentials)


@router.get("/me")
async def get_me(current_user: str = Depends(get_current_user)):
    """Get current user information
    
    Args:
        current_user: Current authenticated user (from dependency)
        
    Returns:
        dict: Current user info
    """
    return {"username": current_user}


@router.post("/logout")
async def logout(current_user: str = Depends(get_current_user)):
    """Logout endpoint (client should discard token)
    
    Args:
        current_user: Current authenticated user (from dependency)
        
    Returns:
        dict: Success message
    """
    return {"message": "Successfully logged out"}

