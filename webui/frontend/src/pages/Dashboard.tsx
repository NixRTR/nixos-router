/**
 * Main Dashboard page
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Progress, Badge, Table } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function Dashboard() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  const { connectionStatus, system, interfaces, services } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${days}d ${hours}h ${mins}m`;
  };

  const formatBytes = (bytes: number) => {
    const gb = bytes / (1024 * 1024 * 1024);
    return gb.toFixed(2) + ' GB';
  };

  // Filter to only show main interfaces
  const mainInterfaces = interfaces.filter(iface => 
    ['ppp0', 'br0', 'br1'].includes(iface.interface)
  );

  // Get friendly names for interfaces
  const getInterfaceName = (iface: string) => {
    switch (iface) {
      case 'ppp0': return 'WAN';
      case 'br0': return 'HOMELAB';
      case 'br1': return 'LAN';
      default: return iface;
    }
  };

  const getInterfaceColor = (iface: string) => {
    switch (iface) {
      case 'ppp0': return 'info';
      case 'br0': return 'success';
      case 'br1': return 'purple';
      default: return 'gray';
    }
  };

  return (
    <div className="flex h-screen">
      <Sidebar 
        onLogout={handleLogout}
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
      />
      
      <div className="flex-1 flex flex-col overflow-hidden">
        <Navbar
          hostname="nixos-router"
          username={username}
          connectionStatus={connectionStatus}
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
        />
        
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50 dark:bg-gray-900">
          <h1 className="text-3xl font-bold mb-6">Dashboard</h1>
          
          {/* System Stats Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <Card>
              <h3 className="text-lg font-semibold mb-2">CPU Usage</h3>
              <div className="text-3xl font-bold mb-2">
                {system?.cpu_percent.toFixed(1)}%
              </div>
              <Progress
                progress={system?.cpu_percent || 0}
                color={
                  (system?.cpu_percent || 0) > 80
                    ? 'red'
                    : (system?.cpu_percent || 0) > 60
                    ? 'yellow'
                    : 'blue'
                }
              />
            </Card>

            <Card>
              <h3 className="text-lg font-semibold mb-2">Memory Usage</h3>
              <div className="text-3xl font-bold mb-2">
                {system?.memory_percent.toFixed(1)}%
              </div>
              <Progress
                progress={system?.memory_percent || 0}
                color={
                  (system?.memory_percent || 0) > 80
                    ? 'red'
                    : (system?.memory_percent || 0) > 60
                    ? 'yellow'
                    : 'blue'
                }
              />
              <div className="text-sm text-gray-500 mt-1">
                {system && `${(system.memory_used_mb / 1024).toFixed(1)} / ${(system.memory_total_mb / 1024).toFixed(1)} GB`}
              </div>
            </Card>

            <Card>
              <h3 className="text-lg font-semibold mb-2">Load Average</h3>
              <div className="text-3xl font-bold mb-2">
                {system?.load_avg_1m.toFixed(2)}
              </div>
              <div className="text-sm text-gray-500">
                5min: {system?.load_avg_5m.toFixed(2)} | 15min: {system?.load_avg_15m.toFixed(2)}
              </div>
            </Card>

            <Card>
              <h3 className="text-lg font-semibold mb-2">Uptime</h3>
              <div className="text-2xl font-bold">
                {system && formatUptime(system.uptime_seconds)}
              </div>
            </Card>
          </div>

          {/* Network Interfaces */}
          <Card className="mb-6">
            <h3 className="text-xl font-semibold mb-4">Network Interfaces</h3>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {mainInterfaces.map((iface) => (
                <div key={iface.interface} className="border rounded-lg p-4">
                  <div className="flex justify-between items-center mb-2">
                    <div className="flex items-center gap-2">
                      <h4 className="font-semibold">{getInterfaceName(iface.interface)}</h4>
                      <Badge color={getInterfaceColor(iface.interface)} size="sm">
                        {iface.interface}
                      </Badge>
                    </div>
                    <Badge color="success" size="sm">UP</Badge>
                  </div>
                  <div className="text-sm space-y-1">
                    <div className="flex justify-between">
                      <span>↓ Download:</span>
                      <span className="font-mono">
                        {iface.rx_rate_mbps?.toFixed(2) || '0.00'} Mbps
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span>↑ Upload:</span>
                      <span className="font-mono">
                        {iface.tx_rate_mbps?.toFixed(2) || '0.00'} Mbps
                      </span>
                    </div>
                    <div className="flex justify-between text-gray-500">
                      <span>Total:</span>
                      <span className="font-mono text-xs">
                        ↓{formatBytes(iface.rx_bytes)} ↑{formatBytes(iface.tx_bytes)}
                      </span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </Card>

          {/* Services Status */}
          <Card>
            <h3 className="text-xl font-semibold mb-4">Services Status</h3>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* Network Services */}
              <div>
                <h4 className="text-lg font-semibold mb-3">Network Services</h4>
                <Table>
                  <Table.Head>
                    <Table.HeadCell>Service</Table.HeadCell>
                    <Table.HeadCell>Status</Table.HeadCell>
                    <Table.HeadCell>PID</Table.HeadCell>
                    <Table.HeadCell>CPU</Table.HeadCell>
                    <Table.HeadCell>Memory</Table.HeadCell>
                  </Table.Head>
                  <Table.Body className="divide-y">
                    {[
                      { name: 'DHCP Server', service: 'kea-dhcp4-server' },
                      { name: 'Homelab DNS', service: 'unbound-homelab' },
                      { name: 'LAN DNS', service: 'unbound-lan' },
                      { name: 'PPPoE', service: 'pppd-eno1' },
                      { name: 'Dynamic DNS', service: 'linode-dyndns' },
                    ].map(({ name, service: serviceName }) => {
                      const service = services.find(s => s.service_name === serviceName);
                      const status = service 
                        ? (service.is_active ? 'Running' : (service.is_enabled ? 'Stopped' : 'Disabled'))
                        : 'Not Found';
                      const statusColor = service
                        ? (service.is_active ? 'success' : (service.is_enabled ? 'failure' : 'gray'))
                        : 'gray';
                      
                      return (
                        <Table.Row key={serviceName}>
                          <Table.Cell className="font-medium">{name}</Table.Cell>
                          <Table.Cell>
                            <Badge color={statusColor as any}>
                              {status}
                            </Badge>
                          </Table.Cell>
                          <Table.Cell>{service?.pid || '-'}</Table.Cell>
                          <Table.Cell>{service?.cpu_percent?.toFixed(1) || '-'}%</Table.Cell>
                          <Table.Cell>{service?.memory_mb?.toFixed(0) || '-'} MB</Table.Cell>
                        </Table.Row>
                      );
                    })}
                  </Table.Body>
                </Table>
              </div>

              {/* WebUI Services */}
              <div>
                <h4 className="text-lg font-semibold mb-3">WebUI Services</h4>
                <Table>
                  <Table.Head>
                    <Table.HeadCell>Service</Table.HeadCell>
                    <Table.HeadCell>Status</Table.HeadCell>
                    <Table.HeadCell>PID</Table.HeadCell>
                    <Table.HeadCell>CPU</Table.HeadCell>
                    <Table.HeadCell>Memory</Table.HeadCell>
                  </Table.Head>
                  <Table.Body className="divide-y">
                    {[
                      { name: 'Frontend', service: 'nginx' },
                      { name: 'Backend', service: 'router-webui-backend' },
                      { name: 'Database', service: 'postgresql' },
                      { name: 'Speedtest', service: 'speedtest', isOneshot: true },
                    ].map(({ name, service: serviceName, isOneshot = false }) => {
                      const service = services.find(s => s.service_name === serviceName);
                      let status: string;
                      let statusColor: string;
                      
                      if (!service) {
                        status = 'Not Found';
                        statusColor = 'gray';
                      } else if (isOneshot) {
                        // One-shot services: Running, Waiting, or Disabled
                        if (service.is_active) {
                          status = 'Running';
                          statusColor = 'success';
                        } else if (service.is_enabled) {
                          status = 'Waiting';
                          statusColor = 'warning';
                        } else {
                          status = 'Disabled';
                          statusColor = 'gray';
                        }
                      } else {
                        // Regular services: Running, Stopped, or Disabled
                        if (service.is_active) {
                          status = 'Running';
                          statusColor = 'success';
                        } else if (service.is_enabled) {
                          status = 'Stopped';
                          statusColor = 'failure';
                        } else {
                          status = 'Disabled';
                          statusColor = 'gray';
                        }
                      }
                      
                      return (
                        <Table.Row key={serviceName}>
                          <Table.Cell className="font-medium">{name}</Table.Cell>
                          <Table.Cell>
                            <Badge color={statusColor as any}>
                              {status}
                            </Badge>
                          </Table.Cell>
                          <Table.Cell>{service?.pid || '-'}</Table.Cell>
                          <Table.Cell>{service?.cpu_percent?.toFixed(1) || '-'}%</Table.Cell>
                          <Table.Cell>{service?.memory_mb?.toFixed(0) || '-'} MB</Table.Cell>
                        </Table.Row>
                      );
                    })}
                  </Table.Body>
                </Table>
              </div>
            </div>
          </Card>
        </main>
      </div>
    </div>
  );
}

