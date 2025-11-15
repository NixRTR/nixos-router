"""
Application configuration using Pydantic Settings
"""
from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application settings"""
    
    # Application
    app_name: str = "Router WebUI"
    debug: bool = False
    
    # Server
    host: str = "0.0.0.0"
    port: int = 8080
    
    # Database
    database_url: str = "postgresql+asyncpg://router_webui:password@localhost/router_webui"
    
    # JWT Authentication
    jwt_secret_key: str = "change-this-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 60 * 24  # 24 hours
    
    # Data Collection
    collection_interval: int = 2  # seconds
    
    # System Paths
    kea_lease_file: str = "/var/lib/kea/dhcp4.leases"
    router_config_file: str = "/etc/nixos/router-config.nix"
    unbound_control_path: str = "/run/unbound/control"
    
    # Historical Data Retention
    metrics_retention_days: int = 30
    
    # CORS
    cors_origins: list = ["http://localhost:3000", "http://localhost:5173"]
    
    class Config:
        env_file = "/etc/router-webui/config.env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()

