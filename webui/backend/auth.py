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


def _authenticate_via_socket(username: str, password: str) -> bool:
    """Authenticate user via socket-activated helper service (runs as root)
    
    This is required because PAM can only authenticate other users when running as root.
    Reference: https://pypi.org/project/python-pam/ - "You have root: you can check any account's password for validity"
    
    Uses a socket-activated service that runs as root and accepts authentication requests via
    a Unix socket. This follows NixOS best practices by avoiding direct PAM usage in unprivileged service.
    
    Args:
        username: System username
        password: User password
        
    Returns:
        bool: True if credentials are valid
    """
    import logging
    import socket
    logger = logging.getLogger(__name__)
    
    socket_path = "/run/router-webui/auth.sock"
    
    try:
        # Connect to authentication socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(10)  # 10 second timeout
        sock.connect(socket_path)
        
        # Send authentication request (format: "USERNAME\tPASSWORD\n")
        # Using tab as delimiter since passwords may contain spaces
        request = f"{username}\t{password}\n"
        sock.sendall(request.encode('utf-8'))
        sock.shutdown(socket.SHUT_WR)
        
        # Read response
        response = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            response += data
        
        sock.close()
        
        # Parse response
        response_str = response.decode('utf-8', errors='ignore').strip()
        
        if response_str == "SUCCESS":
            logger.info(f"PAM authentication successful for user: {username}")
            return True
        elif response_str.startswith("FAILURE"):
            logger.warning(f"PAM authentication failed for user: {username}")
            return False
        elif response_str.startswith("ERROR") or response_str.startswith("INVALID"):
            logger.error(f"Authentication helper error for user {username}: {response_str}")
            return False
        else:
            logger.error(f"Unexpected response from authentication helper: {response_str}")
            return False
            
    except FileNotFoundError:
        logger.error(f"Authentication socket not found: {socket_path}")
        return False
    except (socket.timeout, socket.error) as e:
        logger.error(f"Error communicating with authentication socket: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error during socket authentication: {e}")
        return False


def verify_system_user(username: str, password: str) -> bool:
    """Verify user credentials against system users
    
    Args:
        username: System username
        password: User password
        
    Returns:
        bool: True if credentials are valid
    """
    import logging
    logger = logging.getLogger(__name__)
    
    try:
        # Check if user exists
        pwd.getpwnam(username)
        
        # Try authentication via socket-activated helper (runs as root)
        # This is required because PAM can only authenticate other users when running as root
        try:
            result = _authenticate_via_socket(username, password)
            return result
        except Exception as e:
            logger.error(f"Socket authentication failed for user {username}: {e}")
            # Fallback to direct PAM authentication (only works for same user)
            # This is mainly for development/debugging
            if settings.debug:
                try:
                    import pamela
                    # In debug mode, try direct PAM (may only work for router-webui user)
                    result = pamela.authenticate(username, password, service='login')
                    if result:
                        logger.info(f"Direct PAM authentication successful for user: {username}")
                    return result
                except Exception as pam_error:
                    logger.warning(f"Direct PAM authentication also failed: {pam_error}")
            
            return False
            
    except KeyError:
        # User doesn't exist
        logger.warning(f"User does not exist: {username}")
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

