/**
 * TypeScript types matching backend Pydantic models
 */

export interface SystemMetrics {
  timestamp: string;
  cpu_percent: number;
  memory_percent: number;
  memory_used_mb: number;
  memory_total_mb: number;
  load_avg_1m: number;
  load_avg_5m: number;
  load_avg_15m: number;
  uptime_seconds: number;
}

export interface InterfaceStats {
  timestamp: string;
  interface: string;
  rx_bytes: number;
  tx_bytes: number;
  rx_packets: number;
  tx_packets: number;
  rx_errors: number;
  tx_errors: number;
  rx_dropped: number;
  tx_dropped: number;
  rx_rate_mbps?: number;
  tx_rate_mbps?: number;
}

export interface DHCPLease {
  network: 'homelab' | 'lan';
  ip_address: string;
  mac_address: string;
  hostname?: string;
  lease_start?: string;
  lease_end?: string;
  last_seen: string;
  is_static: boolean;
}

export interface ServiceStatus {
  timestamp: string;
  service_name: string;
  is_active: boolean;
  is_enabled: boolean;
  pid?: number;
  memory_mb?: number;
  cpu_percent?: number;
}

export interface DNSMetrics {
  timestamp: string;
  instance: 'homelab' | 'lan';
  total_queries: number;
  cache_hits: number;
  cache_misses: number;
  blocked_queries: number;
  queries_per_second: number;
  cache_hit_rate: number;
}

export interface MetricsSnapshot {
  timestamp: string;
  system: SystemMetrics;
  interfaces: InterfaceStats[];
  services: ServiceStatus[];
  dhcp_clients: DHCPLease[];
  dns_stats: DNSMetrics[];
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginResponse {
  access_token: string;
  token_type: string;
  username: string;
}

export interface HistoricalDataPoint {
  timestamp: string;
  [key: string]: number | string;
}

export type ConnectionStatus = 'connecting' | 'connected' | 'disconnected' | 'error';

