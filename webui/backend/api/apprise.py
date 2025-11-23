"""
Apprise API notification service endpoints
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional

from ..auth import get_current_user
from ..utils.apprise import is_apprise_enabled


router = APIRouter(prefix="/api/apprise", tags=["apprise"])


class AppriseStatus(BaseModel):
    """Apprise enabled/disabled status"""
    enabled: bool


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

