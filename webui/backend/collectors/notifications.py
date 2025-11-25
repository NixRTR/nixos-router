"""
Notification evaluation helpers and parameter definitions
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from ..database import (
    SystemMetricsDB,
    InterfaceStatsDB,
    TemperatureMetricsDB,
    ServiceStatusDB,
    NotificationRuleDB,
    NotificationStateDB,
    NotificationHistoryDB,
)
from ..models import (
    NotificationParameterConfigField,
    NotificationParameterMetadata,
    ParameterType,
)
from ..collectors.system import collect_disk_space
from ..utils.apprise import send_notification
from jinja2 import Environment, StrictUndefined, TemplateError

logger = logging.getLogger(__name__)
template_env = Environment(
    autoescape=False,
    trim_blocks=True,
    lstrip_blocks=True,
    undefined=StrictUndefined,
)

# Type alias for parameter fetcher functions
ParameterFetcher = Callable[
    [AsyncSession, Optional[Dict[str, Any]]],
    Awaitable[Tuple[Optional[float], Dict[str, any]]]
]


@dataclass(frozen=True)
class ParameterDefinition:
    """Definition for a monitorable parameter"""

    type: str
    label: str
    unit: Optional[str] = None
    description: Optional[str] = None
    requires_config: bool = False
    config_fields: List[NotificationParameterConfigField] = field(default_factory=list)
    variables: List[str] = field(default_factory=list)
    fetcher: Optional[ParameterFetcher] = None


def _system_metric_fetcher(column_name: str) -> ParameterFetcher:
    async def fetch(session: AsyncSession, _: Optional[Dict[str, Any]]) -> Tuple[Optional[float], Dict[str, Any]]:
        result = await session.execute(
            select(SystemMetricsDB.timestamp, getattr(SystemMetricsDB, column_name))
            .order_by(SystemMetricsDB.timestamp.desc())
            .limit(1)
        )
        row = result.first()
        if not row or row[1] is None:
            return None, {}
        return float(row[1]), {"timestamp": row[0]}

    return fetch


def _temperature_fetcher() -> ParameterFetcher:
    async def fetch(session: AsyncSession, config: Optional[Dict[str, Any]]) -> Tuple[Optional[float], Dict[str, Any]]:
        sensor = (config or {}).get("sensor_name")
        if not sensor:
            return None, {}
        result = await session.execute(
            select(TemperatureMetricsDB.timestamp, TemperatureMetricsDB.temperature_c)
            .where(TemperatureMetricsDB.sensor_name == sensor)
            .order_by(TemperatureMetricsDB.timestamp.desc())
            .limit(1)
        )
        row = result.first()
        if not row or row[1] is None:
            return None, {}
        return float(row[1]), {"timestamp": row[0], "sensor_name": sensor}

    return fetch


def _service_status_fetcher(field_name: str) -> ParameterFetcher:
    async def fetch(session: AsyncSession, config: Optional[Dict[str, Any]]) -> Tuple[Optional[float], Dict[str, Any]]:
        service = (config or {}).get("service_name")
        if not service:
            return None, {}
        result = await session.execute(
            select(ServiceStatusDB.timestamp, getattr(ServiceStatusDB, field_name))
            .where(ServiceStatusDB.service_name == service)
            .order_by(ServiceStatusDB.timestamp.desc())
            .limit(1)
        )
        row = result.first()
        if not row or row[1] is None:
            return None, {}
        value = 1.0 if bool(row[1]) else 0.0
        return value, {"timestamp": row[0], "service_name": service}

    return fetch


def _interface_rate_fetcher(column_name: str, unit_multiplier: float) -> ParameterFetcher:
    async def fetch(session: AsyncSession, config: Optional[Dict[str, Any]]) -> Tuple[Optional[float], Dict[str, Any]]:
        interface = (config or {}).get("interface")
        if not interface:
            return None, {}
        result = await session.execute(
            select(
                InterfaceStatsDB.timestamp,
                getattr(InterfaceStatsDB, column_name),
            )
            .where(InterfaceStatsDB.interface == interface)
            .order_by(InterfaceStatsDB.timestamp.desc())
            .limit(2)
        )
        rows = result.all()
        if len(rows) < 2:
            return None, {}

        latest, previous = rows[0], rows[1]
        latest_ts, latest_val = latest
        previous_ts, previous_val = previous

        if latest_val is None or previous_val is None:
            return None, {}

        time_delta = (latest_ts - previous_ts).total_seconds()
        if time_delta <= 0:
            return None, {}

        value_delta = latest_val - previous_val
        rate = (value_delta / time_delta) * unit_multiplier
        context = {
            "timestamp": latest_ts,
            "interface": interface,
            "delta": value_delta,
            "interval_seconds": time_delta,
        }
        return rate, context

    return fetch


def _disk_usage_fetcher() -> ParameterFetcher:
    async def fetch(_: AsyncSession, config: Optional[Dict[str, Any]]) -> Tuple[Optional[float], Dict[str, Any]]:
        mountpoint = (config or {}).get("mountpoint")
        if not mountpoint:
            return None, {}
        measurements = collect_disk_space()
        for disk in measurements:
            if disk.mountpoint == mountpoint:
                return float(disk.percent_used), {"mountpoint": mountpoint, "timestamp": disk.timestamp}
        return None, {"mountpoint": mountpoint}

    return fetch


PARAMETER_DEFINITIONS: Dict[str, ParameterDefinition] = {
    ParameterType.CPU_PERCENT.value: ParameterDefinition(
        type=ParameterType.CPU_PERCENT.value,
        label="CPU Usage",
        unit="%",
        description="Average CPU utilization percentage",
        variables=["system.cpu_percent"],
        fetcher=_system_metric_fetcher("cpu_percent"),
    ),
    ParameterType.MEMORY_PERCENT.value: ParameterDefinition(
        type=ParameterType.MEMORY_PERCENT.value,
        label="Memory Usage",
        unit="%",
        description="RAM usage percentage",
        variables=["system.memory_percent"],
        fetcher=_system_metric_fetcher("memory_percent"),
    ),
    ParameterType.LOAD_AVG_1M.value: ParameterDefinition(
        type=ParameterType.LOAD_AVG_1M.value,
        label="Load Average (1m)",
        unit="load",
        description="1 minute load average",
        variables=["system.load_avg_1m"],
        fetcher=_system_metric_fetcher("load_avg_1m"),
    ),
    ParameterType.LOAD_AVG_5M.value: ParameterDefinition(
        type=ParameterType.LOAD_AVG_5M.value,
        label="Load Average (5m)",
        unit="load",
        description="5 minute load average",
        variables=["system.load_avg_5m"],
        fetcher=_system_metric_fetcher("load_avg_5m"),
    ),
    ParameterType.LOAD_AVG_15M.value: ParameterDefinition(
        type=ParameterType.LOAD_AVG_15M.value,
        label="Load Average (15m)",
        unit="load",
        description="15 minute load average",
        variables=["system.load_avg_15m"],
        fetcher=_system_metric_fetcher("load_avg_15m"),
    ),
    ParameterType.INTERFACE_RX_BYTES.value: ParameterDefinition(
        type=ParameterType.INTERFACE_RX_BYTES.value,
        label="Interface RX Throughput",
        unit="Mbps",
        description="Inbound throughput for a specific interface (calculated from byte counters)",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="interface",
                label="Interface Name",
                description="Example: eth0",
            )
        ],
        variables=["interface", "rx_rate_mbps"],
        fetcher=_interface_rate_fetcher("rx_bytes", unit_multiplier=8 / 1_000_000),
    ),
    ParameterType.INTERFACE_TX_BYTES.value: ParameterDefinition(
        type=ParameterType.INTERFACE_TX_BYTES.value,
        label="Interface TX Throughput",
        unit="Mbps",
        description="Outbound throughput for a specific interface (calculated from byte counters)",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="interface",
                label="Interface Name",
                description="Example: eth0",
            )
        ],
        variables=["interface", "tx_rate_mbps"],
        fetcher=_interface_rate_fetcher("tx_bytes", unit_multiplier=8 / 1_000_000),
    ),
    ParameterType.INTERFACE_RX_ERRORS.value: ParameterDefinition(
        type=ParameterType.INTERFACE_RX_ERRORS.value,
        label="Interface RX Errors",
        unit="errors/sec",
        description="Receive errors per second for an interface",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="interface",
                label="Interface Name",
                description="Example: eth0",
            )
        ],
        variables=["interface", "rx_errors_per_sec"],
        fetcher=_interface_rate_fetcher("rx_errors", unit_multiplier=1.0),
    ),
    ParameterType.INTERFACE_TX_ERRORS.value: ParameterDefinition(
        type=ParameterType.INTERFACE_TX_ERRORS.value,
        label="Interface TX Errors",
        unit="errors/sec",
        description="Transmit errors per second for an interface",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="interface",
                label="Interface Name",
                description="Example: eth0",
            )
        ],
        variables=["interface", "tx_errors_per_sec"],
        fetcher=_interface_rate_fetcher("tx_errors", unit_multiplier=1.0),
    ),
    ParameterType.TEMPERATURE_C.value: ParameterDefinition(
        type=ParameterType.TEMPERATURE_C.value,
        label="Temperature Sensor",
        unit="°C",
        description="Temperature reading for a specific sensor",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="sensor_name",
                label="Sensor Name",
                description="Example: cpu_thermal or nvme0",
            )
        ],
        variables=["sensor_name", "temperature_c"],
        fetcher=_temperature_fetcher(),
    ),
    ParameterType.SERVICE_ACTIVE.value: ParameterDefinition(
        type=ParameterType.SERVICE_ACTIVE.value,
        label="Service Active State",
        unit="state",
        description="Whether a systemd service is currently active (1 = active, 0 = inactive)",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="service_name",
                label="Service Name",
                description="Example: router-webui-backend",
            )
        ],
        variables=["service_name", "service_active"],
        fetcher=_service_status_fetcher("is_active"),
    ),
    ParameterType.SERVICE_ENABLED.value: ParameterDefinition(
        type=ParameterType.SERVICE_ENABLED.value,
        label="Service Enabled State",
        unit="state",
        description="Whether a systemd service is enabled (1 = enabled, 0 = disabled)",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="service_name",
                label="Service Name",
                description="Example: router-webui-backend",
            )
        ],
        variables=["service_name", "service_enabled"],
        fetcher=_service_status_fetcher("is_enabled"),
    ),
    ParameterType.DISK_USAGE_PERCENT.value: ParameterDefinition(
        type=ParameterType.DISK_USAGE_PERCENT.value,
        label="Disk Usage",
        unit="%",
        description="Disk usage percentage for a mountpoint",
        requires_config=True,
        config_fields=[
            NotificationParameterConfigField(
                name="mountpoint",
                label="Mountpoint",
                description="Example: / or /var",
            )
        ],
        variables=["mountpoint", "disk_usage_percent"],
        fetcher=_disk_usage_fetcher(),
    ),
}


async def list_parameter_metadata(_: AsyncSession) -> List[NotificationParameterMetadata]:
    """Return metadata for all available parameters"""
    metadata: List[NotificationParameterMetadata] = []
    for definition in PARAMETER_DEFINITIONS.values():
        metadata.append(
            NotificationParameterMetadata(
                type=definition.type,
                label=definition.label,
                unit=definition.unit,
                description=definition.description,
                requires_config=definition.requires_config,
                config_fields=definition.config_fields,
                variables=[
                    "parameter_name",
                    "current_value",
                    "threshold_info",
                    "threshold_warning",
                    "threshold_failure",
                    "current_level",
                    "timestamp",
                    *definition.variables,
                ],
            )
        )
    return metadata


def get_parameter_definition(parameter_type: str) -> Optional[ParameterDefinition]:
    """Lookup a parameter definition by type"""
    return PARAMETER_DEFINITIONS.get(parameter_type)


SEVERITY_ORDER = {"info": 1, "warning": 2, "failure": 3}


def determine_rule_level(rule: NotificationRuleDB, value: float) -> Optional[str]:
    comparisons = [
        ("failure", rule.threshold_failure),
        ("warning", rule.threshold_warning),
        ("info", rule.threshold_info),
    ]
    for level_name, threshold in comparisons:
        if threshold is None:
            continue
        if rule.comparison_operator == "gt":
            if value >= threshold:
                return level_name
        else:
            if value <= threshold:
                return level_name
    return None


class NotificationEvaluator:
    """Evaluates notification rules and sends alerts when thresholds are exceeded"""

    def __init__(self, session_factory: async_sessionmaker[AsyncSession]):
        self.session_factory = session_factory

    async def evaluate_all(self) -> None:
        async with self.session_factory() as session:
            result = await session.execute(
                select(NotificationRuleDB).where(NotificationRuleDB.enabled.is_(True))
            )
            rules = result.scalars().all()
            for rule in rules:
                try:
                    await self._evaluate_rule(session, rule)
                except Exception as exc:
                    logger.error(
                        "Failed to evaluate notification rule %s (%s): %s",
                        rule.id,
                        rule.name,
                        exc,
                        exc_info=True,
                    )
            await session.commit()

    async def _evaluate_rule(self, session: AsyncSession, rule: NotificationRuleDB) -> None:
        definition = get_parameter_definition(rule.parameter_type)
        if not definition or not definition.fetcher:
            logger.warning("No parameter definition for %s", rule.parameter_type)
            return

        value, context = await definition.fetcher(session, rule.parameter_config)
        measurement_ts = context.get("timestamp") or datetime.now(timezone.utc)

        state = await session.get(NotificationStateDB, rule.id)
        if not state:
            state = NotificationStateDB(rule_id=rule.id, current_level="normal")
            session.add(state)
            await session.flush()

        if value is None:
            state.current_level = "normal"
            state.threshold_exceeded_at = None
            await session.flush()
            return

        target_level = determine_rule_level(rule, value)
        now = datetime.now(timezone.utc)

        if not target_level:
            state.current_level = "normal"
            state.threshold_exceeded_at = None
            await session.flush()
            return

        exceeded_at = state.threshold_exceeded_at
        if state.current_level != target_level or exceeded_at is None:
            exceeded_at = now

        state.current_level = target_level
        state.threshold_exceeded_at = exceeded_at

        duration_met = (now - exceeded_at) >= timedelta(seconds=rule.duration_seconds)
        if not duration_met:
            await session.flush()
            return

        cooldown_met = True
        bypass_cooldown = False
        if state.last_notification_at:
            elapsed = (now - state.last_notification_at).total_seconds()
            cooldown_met = elapsed >= rule.cooldown_seconds
            last_level_rank = SEVERITY_ORDER.get(state.last_notification_level or "", 0)
            current_rank = SEVERITY_ORDER.get(target_level, 0)
            bypass_cooldown = current_rank > last_level_rank

        if not cooldown_met and not bypass_cooldown:
            await session.flush()
            return

        rendered_message = render_notification_template(
            context,
            rule,
            value,
            target_level,
            measurement_ts,
        )

        success, error = send_notification(
            body=rendered_message,
            title=f"{rule.name} ({target_level.upper()})",
            notification_type=target_level,
            service_indices=rule.apprise_service_indices or None,
        )

        history = NotificationHistoryDB(
            rule_id=rule.id,
            timestamp=measurement_ts,
            level=target_level,
            value=value,
            message=rendered_message,
            sent_successfully=success,
        )
        session.add(history)

        state.last_notification_at = now
        state.last_notification_level = target_level

        if not success and error:
            logger.error(
                "Failed to send notification for rule %s (%s): %s",
                rule.id,
                rule.name,
                error,
            )

        await session.flush()

def render_notification_template(
    context: Dict[str, Any],
    rule: NotificationRuleDB,
    value: float,
    current_level: str,
    measurement_ts: datetime,
) -> str:
    definition = get_parameter_definition(rule.parameter_type)
    parameter_label = definition.label if definition else rule.parameter_type
    template = template_env.from_string(rule.message_template)
    payload = {
        "parameter_name": parameter_label,
        "parameter_type": rule.parameter_type,
        "parameter_config": rule.parameter_config or {},
        "current_value": value,
        "current_level": current_level,
        "threshold_info": rule.threshold_info,
        "threshold_warning": rule.threshold_warning,
        "threshold_failure": rule.threshold_failure,
        "timestamp": measurement_ts,
    }
    payload.update(context)

    try:
        return template.render(payload)
    except TemplateError as exc:
        logger.error(
            "Failed to render notification template for rule %s: %s",
            rule.id,
            exc,
        )
        return (
            f"{rule.name}: level={current_level} value={value} "
            f"(template error: {exc})"
        )

