"""
Apprise API notification service endpoints
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import Optional, List

from ..auth import get_current_user
from ..utils.apprise import (
    is_apprise_enabled,
    send_notification,
    get_configured_services,
    load_apprise_config,
    test_service
)


router = APIRouter(prefix="/api/apprise", tags=["apprise"])


class AppriseStatus(BaseModel):
    """Apprise enabled/disabled status"""
    enabled: bool


class NotificationRequest(BaseModel):
    """Request model for sending notifications"""
    body: str = Field(..., description="Message body (required)")
    title: Optional[str] = Field(None, description="Optional message title")
    notification_type: Optional[str] = Field(
        None,
        description="Notification type: info, success, warning, or failure"
    )


class NotificationResponse(BaseModel):
    """Response model for notification requests"""
    success: bool
    message: str
    details: Optional[str] = None


class ServiceInfo(BaseModel):
    """Information about a configured service"""
    url: str


@router.get("/status", response_model=AppriseStatus)
async def get_apprise_status(
    _: str = Depends(get_current_user)
) -> AppriseStatus:
    """Check if Apprise is enabled
    
    Returns:
        AppriseStatus: Enabled status
    """
    enabled = is_apprise_enabled()
    return AppriseStatus(enabled=enabled)


@router.post("/notify", response_model=NotificationResponse)
async def send_notification_endpoint(
    request: NotificationRequest,
    _: str = Depends(get_current_user)
) -> NotificationResponse:
    """Send a notification using configured Apprise services
    
    Args:
        request: Notification request with body, optional title and type
        
    Returns:
        NotificationResponse: Success status and message
    """
    if not is_apprise_enabled():
        raise HTTPException(
            status_code=503,
            detail="Apprise is not enabled"
        )
    
    success, error = send_notification(
        body=request.body,
        title=request.title,
        notification_type=request.notification_type
    )
    
    if success:
        return NotificationResponse(
            success=True,
            message="Notification sent successfully"
        )
    else:
        raise HTTPException(
            status_code=500,
            detail=error or "Failed to send notification"
        )


@router.get("/services", response_model=List[ServiceInfo])
async def get_services(
    _: str = Depends(get_current_user)
) -> List[ServiceInfo]:
    """Get list of configured notification services
    
    Returns:
        List of service URLs (with sensitive information masked)
    """
    if not is_apprise_enabled():
        return []
    
    services = get_configured_services()
    return [ServiceInfo(url=url) for url in services]


@router.post("/test/{service_index}", response_model=NotificationResponse)
async def test_service_endpoint(
    service_index: int,
    _: str = Depends(get_current_user)
) -> NotificationResponse:
    """Test a specific notification service by index
    
    Args:
        service_index: Index of the service to test (0-based)
        
    Returns:
        NotificationResponse: Success status and message
    """
    if not is_apprise_enabled():
        raise HTTPException(
            status_code=503,
            detail="Apprise is not enabled"
        )
    
    services = get_configured_services()
    
    if service_index < 0 or service_index >= len(services):
        raise HTTPException(
            status_code=404,
            detail=f"Service index {service_index} not found"
        )
    
    service_url = services[service_index]
    success, error, details = test_service(service_url)
    
    if success:
        return NotificationResponse(
            success=True,
            message=f"Test notification sent successfully",
            details=details
        )
    else:
        return NotificationResponse(
            success=False,
            message=error or "Failed to send test notification",
            details=details
        )


@router.get("/config")
async def get_config(
    _: str = Depends(get_current_user)
) -> dict:
    """Get Apprise configuration status
    
    Returns:
        Dictionary with configuration information
    """
    enabled = is_apprise_enabled()
    
    if not enabled:
        return {
            "enabled": False,
            "services_count": 0,
            "config_file_exists": False
        }
    
    try:
        apobj = load_apprise_config()
        services = get_configured_services()
        
        return {
            "enabled": True,
            "services_count": len(services),
            "config_file_exists": True,
            "services": services
        }
    except Exception as e:
        return {
            "enabled": True,
            "services_count": 0,
            "config_file_exists": True,
            "error": str(e)
        }

