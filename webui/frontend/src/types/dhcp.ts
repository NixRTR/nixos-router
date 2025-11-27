/**
 * TypeScript types for DHCP management
 */

export type NetworkType = 'homelab' | 'lan';

export interface DhcpNetwork {
  id: number;
  network: NetworkType;
  enabled: boolean;
  start: string;  // IP address
  end: string;  // IP address
  lease_time: string;  // e.g., "1h", "1d", "86400"
  dns_servers: string[] | null;  // Array of IP addresses
  dynamic_domain: string | null;  // e.g., "dhcp.homelab.local"
  original_config_path: string | null;
  created_at: string;
  updated_at: string;
}

export interface DhcpNetworkCreate {
  network: NetworkType;
  enabled: boolean;
  start: string;
  end: string;
  lease_time: string;
  dns_servers?: string[] | null;
  dynamic_domain?: string | null;
  original_config_path?: string | null;
}

export interface DhcpNetworkUpdate {
  enabled?: boolean;
  start?: string;
  end?: string;
  lease_time?: string;
  dns_servers?: string[] | null;
  dynamic_domain?: string | null;
}

export interface DhcpReservation {
  id: number;
  network_id: number;
  hostname: string;
  hw_address: string;  // MAC address
  ip_address: string;  // IP address
  comment: string | null;
  enabled: boolean;
  original_config_path: string | null;
  created_at: string;
  updated_at: string;
}

export interface DhcpReservationCreate {
  network_id: number;
  hostname: string;
  hw_address: string;  // MAC address
  ip_address: string;  // IP address
  comment?: string | null;
  enabled?: boolean;
  original_config_path?: string | null;
}

export interface DhcpReservationUpdate {
  hostname?: string;
  hw_address?: string;
  ip_address?: string;
  comment?: string | null;
  enabled?: boolean;
  network_id?: number;
}

