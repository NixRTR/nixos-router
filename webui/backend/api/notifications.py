"""
Notification management API
"""
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from ..auth import get_current_user
from ..database import (
    get_db,
    NotificationRuleDB,
    NotificationStateDB,
    NotificationHistoryDB,
)
from ..models import (
    NotificationRule,
    NotificationRuleCreate,
    NotificationRuleUpdate,
    NotificationHistory,
    NotificationHistoryRecord,
    NotificationParameterMetadata,
)
from ..collectors.notifications import (
    list_parameter_metadata,
    get_parameter_definition,
    render_notification_template,
    determine_rule_level,
)
from ..utils.apprise import send_notification
from ..utils.redis_client import delete as redis_delete

router = APIRouter(prefix="/api/notifications", tags=["notifications"])


async def _invalidate_rules_cache():
    """Invalidate notification rules cache"""
    await redis_delete("notification_rules:enabled:ids")


def _serialize_rule(
    rule: NotificationRuleDB,
    state: Optional[NotificationStateDB],
) -> NotificationRule:
    return NotificationRule(
        id=rule.id,
        name=rule.name,
        enabled=rule.enabled,
        parameter_type=rule.parameter_type,
        parameter_config=rule.parameter_config,
        threshold_info=rule.threshold_info,
        threshold_warning=rule.threshold_warning,
        threshold_failure=rule.threshold_failure,
        comparison_operator=rule.comparison_operator,
        duration_seconds=rule.duration_seconds,
        cooldown_seconds=rule.cooldown_seconds,
        apprise_service_indices=list(rule.apprise_service_indices or []),
        message_template=rule.message_template,
        created_at=rule.created_at,
        updated_at=rule.updated_at,
        current_level=state.current_level if state else None,
        last_notification_at=state.last_notification_at if state else None,
        last_notification_level=state.last_notification_level if state else None,
    )


async def _load_rule(
    db: AsyncSession,
    rule_id: int,
) -> NotificationRuleDB:
    rule = await db.get(NotificationRuleDB, rule_id)
    if not rule:
        raise HTTPException(status_code=404, detail="Notification rule not found")
    return rule


@router.get("/rules", response_model=List[NotificationRule])
async def list_rules(
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> List[NotificationRule]:
    stmt = (
        select(NotificationRuleDB, NotificationStateDB)
        .join(
            NotificationStateDB,
            NotificationStateDB.rule_id == NotificationRuleDB.id,
            isouter=True,
        )
        .order_by(NotificationRuleDB.id.asc())
    )
    result = await db.execute(stmt)
    items: List[NotificationRule] = []
    for rule, state in result.all():
        items.append(_serialize_rule(rule, state))
    return items


@router.get("/rules/{rule_id}", response_model=NotificationRule)
async def get_rule(
    rule_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationRule:
    stmt = (
        select(NotificationRuleDB, NotificationStateDB)
        .join(
            NotificationStateDB,
            NotificationStateDB.rule_id == NotificationRuleDB.id,
            isouter=True,
        )
        .where(NotificationRuleDB.id == rule_id)
    )
    result = await db.execute(stmt)
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Notification rule not found")
    rule, state = row
    return _serialize_rule(rule, state)


@router.post("/rules", response_model=NotificationRule, status_code=201)
async def create_rule(
    payload: NotificationRuleCreate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationRule:
    rule = NotificationRuleDB(
        name=payload.name,
        enabled=payload.enabled,
        parameter_type=payload.parameter_type,
        parameter_config=payload.parameter_config,
        threshold_info=payload.threshold_info,
        threshold_warning=payload.threshold_warning,
        threshold_failure=payload.threshold_failure,
        comparison_operator=payload.comparison_operator,
        duration_seconds=payload.duration_seconds,
        cooldown_seconds=payload.cooldown_seconds,
        apprise_service_indices=payload.apprise_service_indices,
        message_template=payload.message_template,
    )
    db.add(rule)
    await db.flush()
    await _invalidate_rules_cache()  # Invalidate cache after creation
    return _serialize_rule(rule, None)


@router.put("/rules/{rule_id}", response_model=NotificationRule)
async def update_rule(
    rule_id: int,
    payload: NotificationRuleUpdate,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationRule:
    rule = await _load_rule(db, rule_id)

    for field in [
        "name",
        "enabled",
        "parameter_type",
        "parameter_config",
        "threshold_info",
        "threshold_warning",
        "threshold_failure",
        "comparison_operator",
        "duration_seconds",
        "cooldown_seconds",
        "message_template",
    ]:
        value = getattr(payload, field)
        if value is not None:
            setattr(rule, field, value)

    if payload.apprise_service_indices is not None:
        rule.apprise_service_indices = payload.apprise_service_indices

    await db.flush()
    await _invalidate_rules_cache()  # Invalidate cache after update
    state = await db.get(NotificationStateDB, rule.id)
    return _serialize_rule(rule, state)


@router.delete("/rules/{rule_id}", status_code=204)
async def delete_rule(
    rule_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    rule = await _load_rule(db, rule_id)
    await db.delete(rule)
    await db.flush()
    await _invalidate_rules_cache()  # Invalidate cache after deletion


@router.get("/rules/{rule_id}/history", response_model=NotificationHistory)
async def get_rule_history(
    rule_id: int,
    limit: int = Query(50, ge=1, le=500),
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> NotificationHistory:
    await _load_rule(db, rule_id)
    stmt = (
        select(NotificationHistoryDB)
        .where(NotificationHistoryDB.rule_id == rule_id)
        .order_by(NotificationHistoryDB.timestamp.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    records: List[NotificationHistoryRecord] = []
    for history in result.scalars():
        records.append(
            NotificationHistoryRecord(
                id=history.id,
                rule_id=history.rule_id,
                timestamp=history.timestamp,
                level=history.level,
                value=history.value,
                message=history.message,
                sent_successfully=history.sent_successfully,
            )
        )
    return NotificationHistory(rule_id=rule_id, items=records)


@router.get("/parameters", response_model=List[NotificationParameterMetadata])
async def get_parameter_definitions(
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> List[NotificationParameterMetadata]:
    return await list_parameter_metadata(db)


@router.post("/rules/{rule_id}/test")
async def test_rule(
    rule_id: int,
    _: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    rule = await _load_rule(db, rule_id)
    definition = get_parameter_definition(rule.parameter_type)
    if not definition or not definition.fetcher:
        raise HTTPException(status_code=400, detail="Parameter type is not supported")

    value, context = await definition.fetcher(db, rule.parameter_config)
    if value is None:
        raise HTTPException(status_code=400, detail="Unable to load parameter value")

    measurement_ts = context.get("timestamp")
    if not measurement_ts:
        measurement_ts = datetime.now(timezone.utc)
        context["timestamp"] = measurement_ts

    level = determine_rule_level(rule, value) or "info"
    message = render_notification_template(context, rule, value, level, measurement_ts)
    success, error = send_notification(
        body=message,
        title=f"{rule.name} ({level.upper()})",
        notification_type=level,
        service_indices=rule.apprise_service_indices or None,
    )

    return {
        "success": success,
        "level": level,
        "value": value,
        "message": message,
        "error": error,
    }
