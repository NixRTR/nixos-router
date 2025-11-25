"""
Apprise API notification service endpoints
"""
import logging
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import Optional, List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth import get_current_user
from ..database import AsyncSessionLocal, AppriseServiceDB, get_db
from ..models import AppriseService, AppriseServiceCreate, AppriseServiceUpdate, AppriseServiceInfo
from ..utils.apprise import (
    is_apprise_enabled,
    send_notification,
    get_configured_services,
    get_raw_service_urls,
    load_apprise_config,
    test_service,
    url_encode_password_in_url
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
    """Information about a configured service (legacy - for backward compatibility)"""
    url: str
    description: str


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


@router.get("/services", response_model=List[AppriseServiceInfo])
async def get_services(
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> List[AppriseServiceInfo]:
    """Get list of configured notification services from database
    
    Returns:
        List of service info (id, name, description) - no URLs exposed
    """
    if not is_apprise_enabled():
        return []
    
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.enabled == True).order_by(AppriseServiceDB.name)
    )
    services = result.scalars().all()
    
    return [AppriseServiceInfo(
        id=service.id,
        name=service.name,
        description=service.description,
        enabled=service.enabled
    ) for service in services]


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
        services = get_raw_service_urls()
        logger.debug(f"Found {len(services)} configured services")
        
        if service_index < 0 or service_index >= len(services):
            logger.error(f"Service index {service_index} out of range (0-{len(services)-1})")
            raise HTTPException(
                status_code=404,
                detail=f"Service index {service_index} not found. Available indices: 0-{len(services)-1}"
            )
        
        service_url = services[service_index]['url']
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
        services = get_raw_service_urls()
        logger.debug(f"Found {len(services)} configured services")
        
        if service_index < 0 or service_index >= len(services):
            logger.error(f"Service index {service_index} out of range (0-{len(services)-1})")
            raise HTTPException(
                status_code=404,
                detail=f"Service index {service_index} not found. Available indices: 0-{len(services)-1}"
            )
        
        service_url = services[service_index]['url']
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


@router.post("/services", response_model=AppriseService)
async def create_service(
    service: AppriseServiceCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> AppriseService:
    """Create a new Apprise service
    
    Args:
        service: Service creation data (name, description, url)
        
    Returns:
        Created service with ID
    """
    if not is_apprise_enabled():
        raise HTTPException(
            status_code=503,
            detail="Apprise is not enabled"
        )
    
    # Validate URL by trying to create Apprise object
    try:
        from apprise import Apprise
        apobj = Apprise()
        encoded_url = url_encode_password_in_url(service.url)
        apobj.add(encoded_url)
        if len(apobj) == 0:
            raise HTTPException(
                status_code=400,
                detail="Invalid service URL format"
            )
    except Exception as e:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid service URL: {str(e)}"
        )
    
    # Create service in database
    db_service = AppriseServiceDB(
        name=service.name,
        description=service.description,
        url=service.url,
        enabled=True
    )
    db.add(db_service)
    await db.commit()
    await db.refresh(db_service)
    
    return AppriseService(
        id=db_service.id,
        name=db_service.name,
        description=db_service.description,
        url=db_service.url,
        original_secret_string=db_service.original_secret_string,
        enabled=db_service.enabled,
        created_at=db_service.created_at,
        updated_at=db_service.updated_at
    )


@router.get("/services/{service_id}", response_model=AppriseService)
async def get_service(
    service_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> AppriseService:
    """Get a specific Apprise service by ID
    
    Args:
        service_id: Service ID
        
    Returns:
        Service details including URL
    """
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.id == service_id)
    )
    service = result.scalar_one_or_none()
    
    if not service:
        raise HTTPException(
            status_code=404,
            detail=f"Service {service_id} not found"
        )
    
    return AppriseService(
        id=service.id,
        name=service.name,
        description=service.description,
        url=service.url,
        original_secret_string=service.original_secret_string,
        enabled=service.enabled,
        created_at=service.created_at,
        updated_at=service.updated_at
    )


@router.put("/services/{service_id}", response_model=AppriseService)
async def update_service(
    service_id: int,
    service_update: AppriseServiceUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> AppriseService:
    """Update an Apprise service
    
    Args:
        service_id: Service ID
        service_update: Fields to update
        
    Returns:
        Updated service
    """
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.id == service_id)
    )
    service = result.scalar_one_or_none()
    
    if not service:
        raise HTTPException(
            status_code=404,
            detail=f"Service {service_id} not found"
        )
    
    # Validate URL if it's being updated
    if service_update.url is not None:
        try:
            from apprise import Apprise
            apobj = Apprise()
            encoded_url = url_encode_password_in_url(service_update.url)
            apobj.add(encoded_url)
            if len(apobj) == 0:
                raise HTTPException(
                    status_code=400,
                    detail="Invalid service URL format"
                )
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid service URL: {str(e)}"
            )
        service.url = service_update.url
    
    # Update other fields
    if service_update.name is not None:
        service.name = service_update.name
    if service_update.description is not None:
        service.description = service_update.description
    if service_update.enabled is not None:
        service.enabled = service_update.enabled
    
    await db.commit()
    await db.refresh(service)
    
    return AppriseService(
        id=service.id,
        name=service.name,
        description=service.description,
        url=service.url,
        original_secret_string=service.original_secret_string,
        enabled=service.enabled,
        created_at=service.created_at,
        updated_at=service.updated_at
    )


@router.delete("/services/{service_id}")
async def delete_service(
    service_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> dict:
    """Delete an Apprise service
    
    Args:
        service_id: Service ID
        
    Returns:
        Success message
    """
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.id == service_id)
    )
    service = result.scalar_one_or_none()
    
    if not service:
        raise HTTPException(
            status_code=404,
            detail=f"Service {service_id} not found"
        )
    
    # Check if service is used in notification rules
    from ..database import NotificationRuleDB
    result = await db.execute(
        select(NotificationRuleDB).where(
            NotificationRuleDB.apprise_service_indices.contains([service_id])
        )
    )
    rules_using_service = result.scalars().all()
    
    if rules_using_service:
        rule_names = [rule.name for rule in rules_using_service]
        raise HTTPException(
            status_code=400,
            detail=f"Cannot delete service: it is used in notification rules: {', '.join(rule_names)}"
        )
    
    await db.delete(service)
    await db.commit()
    
    return {"message": f"Service {service_id} deleted successfully"}


@router.post("/services/{service_id}/send", response_model=NotificationResponse)
async def send_to_service_by_id(
    service_id: int,
    request: NotificationRequest,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> NotificationResponse:
    """Send a notification to a specific service by ID
    
    Args:
        service_id: Service ID
        request: Notification request with body, optional title and type
        
    Returns:
        NotificationResponse: Success status and message
    """
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.id == service_id)
    )
    service = result.scalar_one_or_none()
    
    if not service:
        raise HTTPException(
            status_code=404,
            detail=f"Service {service_id} not found"
        )
    
    if not service.enabled:
        raise HTTPException(
            status_code=400,
            detail="Service is disabled"
        )
    
    try:
        success, error, details = test_service(
            service.url,
            body=request.body,
            title=request.title,
            notification_type=request.notification_type
        )
        
        if success:
            return NotificationResponse(
                success=True,
                message="Notification sent successfully",
                details=details
            )
        else:
            return NotificationResponse(
                success=False,
                message=error or "Failed to send notification",
                details=details
            )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error sending notification: {str(e)}"
        )


@router.post("/services/{service_id}/test", response_model=NotificationResponse)
async def test_service_by_id(
    service_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> NotificationResponse:
    """Test a specific notification service by ID
    
    Args:
        service_id: Service ID
        
    Returns:
        NotificationResponse: Success status and message
    """
    result = await db.execute(
        select(AppriseServiceDB).where(AppriseServiceDB.id == service_id)
    )
    service = result.scalar_one_or_none()
    
    if not service:
        raise HTTPException(
            status_code=404,
            detail=f"Service {service_id} not found"
        )
    
    if not service.enabled:
        raise HTTPException(
            status_code=400,
            detail="Service is disabled"
        )
    
    try:
        success, error, details = test_service(service.url)
        
        if success:
            return NotificationResponse(
                success=True,
                message="Test notification sent successfully",
                details=details
            )
        else:
            return NotificationResponse(
                success=False,
                message=error or "Failed to send test notification",
                details=details
            )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error testing service: {str(e)}"
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

