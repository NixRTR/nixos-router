/**
 * Device Usage page - Shows per-client bandwidth statistics
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Table, Badge, Button, Modal, Select, Label, TextInput } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface NetworkDevice {
  network: string;
  ip_address: string;
  mac_address: string;
  hostname: string;
  nickname?: string | null;
  vendor: string | null;
  is_dhcp: boolean;
  is_static: boolean;
  is_online: boolean;
  last_seen: string;
}

interface BandwidthAverages {
  dl_5m: number;
  dl_30m: number;
  dl_1h: number;
  dl_1d: number;
  ul_5m: number;
  ul_30m: number;
  ul_1h: number;
  ul_1d: number;
}

interface ClientBandwidthDataPoint {
  timestamp: string;
  rx_mbps: number;
  tx_mbps: number;
  rx_bytes: number;
  tx_bytes: number;
}


export function DeviceUsage() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [devices, setDevices] = useState<NetworkDevice[]>([]);
  const [bandwidthAverages, setBandwidthAverages] = useState<Record<string, BandwidthAverages>>({});
  const [blockedV4, setBlockedV4] = useState<string[]>([]);
  const [blockedMacs, setBlockedMacs] = useState<string[]>([]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [chartModalOpen, setChartModalOpen] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState<NetworkDevice | null>(null);
  const [chartData, setChartData] = useState<ClientBandwidthDataPoint[]>([]);
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(10);
  const [chartInterval, setChartInterval] = useState('raw');
  const [tableTimeRange, setTableTimeRange] = useState('1h');
  const [tableCustomRange, setTableCustomRange] = useState('');
  const [interfaceStats, setInterfaceStats] = useState<Record<string, { rx_rate_mbps: number; tx_rate_mbps: number; rx_bytes: number; tx_bytes: number }>>({});
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch devices (filter to bridge subnets only)
  useEffect(() => {
    const fetchDevices = async () => {
      if (!token) return;
      
      try {
        const response = await fetch('/api/devices/all', {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data = await response.json();
          // Filter to only bridge subnets (192.168.2.x for br0/homelab, 192.168.3.x for br1/lan)
          const filtered = data.filter((d: NetworkDevice) => 
            d.ip_address.startsWith('192.168.2.') || d.ip_address.startsWith('192.168.3.')
          );
          setDevices(filtered);
        }
      } catch (error) {
        console.error('Failed to fetch devices:', error);
      }
    };
    
    fetchDevices();
    const interval = setInterval(fetchDevices, 10000);
    return () => clearInterval(interval);
  }, [token]);

  // Fetch interface stats
  useEffect(() => {
    const fetchInterfaceStats = async () => {
      if (!token) return;
      
      try {
        const stats = await apiClient.getCurrentInterfaceStats();
        setInterfaceStats(stats);
      } catch (error) {
        console.error('Failed to fetch interface stats:', error);
      }
    };
    
    fetchInterfaceStats();
    const interval = setInterval(fetchInterfaceStats, 5000);
    return () => clearInterval(interval);
  }, [token]);

  // Fetch blocked list
  useEffect(() => {
    const fetchBlocked = async () => {
      if (!token) return;
      try {
        const response = await fetch('/api/devices/blocked', {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        if (response.ok) {
          const data = await response.json();
          setBlockedV4(data.ipv4 || []);
          setBlockedMacs((data.macs || []).map((m: string) => m.toLowerCase()));
        }
      } catch (e) {
        // ignore
      }
    };
    fetchBlocked();
    const interval = setInterval(fetchBlocked, 10000);
    return () => clearInterval(interval);
  }, [token]);


  // Validate time range format (e.g., "1m", "5m", "10m", "30m", "1h", "3h", "6h", "12h", "1d", "1w", "1M", "1y")
  const validateTimeRange = (range: string): boolean => {
    if (!range || range.trim() === '') return false;
    const pattern = /^(\d+)([mhdwMy])$/i;
    return pattern.test(range.trim());
  };

  // Fetch and calculate time period averages for the selected table time range
  useEffect(() => {
    const fetchAverages = async () => {
      if (!token) return;
      
      const range = tableTimeRange === 'custom' ? tableCustomRange : tableTimeRange;
      if (!range || (tableTimeRange === 'custom' && !validateTimeRange(range))) {
        setBandwidthAverages({});
        return;
      }
      
      try {
        // Fetch bulk data for the selected time period
        // Use appropriate aggregation interval based on time range
        let interval = 'raw';
        if (range.endsWith('d') || range.endsWith('w') || range.endsWith('M') || range.endsWith('y')) {
          interval = '1h';
        } else if (range.endsWith('h') && parseInt(range) >= 3) {
          interval = '5m';
        } else if (range.endsWith('h')) {
          interval = '1m';
        } else {
          interval = 'raw';
        }

        const data = await apiClient.getBulkClientBandwidthHistory(range, interval);

        const averages: Record<string, BandwidthAverages> = {};

        // Calculate average MB (not Mbps) - sum bytes and convert to MB
        const calculateAverageMB = (data: ClientBandwidthDataPoint[]): { rx: number; tx: number } => {
          if (data.length === 0) return { rx: 0, tx: 0 };
          // Sum all bytes and convert to MB
          const totalRxBytes = data.reduce((sum, d) => sum + d.rx_bytes, 0);
          const totalTxBytes = data.reduce((sum, d) => sum + d.tx_bytes, 0);
          // Convert bytes to MB
          return {
            rx: totalRxBytes / (1024 * 1024),
            tx: totalTxBytes / (1024 * 1024),
          };
        };

        // Process each MAC address
        Object.keys(data).forEach((mac) => {
          const avg = calculateAverageMB(data[mac]?.data || []);

          averages[mac] = {
            dl_5m: avg.rx,
            dl_30m: avg.rx,
            dl_1h: avg.rx,
            dl_1d: avg.rx,
            ul_5m: avg.tx,
            ul_30m: avg.tx,
            ul_1h: avg.tx,
            ul_1d: avg.tx,
          };
        });

        setBandwidthAverages(averages);
      } catch (error) {
        console.error('Failed to fetch bandwidth averages:', error);
      }
    };

    fetchAverages();
    const interval = setInterval(fetchAverages, 60000); // Update every minute
    return () => clearInterval(interval);
  }, [token, tableTimeRange, tableCustomRange]);

  const isDeviceBlocked = (device: NetworkDevice) => {
    if (device.mac_address && blockedMacs.includes(device.mac_address.toLowerCase())) return true;
    return (device.ip_address && blockedV4.includes(device.ip_address));
  };

  const handleBlockToggle = async (device: NetworkDevice) => {
    if (!token) return;
    const blocked = isDeviceBlocked(device);
    const url = blocked ? '/api/devices/unblock' : '/api/devices/block';
    const body: any = { mac_address: device.mac_address };
    if (device.ip_address && device.ip_address.includes('.')) body.ip_address = device.ip_address;
    
    // Optimistic UI
    if (blocked) {
      setBlockedV4(prev => prev.filter(ip => ip !== device.ip_address));
      setBlockedMacs(prev => prev.filter(m => m !== device.mac_address.toLowerCase()));
    } else if (body.ip_address) {
      setBlockedV4(prev => Array.from(new Set([...prev, body.ip_address])));
      setBlockedMacs(prev => Array.from(new Set([...prev, device.mac_address.toLowerCase()])));
    }
    
    try {
      await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      // revert on error
      if (blocked) {
        setBlockedV4(prev => Array.from(new Set([...prev, device.ip_address])));
      } else {
        setBlockedV4(prev => prev.filter(ip => ip !== device.ip_address));
      }
    }
  };

  const openChart = async (device: NetworkDevice) => {
    setSelectedDevice(device);
    setChartModalOpen(true);
    await loadChartData(device);
  };

  const loadChartData = async (device: NetworkDevice) => {
    if (!token) return;
    try {
      const range = timeRange === 'custom' ? customRange : timeRange;
      if (!range || (timeRange === 'custom' && (!customRange || !validateTimeRange(customRange)))) {
        setChartData([]);
        return;
      }
      
      const history = await apiClient.getClientBandwidthHistory(
        device.mac_address,
        range,
        chartInterval
      );
      setChartData(history.data || []);
    } catch (error) {
      console.error('Failed to load chart data:', error);
      setChartData([]);
    }
  };

  // Reload chart data when time range or interval changes
  useEffect(() => {
    if (chartModalOpen && selectedDevice) {
      loadChartData(selectedDevice);
      const interval = setInterval(() => loadChartData(selectedDevice), refreshInterval * 1000);
      return () => clearInterval(interval);
    }
  }, [timeRange, customRange, chartInterval, refreshInterval, chartModalOpen, selectedDevice, token]);

  const formatMB = (value: number): string => {
    if (value === 0 || !value) return '0.00';
    return value.toFixed(2);
  };

  const getDisplayName = (device: NetworkDevice): string => {
    return device.nickname || device.hostname || 'Unknown';
  };

  // Sort IP address with zero-padded last octet for sorting (but not display)
  const getSortableIP = (ip: string): string => {
    const parts = ip.split('.');
    if (parts.length === 4) {
      // Zero-pad the last octet to 3 digits
      const lastOctet = parts[3].padStart(3, '0');
      return `${parts[0]}.${parts[1]}.${parts[2]}.${lastOctet}`;
    }
    return ip;
  };

  // Sort devices by IP address
  const sortedDevices = [...devices].sort((a, b) => {
    const ipA = getSortableIP(a.ip_address);
    const ipB = getSortableIP(b.ip_address);
    return ipA.localeCompare(ipB);
  });

  const chartDataFormatted = chartData.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString(),
    download: point.rx_mbps || 0,
    upload: point.tx_mbps || 0,
  }));

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
        
        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          <h1 className="text-2xl md:text-3xl font-bold mb-4 md:mb-6">Device Usage</h1>
          
          <Card>
            {/* Interface Stats at Top */}
            <div className="mb-4 p-4 bg-gray-100 dark:bg-gray-800 rounded-lg">
              <h3 className="text-sm font-semibold mb-2 text-gray-700 dark:text-gray-300">Interface Statistics</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {(['br0', 'br1', 'ppp0'] as const).map((iface) => {
                  const stats = interfaceStats[iface];
                  return (
                    <div key={iface} className="text-sm">
                      <div className="font-medium text-gray-900 dark:text-gray-100">{iface}</div>
                      {stats ? (
                        <div className="text-gray-600 dark:text-gray-400 space-y-1 mt-1">
                          <div>DL: {stats.rx_rate_mbps.toFixed(2)} Mbit/s</div>
                          <div>UL: {stats.tx_rate_mbps.toFixed(2)} Mbit/s</div>
                        </div>
                      ) : (
                        <div className="text-gray-400 dark:text-gray-500 mt-1">No data</div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Time Range Selector for Table */}
            <div className="mb-4 flex flex-wrap gap-4 items-end">
              <div className="min-w-[150px]">
                <Label htmlFor="table-range" value="Time Period" />
                <Select 
                  id="table-range" 
                  value={tableTimeRange} 
                  onChange={(e) => {
                    setTableTimeRange(e.target.value);
                    if (e.target.value !== 'custom') {
                      setTableCustomRange('');
                    }
                  }}
                >
                  <option value="1m">1 minute</option>
                  <option value="5m">5 minutes</option>
                  <option value="10m">10 minutes</option>
                  <option value="30m">30 minutes</option>
                  <option value="1h">1 hour</option>
                  <option value="3h">3 hours</option>
                  <option value="6h">6 hours</option>
                  <option value="12h">12 hours</option>
                  <option value="1d">1 day</option>
                  <option value="1w">1 week</option>
                  <option value="1M">1 month</option>
                  <option value="1y">1 year</option>
                  <option value="custom">Custom</option>
                </Select>
              </div>
              
              {tableTimeRange === 'custom' && (
                <div className="min-w-[150px]">
                  <Label htmlFor="table-custom" value="Custom Range" />
                  <TextInput 
                    id="table-custom" 
                    placeholder="e.g., 45m, 2h, 3d" 
                    value={tableCustomRange} 
                    onChange={(e) => setTableCustomRange(e.target.value)}
                    color={tableCustomRange && !validateTimeRange(tableCustomRange) ? 'failure' : undefined}
                    helperText={tableCustomRange && !validateTimeRange(tableCustomRange) ? 'Format: 1m, 5m, 1h, 1d, 1w, 1M, 1y' : undefined}
                  />
                </div>
              )}
            </div>

            <div className="hidden md:block overflow-x-auto">
              <Table>
                <Table.Head>
                  <Table.HeadCell>Hostname</Table.HeadCell>
                  <Table.HeadCell>MAC</Table.HeadCell>
                  <Table.HeadCell>IP</Table.HeadCell>
                  <Table.HeadCell>Status</Table.HeadCell>
                  <Table.HeadCell>DL (MB)</Table.HeadCell>
                  <Table.HeadCell>UL (MB)</Table.HeadCell>
                  <Table.HeadCell>Chart</Table.HeadCell>
                  <Table.HeadCell>Details</Table.HeadCell>
                  <Table.HeadCell>Enable/Disable</Table.HeadCell>
                </Table.Head>
                <Table.Body className="divide-y">
                  {sortedDevices.map((device) => {
                    const mac = device.mac_address.toLowerCase();
                    const averages = bandwidthAverages[mac] || {
                      dl_5m: 0, dl_30m: 0, dl_1h: 0, dl_1d: 0,
                      ul_5m: 0, ul_30m: 0, ul_1h: 0, ul_1d: 0,
                    };
                    
                    return (
                      <Table.Row key={device.mac_address} className={!device.is_online ? 'opacity-50' : ''}>
                        <Table.Cell className="font-medium">
                          {getDisplayName(device)}
                        </Table.Cell>
                        <Table.Cell className="font-mono text-sm">
                          {device.mac_address}
                        </Table.Cell>
                        <Table.Cell>{device.ip_address}</Table.Cell>
                        <Table.Cell>
                          <Badge color={device.is_online ? 'success' : 'gray'} size="sm">
                            {device.is_online ? 'Online' : 'Offline'}
                          </Badge>
                        </Table.Cell>
                        <Table.Cell className="text-sm">
                          {formatMB(averages.dl_1h)} MB
                        </Table.Cell>
                        <Table.Cell className="text-sm">
                          {formatMB(averages.ul_1h)} MB
                        </Table.Cell>
                        <Table.Cell>
                          <Button size="xs" color="blue" onClick={() => openChart(device)}>
                            Chart
                          </Button>
                        </Table.Cell>
                        <Table.Cell>
                          <Button size="xs" color="gray" onClick={() => navigate(`/device-usage/${device.ip_address}`)}>
                            Details
                          </Button>
                        </Table.Cell>
                        <Table.Cell>
                          <Button
                            size="xs"
                            color={isDeviceBlocked(device) ? 'success' : 'failure'}
                            onClick={() => handleBlockToggle(device)}
                          >
                            {isDeviceBlocked(device) ? 'Enable' : 'Disable'}
                          </Button>
                        </Table.Cell>
                      </Table.Row>
                    );
                  })}
                </Table.Body>
              </Table>
            </div>

            {/* Mobile Card View */}
            <div className="md:hidden space-y-3">
              {sortedDevices.map((device) => {
                const mac = device.mac_address.toLowerCase();
                const averages = bandwidthAverages[mac] || {
                  dl_5m: 0, dl_30m: 0, dl_1h: 0, dl_1d: 0,
                  ul_5m: 0, ul_30m: 0, ul_1h: 0, ul_1d: 0,
                };
                
                return (
                  <div
                    key={device.mac_address}
                    className={`p-4 rounded-lg border ${
                      device.is_online 
                        ? 'bg-white border-gray-200 dark:bg-gray-800 dark:border-gray-700' 
                        : 'bg-gray-50 border-gray-200 dark:bg-gray-900 dark:border-gray-700 opacity-60'
                    }`}
                  >
                    <div className="font-semibold text-lg mb-2">{getDisplayName(device)}</div>
                    <div className="text-sm space-y-1 mb-3">
                      <div>MAC: <span className="font-mono">{device.mac_address}</span></div>
                      <div>IP: {device.ip_address}</div>
                      <Badge color={device.is_online ? 'success' : 'gray'} size="sm">
                        {device.is_online ? 'Online' : 'Offline'}
                      </Badge>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-sm mb-3">
                      <div>
                        <div className="font-semibold">Download</div>
                        <div>{formatMB(averages.dl_1h)} MB</div>
                      </div>
                      <div>
                        <div className="font-semibold">Upload</div>
                        <div>{formatMB(averages.ul_1h)} MB</div>
                      </div>
                    </div>
                    <div className="flex gap-2">
                      <Button size="xs" color="blue" onClick={() => openChart(device)} className="flex-1">
                        Chart
                      </Button>
                      <Button size="xs" color="gray" onClick={() => navigate(`/device-usage/${device.ip_address}`)} className="flex-1">
                        Details
                      </Button>
                      <Button
                        size="xs"
                        color={isDeviceBlocked(device) ? 'success' : 'failure'}
                        onClick={() => handleBlockToggle(device)}
                        className="flex-1"
                      >
                        {isDeviceBlocked(device) ? 'Enable' : 'Disable'}
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>
          </Card>

          {/* Chart Modal */}
          <Modal show={chartModalOpen} onClose={() => setChartModalOpen(false)} size="xl">
            <Modal.Header>
              Bandwidth Usage - {selectedDevice ? getDisplayName(selectedDevice) : ''}
            </Modal.Header>
            <Modal.Body>
              <div className="space-y-4">
                {/* Controls */}
                <div className="flex flex-wrap gap-4">
                  <div className="min-w-[120px]">
                    <Label htmlFor="chart-range" value="Time Range" className="text-xs mb-1" />
                    <Select id="chart-range" sizing="sm" value={timeRange} onChange={(e) => {
                      setTimeRange(e.target.value);
                      if (e.target.value !== 'custom') {
                        setCustomRange('');
                      }
                    }}>
                      <option value="1m">1 minute</option>
                      <option value="5m">5 minutes</option>
                      <option value="10m">10 minutes</option>
                      <option value="30m">30 minutes</option>
                      <option value="1h">1 hour</option>
                      <option value="3h">3 hours</option>
                      <option value="6h">6 hours</option>
                      <option value="12h">12 hours</option>
                      <option value="1d">1 day</option>
                      <option value="1w">1 week</option>
                      <option value="1M">1 month</option>
                      <option value="1y">1 year</option>
                      <option value="custom">Custom</option>
                    </Select>
                  </div>
                  
                  {timeRange === 'custom' && (
                    <div className="min-w-[100px]">
                      <Label htmlFor="chart-custom" value="Custom" className="text-xs mb-1" />
                      <TextInput 
                        id="chart-custom" 
                        sizing="sm" 
                        placeholder="e.g., 45m" 
                        value={customRange} 
                        onChange={(e) => setCustomRange(e.target.value)}
                        color={customRange && !validateTimeRange(customRange) ? 'failure' : undefined}
                      />
                    </div>
                  )}
                  
                  <div className="min-w-[120px]">
                    <Label htmlFor="chart-interval" value="Interval" className="text-xs mb-1" />
                    <Select id="chart-interval" sizing="sm" value={chartInterval} onChange={(e) => setChartInterval(e.target.value)}>
                      <option value="raw">Raw</option>
                      <option value="1m">1 minute</option>
                      <option value="5m">5 minutes</option>
                      <option value="1h">1 hour</option>
                    </Select>
                  </div>
                  
                  <div className="min-w-[120px]">
                    <Label htmlFor="chart-refresh" value="Update Every" className="text-xs mb-1" />
                    <Select id="chart-refresh" sizing="sm" value={refreshInterval} onChange={(e) => setRefreshInterval(Number(e.target.value))}>
                      <option value={1}>1 second</option>
                      <option value={5}>5 seconds</option>
                      <option value={10}>10 seconds</option>
                      <option value={30}>30 seconds</option>
                      <option value={60}>1 minute</option>
                    </Select>
                  </div>
                </div>

                {/* Chart */}
                {chartDataFormatted.length > 0 ? (
                  <ResponsiveContainer width="100%" height={300}>
                    <LineChart data={chartDataFormatted}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="time" 
                        tick={{ fontSize: 12 }}
                        interval={Math.floor(chartDataFormatted.length / 8)}
                      />
                      <YAxis 
                        tick={{ fontSize: 12 }} 
                        label={{ value: 'Mbit/s', angle: -90, position: 'insideLeft' }}
                      />
                      <Tooltip />
                      <Legend />
                      <Line 
                        type="monotone" 
                        dataKey="download" 
                        stroke="#3b82f6" 
                        name="Download (Mbit/s)"
                        strokeWidth={2}
                        dot={false}
                        isAnimationActive={false}
                      />
                      <Line 
                        type="monotone" 
                        dataKey="upload" 
                        stroke="#10b981" 
                        name="Upload (Mbit/s)"
                        strokeWidth={2}
                        dot={false}
                        isAnimationActive={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                ) : (
                  <div className="text-center py-8 text-gray-500">
                    No bandwidth data available for this time range.
                  </div>
                )}
              </div>
            </Modal.Body>
          </Modal>
        </main>
      </div>
    </div>
  );
}

