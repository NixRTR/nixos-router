"""
Authentication using PAM and JWT tokens
"""
import pwd
from datetime import datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt

from .config import settings
from .models import LoginRequest, LoginResponse


security = HTTPBearer()


def verify_system_user(username: str, password: str) -> bool:
    """Verify user credentials against system users
    
    Args:
        username: System username
        password: User password
        
    Returns:
        bool: True if credentials are valid
    """
    try:
        # Check if user exists
        pwd.getpwnam(username)
        
        # Try PAM authentication
        try:
            import pamela
            pamela.authenticate(username, password, service='login')
            return True
        except ImportError:
            # PAM not available (e.g., on Windows for development)
            # In development, accept any password for existing system user
            if settings.debug:
                return True
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="PAM authentication not available"
            )
        except pamela.PAMError:
            # Authentication failed
            return False
            
    except KeyError:
        # User doesn't exist
        return False


def create_access_token(username: str) -> str:
    """Create JWT access token
    
    Args:
        username: Username to encode in token
        
    Returns:
        str: JWT token
    """
    expire = datetime.utcnow() + timedelta(minutes=settings.jwt_expiration_minutes)
    
    to_encode = {
        "sub": username,
        "exp": expire,
        "iat": datetime.utcnow()
    }
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm
    )
    
    return encoded_jwt


def decode_access_token(token: str) -> Optional[str]:
    """Decode and validate JWT token
    
    Args:
        token: JWT token string
        
    Returns:
        Optional[str]: Username if token is valid, None otherwise
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm]
        )
        username: str = payload.get("sub")
        if username is None:
            return None
        return username
    except JWTError:
        return None


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    """Dependency to get current authenticated user
    
    Args:
        credentials: HTTP bearer credentials
        
    Returns:
        str: Username
        
    Raises:
        HTTPException: If token is invalid
    """
    username = decode_access_token(credentials.credentials)
    
    if username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    return username


async def authenticate_user(login: LoginRequest) -> LoginResponse:
    """Authenticate user and return JWT token
    
    Args:
        login: Login credentials
        
    Returns:
        LoginResponse: JWT token and user info
        
    Raises:
        HTTPException: If credentials are invalid
    """
    if not verify_system_user(login.username, login.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(login.username)
    
    return LoginResponse(
        access_token=access_token,
        token_type="bearer",
        username=login.username
    )

