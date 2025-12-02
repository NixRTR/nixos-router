/**
 * DNS zone and record types
 */

export interface DnsZone {
  id: number;
  name: string;
  network: 'homelab' | 'lan';
  authoritative: boolean;
  forward_to: string | null;
  delegate_to: string | null;
  enabled: boolean;
  original_config_path: string | null;
  created_at: string;
  updated_at: string;
}

export interface DnsZoneCreate {
  name: string;
  network: 'homelab' | 'lan';
  authoritative?: boolean;
  forward_to?: string | null;
  delegate_to?: string | null;
  enabled?: boolean;
  original_config_path?: string | null;
}

export interface DnsZoneUpdate {
  name?: string;
  network?: 'homelab' | 'lan';
  authoritative?: boolean;
  forward_to?: string | null;
  delegate_to?: string | null;
  enabled?: boolean;
}

export interface DnsRecord {
  id: number;
  zone_id: number;
  name: string;
  type: 'A' | 'CNAME';
  value: string;
  comment: string | null;
  enabled: boolean;
  original_config_path: string | null;
  created_at: string;
  updated_at: string;
}

export interface DnsRecordCreate {
  zone_id: number;
  name: string;
  type: 'A' | 'CNAME';
  value: string;
  comment?: string | null;
  enabled?: boolean;
  original_config_path?: string | null;
}

export interface DnsRecordUpdate {
  name?: string;
  type?: 'A' | 'CNAME';
  value?: string;
  comment?: string | null;
  enabled?: boolean;
  zone_id?: number;
}

