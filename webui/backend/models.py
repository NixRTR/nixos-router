"""
Pydantic models for data validation and serialization
"""
from datetime import datetime
from typing import Optional, List, Dict, Any, Literal
from enum import Enum
from pydantic import BaseModel, Field, field_validator
from ipaddress import IPv4Address
import re


class SystemMetrics(BaseModel):
    """System-wide metrics"""
    timestamp: datetime
    cpu_percent: float = Field(..., ge=0, le=100)
    memory_percent: float = Field(..., ge=0, le=100)
    memory_used_mb: int = Field(..., ge=0)
    memory_total_mb: int = Field(..., ge=0)
    load_avg_1m: float = Field(..., ge=0)
    load_avg_5m: float = Field(..., ge=0)
    load_avg_15m: float = Field(..., ge=0)
    uptime_seconds: int = Field(..., ge=0)


class InterfaceStats(BaseModel):
    """Network interface statistics"""
    timestamp: datetime
    interface: str = Field(..., min_length=1, max_length=32)
    rx_bytes: int = Field(..., ge=0)
    tx_bytes: int = Field(..., ge=0)
    rx_packets: int = Field(..., ge=0)
    tx_packets: int = Field(..., ge=0)
    rx_errors: int = Field(..., ge=0)
    tx_errors: int = Field(..., ge=0)
    rx_dropped: int = Field(..., ge=0)
    tx_dropped: int = Field(..., ge=0)
    rx_rate_mbps: Optional[float] = Field(default=None, ge=0)
    tx_rate_mbps: Optional[float] = Field(default=None, ge=0)


class DHCPLease(BaseModel):
    """DHCP lease information"""
    network: str = Field(..., pattern="^(homelab|lan)$")
    ip_address: str
    mac_address: str
    hostname: Optional[str] = None
    lease_start: Optional[datetime] = None
    lease_end: Optional[datetime] = None
    last_seen: datetime
    is_static: bool = False

    @field_validator('mac_address')
    @classmethod
    def validate_mac(cls, v: str) -> str:
        """Validate MAC address format"""
        mac_pattern = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
        if not re.match(mac_pattern, v):
            raise ValueError('Invalid MAC address format')
        return v.lower().replace('-', ':')

    @field_validator('ip_address')
    @classmethod
    def validate_ip(cls, v: str) -> str:
        """Validate IP address"""
        try:
            IPv4Address(v)
            return v
        except ValueError:
            raise ValueError('Invalid IPv4 address')


class ServiceStatus(BaseModel):
    """Systemd service status"""
    timestamp: datetime
    service_name: str = Field(..., min_length=1, max_length=128)
    is_active: bool
    is_enabled: bool
    pid: Optional[int] = Field(default=None, ge=0)
    memory_mb: Optional[float] = Field(default=None, ge=0)
    cpu_percent: Optional[float] = Field(default=None, ge=0)


class DNSMetrics(BaseModel):
    """DNS server metrics from Unbound"""
    timestamp: datetime
    instance: str = Field(..., pattern="^(homelab|lan)$")
    total_queries: int = Field(..., ge=0)
    cache_hits: int = Field(..., ge=0)
    cache_misses: int = Field(..., ge=0)
    blocked_queries: int = Field(..., ge=0)
    queries_per_second: float = Field(..., ge=0)
    cache_hit_rate: float = Field(..., ge=0, le=100)


class MetricsSnapshot(BaseModel):
    """Complete snapshot of all metrics for WebSocket broadcast"""
    timestamp: datetime
    system: SystemMetrics
    interfaces: List[InterfaceStats]
    services: List[ServiceStatus]
    dhcp_clients: List[DHCPLease]
    dns_stats: List[DNSMetrics]


class HistoryQuery(BaseModel):
    """Query parameters for historical data"""
    start: datetime
    end: datetime
    interval: Optional[int] = Field(default=60, ge=1, le=3600)  # seconds


class LoginRequest(BaseModel):
    """Login request"""
    username: str = Field(..., min_length=1, max_length=64)
    password: str = Field(..., min_length=1)


class LoginResponse(BaseModel):
    """Login response"""
    access_token: str
    token_type: str = "bearer"
    username: str


class ConfigChange(BaseModel):
    """Configuration change request (Stage 2)"""
    change_type: str = Field(..., pattern="^(dhcp|dns|firewall|network)$")
    change_data: Dict[str, Any]


class ConfigChangeResponse(BaseModel):
    """Configuration change response"""
    id: int
    timestamp: datetime
    applied: bool
    error_message: Optional[str] = None


class DiskIOMetrics(BaseModel):
    """Disk I/O statistics"""
    timestamp: datetime
    device: str
    read_bytes_per_sec: float = Field(..., ge=0)
    write_bytes_per_sec: float = Field(..., ge=0)
    read_ops_per_sec: float = Field(..., ge=0)
    write_ops_per_sec: float = Field(..., ge=0)


class DiskSpaceMetrics(BaseModel):
    """Disk space usage"""
    timestamp: datetime
    mountpoint: str
    device: str
    total_gb: float = Field(..., ge=0)
    used_gb: float = Field(..., ge=0)
    free_gb: float = Field(..., ge=0)
    percent_used: float = Field(..., ge=0, le=100)


class TemperatureMetrics(BaseModel):
    """Temperature sensor readings"""
    timestamp: datetime
    sensor_name: str
    temperature_c: float
    label: Optional[str] = None
    critical: Optional[float] = None


class FanMetrics(BaseModel):
    """Fan speed readings"""
    timestamp: datetime
    fan_name: str
    rpm: int = Field(..., ge=0)
    label: Optional[str] = None


class ClientStats(BaseModel):
    """Network client statistics"""
    timestamp: datetime
    network: str = Field(..., pattern="^(homelab|lan)$")
    dhcp_clients: int = Field(..., ge=0)
    static_clients: int = Field(..., ge=0)
    total_clients: int = Field(..., ge=0)
    online_clients: int = Field(..., ge=0)
    offline_clients: int = Field(..., ge=0)


class NetworkDevice(BaseModel):
    """Network device information"""
    network: str
    mac_address: str
    ip_address: str
    hostname: Optional[str] = None
    vendor: Optional[str] = None
    is_dhcp: bool = False
    is_static: bool = False
    is_online: bool = True
    first_seen: datetime
    last_seen: datetime
    
    class Config:
        from_attributes = True


class ClientBandwidthStats(BaseModel):
    """Per-client bandwidth statistics"""
    timestamp: datetime
    mac_address: str
    ip_address: str
    network: str = Field(..., pattern="^(homelab|lan)$")
    rx_bytes: int = Field(..., ge=0)  # download bytes in this interval
    tx_bytes: int = Field(..., ge=0)  # upload bytes in this interval
    rx_bytes_total: int = Field(..., ge=0)  # cumulative download
    tx_bytes_total: int = Field(..., ge=0)  # cumulative upload
    
    @field_validator('mac_address')
    @classmethod
    def validate_mac(cls, v: str) -> str:
        """Validate MAC address format"""
        mac_pattern = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
        if not re.match(mac_pattern, v):
            raise ValueError('Invalid MAC address format')
        return v.lower().replace('-', ':')
    
    @field_validator('ip_address')
    @classmethod
    def validate_ip(cls, v: str) -> str:
        """Validate IP address"""
        try:
            IPv4Address(v)
            return v
        except ValueError:
            raise ValueError('Invalid IPv4 address')


class ClientBandwidthDataPoint(BaseModel):
    """Single data point for client bandwidth history"""
    timestamp: datetime
    rx_mbps: float = Field(..., ge=0)
    tx_mbps: float = Field(..., ge=0)
    rx_bytes: int = Field(..., ge=0)
    tx_bytes: int = Field(..., ge=0)


class ClientBandwidthHistory(BaseModel):
    """Bandwidth history for a client"""
    mac_address: str
    ip_address: str
    network: str
    data: List[ClientBandwidthDataPoint]


class ClientBandwidthCurrent(BaseModel):
    """Current bandwidth stats for a client"""
    mac_address: str
    ip_address: str
    network: str
    hostname: Optional[str] = None
    rx_mbps: float = Field(..., ge=0)
    tx_mbps: float = Field(..., ge=0)
    rx_bytes_total: int = Field(..., ge=0)
    tx_bytes_total: int = Field(..., ge=0)
    last_updated: datetime


class ClientConnectionStats(BaseModel):
    """Per-connection bandwidth statistics"""
    timestamp: datetime
    client_ip: str
    client_mac: str
    remote_ip: str
    remote_port: int = Field(..., ge=1, le=65535)
    rx_bytes: int = Field(..., ge=0)  # download bytes in this interval
    tx_bytes: int = Field(..., ge=0)  # upload bytes in this interval
    rx_bytes_total: int = Field(..., ge=0)  # cumulative download
    tx_bytes_total: int = Field(..., ge=0)  # cumulative upload
    aggregation_level: str = Field(default='raw', pattern="^(raw|1m|5m|1h|1d)$")
    
    @field_validator('client_ip', 'remote_ip')
    @classmethod
    def validate_ip(cls, v: str) -> str:
        """Validate IP address"""
        try:
            IPv4Address(v)
            return v
        except ValueError:
            raise ValueError('Invalid IPv4 address')
    
    @field_validator('client_mac')
    @classmethod
    def validate_mac(cls, v: str) -> str:
        """Validate MAC address format"""
        mac_pattern = r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
        if not re.match(mac_pattern, v):
            raise ValueError('Invalid MAC address format')
        return v.lower().replace('-', ':')


class ClientConnectionCurrent(BaseModel):
    """Current connection stats with hostname"""
    remote_ip: str
    remote_port: int
    hostname: Optional[str] = None
    download_mb: float = Field(..., ge=0)  # cumulative MB for time period
    download_mbps: float = Field(..., ge=0)  # peak rate in Mbit/s during time period
    upload_mb: float = Field(..., ge=0)  # cumulative MB for time period
    upload_mbps: float = Field(..., ge=0)  # peak rate in Mbit/s during time period


class ClientConnectionDataPoint(BaseModel):
    """Single data point for connection history"""
    timestamp: datetime
    rx_mbps: float = Field(..., ge=0)
    tx_mbps: float = Field(..., ge=0)
    rx_bytes: int = Field(..., ge=0)
    tx_bytes: int = Field(..., ge=0)


class ClientConnectionHistory(BaseModel):
    """Connection history for charting"""
    client_ip: str
    remote_ip: str
    remote_port: int
    data: List[ClientConnectionDataPoint]


class CakeTrafficClass(BaseModel):
    """CAKE traffic class statistics"""
    pk_delay_ms: Optional[float] = None  # Peak delay in milliseconds
    av_delay_ms: Optional[float] = None  # Average delay in milliseconds
    sp_delay_ms: Optional[float] = None  # Sparse delay in milliseconds
    bytes: Optional[int] = None          # Total bytes
    packets: Optional[int] = None        # Total packets
    drops: Optional[int] = None          # Dropped packets
    marks: Optional[int] = None          # ECN marks


class CakeStats(BaseModel):
    """CAKE traffic shaping statistics"""
    timestamp: datetime
    interface: str
    rate_mbps: Optional[float] = None        # Priority layer bandwidth threshold
    target_ms: Optional[float] = None        # AQM target delay
    interval_ms: Optional[float] = None      # AQM interval
    classes: Dict[str, CakeTrafficClass] = Field(default_factory=dict)  # Per-class stats
    way_inds: Optional[int] = None           # Hash indirect hits
    way_miss: Optional[int] = None           # Hash misses
    way_cols: Optional[int] = None           # Hash collisions


class CakeDataPoint(BaseModel):
    """Single data point for CAKE statistics history"""
    timestamp: datetime
    rate_mbps: Optional[float] = None
    target_ms: Optional[float] = None
    interval_ms: Optional[float] = None
    classes: Dict[str, CakeTrafficClass] = Field(default_factory=dict)
    way_inds: Optional[int] = None
    way_miss: Optional[int] = None
    way_cols: Optional[int] = None


class CakeStatsHistory(BaseModel):
    """Historical CAKE statistics"""
    interface: str
    data: List[CakeDataPoint]


class CakeStatus(BaseModel):
    """CAKE enabled/disabled status"""
    enabled: bool
    interface: Optional[str] = None


class ParameterType(str, Enum):
    """Supported notification parameter types"""
    CPU_PERCENT = "cpu_percent"
    MEMORY_PERCENT = "memory_percent"
    LOAD_AVG_1M = "load_avg_1m"
    LOAD_AVG_5M = "load_avg_5m"
    LOAD_AVG_15M = "load_avg_15m"
    INTERFACE_RX_BYTES = "interface_rx_bytes"
    INTERFACE_TX_BYTES = "interface_tx_bytes"
    INTERFACE_RX_ERRORS = "interface_rx_errors"
    INTERFACE_TX_ERRORS = "interface_tx_errors"
    TEMPERATURE_C = "temperature_c"
    SERVICE_ACTIVE = "service_active"
    SERVICE_ENABLED = "service_enabled"
    DISK_USAGE_PERCENT = "disk_usage_percent"


class NotificationParameterConfigField(BaseModel):
    """Configuration requirement for a parameter"""
    name: str
    label: str
    field_type: Literal['text', 'select'] = 'text'
    description: Optional[str] = None
    options: Optional[List[Dict[str, Any]]] = None


class NotificationParameterMetadata(BaseModel):
    """Metadata describing a parameter that can be monitored"""
    type: str
    label: str
    unit: Optional[str] = None
    description: Optional[str] = None
    requires_config: bool = False
    config_fields: List[NotificationParameterConfigField] = Field(default_factory=list)
    variables: List[str] = Field(default_factory=list)


class NotificationRuleBase(BaseModel):
    """Shared fields for notification rules"""
    name: str = Field(..., max_length=255)
    enabled: bool = True
    parameter_type: str = Field(..., max_length=64)
    parameter_config: Optional[Dict[str, Any]] = None
    threshold_info: Optional[float] = None
    threshold_warning: Optional[float] = None
    threshold_failure: Optional[float] = None
    comparison_operator: Literal['gt', 'lt'] = 'gt'
    duration_seconds: int = Field(..., gt=0)
    cooldown_seconds: int = Field(..., ge=0)
    apprise_service_indices: List[int] = Field(default_factory=list)
    message_template: str


class NotificationRuleCreate(NotificationRuleBase):
    """Request body for creating a notification rule"""
    pass


class NotificationRuleUpdate(BaseModel):
    """Request body for updating a notification rule"""
    name: Optional[str] = Field(default=None, max_length=255)
    enabled: Optional[bool] = None
    parameter_type: Optional[str] = Field(default=None, max_length=64)
    parameter_config: Optional[Dict[str, Any]] = None
    threshold_info: Optional[float] = None
    threshold_warning: Optional[float] = None
    threshold_failure: Optional[float] = None
    comparison_operator: Optional[Literal['gt', 'lt']] = None
    duration_seconds: Optional[int] = Field(default=None, gt=0)
    cooldown_seconds: Optional[int] = Field(default=None, ge=0)
    apprise_service_indices: Optional[List[int]] = None
    message_template: Optional[str] = None


class NotificationRule(NotificationRuleBase):
    """Notification rule response model"""
    id: int
    created_at: datetime
    updated_at: datetime
    current_level: Optional[str] = None
    last_notification_at: Optional[datetime] = None
    last_notification_level: Optional[str] = None


class NotificationHistoryRecord(BaseModel):
    """Single notification history entry"""
    id: int
    rule_id: int
    timestamp: datetime
    level: str
    value: float
    message: Optional[str] = None
    sent_successfully: bool


class NotificationHistory(BaseModel):
    """Notification history list"""
    rule_id: int
    items: List[NotificationHistoryRecord]
