/**
 * Custom hook for consuming WebSocket metrics data
 */
import { useEffect, useState } from 'react';
import { useWebSocket } from './useWebSocket';
import type {
  MetricsSnapshot,
  SystemMetrics,
  InterfaceStats,
  ServiceStatus,
  DHCPLease,
  DNSMetrics,
  ConnectionStatus,
} from '../types/metrics';

interface UseMetricsReturn {
  connectionStatus: ConnectionStatus;
  system: SystemMetrics | null;
  interfaces: InterfaceStats[];
  services: ServiceStatus[];
  dhcpClients: DHCPLease[];
  dnsStats: DNSMetrics[];
  interfaceHistory: Map<string, InterfaceStats[]>;
}

const MAX_HISTORY_POINTS = 60; // Keep last 60 data points for sparklines

export function useMetrics(token: string | null): UseMetricsReturn {
  const { connectionStatus, lastMessage } = useWebSocket(token);

  const [system, setSystem] = useState<SystemMetrics | null>(null);
  const [interfaces, setInterfaces] = useState<InterfaceStats[]>([]);
  const [services, setServices] = useState<ServiceStatus[]>([]);
  const [dhcpClients, setDhcpClients] = useState<DHCPLease[]>([]);
  const [dnsStats, setDnsStats] = useState<DNSMetrics[]>([]);
  const [interfaceHistory, setInterfaceHistory] = useState<Map<string, InterfaceStats[]>>(
    new Map()
  );

  useEffect(() => {
    if (!lastMessage) return;

    try {
      const message = JSON.parse(lastMessage.data);

      if (message.type === 'metrics' && message.data) {
        const snapshot = message.data as MetricsSnapshot;

        // Update current metrics
        setSystem(snapshot.system);
        setInterfaces(snapshot.interfaces);
        setServices(snapshot.services);
        setDhcpClients(snapshot.dhcp_clients);
        setDnsStats(snapshot.dns_stats);

        // Update interface history for sparklines
        setInterfaceHistory((prev) => {
          const newHistory = new Map(prev);

          snapshot.interfaces.forEach((iface) => {
            const history = newHistory.get(iface.interface) || [];
            const updatedHistory = [...history, iface].slice(-MAX_HISTORY_POINTS);
            newHistory.set(iface.interface, updatedHistory);
          });

          return newHistory;
        });
      }
    } catch (error) {
      console.error('Failed to parse WebSocket message:', error);
    }
  }, [lastMessage]);

  return {
    connectionStatus,
    system,
    interfaces,
    services,
    dhcpClients,
    dnsStats,
    interfaceHistory,
  };
}

