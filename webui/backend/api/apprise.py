"""
Apprise API notification service endpoints
"""
import logging
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

logger = logging.getLogger(__name__)


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
    
    try:
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
            # Return 200 with success=False so frontend can display the error
            # This allows partial success (some services work, others don't)
            return NotificationResponse(
                success=False,
                message=error or "Failed to send notification to all services",
                details=error
            )
    except Exception as e:
        logger.error(f"Exception in send_notification_endpoint: {type(e).__name__}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {type(e).__name__}: {str(e)}"
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


@router.post("/send/{service_index}", response_model=NotificationResponse)
async def send_to_service_endpoint(
    service_index: int,
    request: NotificationRequest,
    _: str = Depends(get_current_user)
) -> NotificationResponse:
    """Send a notification to a specific service by index
    
    Args:
        service_index: Index of the service to send to (0-based)
        request: Notification request with body, optional title and type
        
    Returns:
        NotificationResponse: Success status and message
    """
    logger.info(f"Send to service endpoint called for service index: {service_index}")
    
    try:
        if not is_apprise_enabled():
            logger.warning("Apprise is not enabled")
            raise HTTPException(
                status_code=503,
                detail="Apprise is not enabled"
            )
        
        logger.debug("Fetching configured services")
        services = get_configured_services()
        logger.debug(f"Found {len(services)} configured services")
        
        if service_index < 0 or service_index >= len(services):
            logger.error(f"Service index {service_index} out of range (0-{len(services)-1})")
            raise HTTPException(
                status_code=404,
                detail=f"Service index {service_index} not found. Available indices: 0-{len(services)-1}"
            )
        
        service_url = services[service_index]
        logger.info(f"Sending notification to service at index {service_index}: {service_url[:50]}... (masked)")
        logger.debug(f"Notification details: title={request.title}, body={request.body[:50]}..., type={request.notification_type}")
        
        try:
            success, error, details = test_service(
                service_url,
                body=request.body,
                title=request.title,
                notification_type=request.notification_type
            )
            logger.info(f"Send result for service {service_index}: success={success}, error={error}, details={details}")
        except Exception as send_error:
            logger.error(f"Exception in test_service: {type(send_error).__name__}: {str(send_error)}", exc_info=True)
            raise HTTPException(
                status_code=500,
                detail=f"Error sending notification: {str(send_error)}"
            )
        
        if success:
            return NotificationResponse(
                success=True,
                message=f"Notification sent successfully",
                details=details
            )
        else:
            # Return 200 with success=False so frontend can display the error
            return NotificationResponse(
                success=False,
                message=error or "Failed to send notification",
                details=details
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in send_to_service_endpoint: {type(e).__name__}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {type(e).__name__}: {str(e)}"
        )


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
    logger.info(f"Test service endpoint called for service index: {service_index}")
    
    try:
        if not is_apprise_enabled():
            logger.warning("Apprise is not enabled")
            raise HTTPException(
                status_code=503,
                detail="Apprise is not enabled"
            )
        
        logger.debug("Fetching configured services")
        services = get_configured_services()
        logger.debug(f"Found {len(services)} configured services")
        
        if service_index < 0 or service_index >= len(services):
            logger.error(f"Service index {service_index} out of range (0-{len(services)-1})")
            raise HTTPException(
                status_code=404,
                detail=f"Service index {service_index} not found. Available indices: 0-{len(services)-1}"
            )
        
        service_url = services[service_index]
        logger.info(f"Testing service at index {service_index}: {service_url[:50]}... (masked)")
        
        try:
            success, error, details = test_service(service_url)
            logger.info(f"Test result for service {service_index}: success={success}, error={error}, details={details}")
        except Exception as test_error:
            logger.error(f"Exception in test_service: {type(test_error).__name__}: {str(test_error)}", exc_info=True)
            raise HTTPException(
                status_code=500,
                detail=f"Error testing service: {str(test_error)}"
            )
        
        if success:
            return NotificationResponse(
                success=True,
                message=f"Test notification sent successfully",
                details=details
            )
        else:
            # Return 200 with success=False so frontend can display the error
            return NotificationResponse(
                success=False,
                message=error or "Failed to send test notification",
                details=details
            )
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in test_service_endpoint: {type(e).__name__}: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {type(e).__name__}: {str(e)}"
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

