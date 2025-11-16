/**
 * Device Usage page - Shows bandwidth usage per device with sortable table and detailed charts
 */
import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput, Label, Table, Button } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { HiArrowUp, HiArrowDown } from 'react-icons/hi';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface DeviceBandwidthSummary {
  network: string;
  ip_address: string;
  mac_address: string | null;
  hostname: string | null;
  current_rx_mbps: number;
  current_tx_mbps: number;
  last_hour_rx_mb: number;
  last_hour_tx_mb: number;
  last_day_rx_mb: number;
  last_day_tx_mb: number;
  last_month_rx_mb: number;
  last_month_tx_mb: number;
}

interface DeviceBandwidthDataPoint {
  timestamp: string;
  rx_mbps: number;
  tx_mbps: number;
}

interface DeviceBandwidthHistory {
  network: string;
  ip_address: string;
  mac_address: string | null;
  hostname: string | null;
  data: DeviceBandwidthDataPoint[];
}

type SortField = 'hostname' | 'ip_address' | 'current_rx_mbps' | 'current_tx_mbps' |
                 'last_hour_rx_mb' | 'last_hour_tx_mb' | 'last_day_rx_mb' | 'last_day_tx_mb' |
                 'last_month_rx_mb' | 'last_month_tx_mb';
type SortDirection = 'asc' | 'desc';

export function DeviceUsage() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  // Global controls
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(30); // 30 seconds for device data

  // Table data and sorting
  const [devices, setDevices] = useState<DeviceBandwidthSummary[]>([]);
  const [sortField, setSortField] = useState<SortField>('last_hour_tx_mb');
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');
  const [loading, setLoading] = useState(true);

  // Detailed view
  const [selectedDevice, setSelectedDevice] = useState<DeviceBandwidthSummary | null>(null);
  const [deviceHistory, setDeviceHistory] = useState<DeviceBandwidthHistory | null>(null);

  const { connectionStatus } = useMetrics(token);

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Load device summary data
  useEffect(() => {
    const fetchDevices = async () => {
      if (!token) return;

      try {
        console.log('DEBUG: Fetching device bandwidth summary...');
        const response = await fetch('/api/system/device-bandwidth/summary', {
          headers: { 'Authorization': `Bearer ${token}` },
        });

        console.log('DEBUG: Response status:', response.status);
        if (response.ok) {
          const data: DeviceBandwidthSummary[] = await response.json();
          console.log('DEBUG: Received device data:', data);
          setDevices(data);
          setLoading(false);
        } else {
          const errorText = await response.text();
          console.error('DEBUG: API error response:', errorText);
          setLoading(false);
        }
      } catch (error) {
        console.error('Failed to fetch device usage:', error);
        setLoading(false);
      }
    };

    fetchDevices();
    const interval = setInterval(fetchDevices, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [token, refreshInterval]);

  // Load detailed device history when selected
  useEffect(() => {
    if (!selectedDevice) {
      setDeviceHistory(null);
      return;
    }

    const fetchDeviceHistory = async () => {
      if (!token) return;

      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        const response = await fetch(
          `/api/system/device-bandwidth/history?ip_address=${selectedDevice.ip_address}&range=${range}`,
          {
            headers: { 'Authorization': `Bearer ${token}` },
          }
        );

        if (response.ok) {
          const data: DeviceBandwidthHistory[] = await response.json();
          setDeviceHistory(data[0] || null);
        }
      } catch (error) {
        console.error('Failed to fetch device history:', error);
      }
    };

    fetchDeviceHistory();
  }, [selectedDevice, timeRange, customRange, token]);

  // Sort devices
  const sortedDevices = useMemo(() => {
    return [...devices].sort((a, b) => {
      let aVal: any = a[sortField];
      let bVal: any = b[sortField];

      // Handle null values
      if (aVal === null || aVal === undefined) aVal = '';
      if (bVal === null || bVal === undefined) bVal = '';

      // String comparison for hostname and IP
      if (typeof aVal === 'string') {
        aVal = aVal.toLowerCase();
        bVal = bVal.toLowerCase();
      }

      if (sortDirection === 'asc') {
        return aVal > bVal ? 1 : aVal < bVal ? -1 : 0;
      } else {
        return aVal < bVal ? 1 : aVal > bVal ? -1 : 0;
      }
    });
  }, [devices, sortField, sortDirection]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('desc'); // Default to descending for bandwidth fields
    }
  };

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  const SortableHeader = ({ field, children }: { field: SortField; children: React.ReactNode }) => (
    <Table.HeadCell>
      <Button
        size="xs"
        color="light"
        className="p-0 h-auto font-semibold text-gray-900 dark:text-white hover:bg-transparent"
        onClick={() => handleSort(field)}
      >
        <div className="flex items-center gap-1">
          {children}
          {sortField === field && (
            sortDirection === 'asc' ? <HiArrowUp className="w-3 h-3" /> : <HiArrowDown className="w-3 h-3" />
          )}
        </div>
      </Button>
    </Table.HeadCell>
  );

  // Chart data for selected device
  const chartData = useMemo(() => {
    if (!deviceHistory) return [];
    return deviceHistory.data.map((point) => ({
      time: new Date(point.timestamp).toLocaleTimeString(),
      download: point.rx_mbps || 0,
      upload: point.tx_mbps || 0,
    }));
  }, [deviceHistory]);

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

        {/* Sticky Global Controls */}
        <div className="sticky top-0 z-10 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 md:px-6 py-3 shadow-sm">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-3">
            <h1 className="text-2xl md:text-3xl font-bold">Device Usage</h1>

            <div className="flex flex-wrap gap-2 md:gap-4 items-end">
              {/* Time Range Selector */}
              <div className="min-w-[120px]">
                <Label htmlFor="global-range" value="Time Range" className="text-xs mb-1" />
                <Select id="global-range" sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                  <option value="10m">10 minutes</option>
                  <option value="30m">30 minutes</option>
                  <option value="1h">1 hour</option>
                  <option value="3h">3 hours</option>
                  <option value="6h">6 hours</option>
                  <option value="12h">12 hours</option>
                  <option value="1d">1 day</option>
                  <option value="custom">Custom</option>
                </Select>
              </div>

              {timeRange === 'custom' && (
                <div className="min-w-[100px]">
                  <Label htmlFor="global-custom" value="Custom" className="text-xs mb-1" />
                  <TextInput id="global-custom" sizing="sm" placeholder="e.g., 45m" value={customRange} onChange={(e) => setCustomRange(e.target.value)} />
                </div>
              )}

              {/* Refresh Interval Selector */}
              <div className="min-w-[120px]">
                <Label htmlFor="global-refresh" value="Update Every" className="text-xs mb-1" />
                <Select id="global-refresh" sizing="sm" value={refreshInterval} onChange={(e) => setRefreshInterval(Number(e.target.value))}>
                  <option value={10}>10 seconds</option>
                  <option value={30}>30 seconds</option>
                  <option value={60}>1 minute</option>
                  <option value={300}>5 minutes</option>
                </Select>
              </div>
            </div>
          </div>
        </div>

        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          {loading ? (
            <Card>
              <p className="text-center py-8">Loading device usage data...</p>
            </Card>
          ) : (
            <>
              {/* Device List Table */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">Device Bandwidth Overview</h3>

                <div className="overflow-x-auto">
                  <Table>
                    <Table.Head>
                      <SortableHeader field="hostname">Device</SortableHeader>
                      <SortableHeader field="ip_address">IP Address</SortableHeader>
                      <Table.HeadCell>MAC Address</Table.HeadCell>
                      <Table.HeadCell>Network</Table.HeadCell>
                      <SortableHeader field="current_rx_mbps">Current ↓</SortableHeader>
                      <SortableHeader field="current_tx_mbps">Current ↑</SortableHeader>
                      <SortableHeader field="last_hour_rx_mb">1h ↓</SortableHeader>
                      <SortableHeader field="last_hour_tx_mb">1h ↑</SortableHeader>
                      <SortableHeader field="last_day_rx_mb">24h ↓</SortableHeader>
                      <SortableHeader field="last_day_tx_mb">24h ↑</SortableHeader>
                      <SortableHeader field="last_month_rx_mb">30d ↓</SortableHeader>
                      <SortableHeader field="last_month_tx_mb">30d ↑</SortableHeader>
                    </Table.Head>
                    <Table.Body className="divide-y">
                      {sortedDevices.map((device) => (
                        <Table.Row
                          key={device.ip_address}
                          className={`hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer ${
                            selectedDevice?.ip_address === device.ip_address ? 'bg-blue-50 dark:bg-blue-900/20' : ''
                          }`}
                          onClick={() => setSelectedDevice(device)}
                        >
                          <Table.Cell className="font-medium">
                            {device.hostname || 'Unknown'}
                          </Table.Cell>
                          <Table.Cell className="font-mono text-sm">{device.ip_address}</Table.Cell>
                          <Table.Cell className="font-mono text-sm">{device.mac_address || '—'}</Table.Cell>
                          <Table.Cell>
                            <Badge color={device.network === 'homelab' ? 'info' : 'purple'} size="sm">
                              {device.network.toUpperCase()}
                            </Badge>
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {device.current_rx_mbps.toFixed(2)} Mbps
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {device.current_tx_mbps.toFixed(2)} Mbps
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_hour_rx_mb * 1024 * 1024)}
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_hour_tx_mb * 1024 * 1024)}
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_day_rx_mb * 1024 * 1024)}
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_day_tx_mb * 1024 * 1024)}
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_month_rx_mb * 1024 * 1024)}
                          </Table.Cell>
                          <Table.Cell className="text-right font-mono">
                            {formatBytes(device.last_month_tx_mb * 1024 * 1024)}
                          </Table.Cell>
                        </Table.Row>
                      ))}
                    </Table.Body>
                  </Table>
                </div>

                {sortedDevices.length === 0 && (
                  <div className="text-center py-8 text-gray-500">
                    No device bandwidth data available. Devices will appear here as they use network bandwidth.
                  </div>
                )}

                <div className="mt-4 text-xs md:text-sm text-gray-500 text-center">
                  <p>Showing {sortedDevices.length} devices • Auto-refreshing every {refreshInterval} seconds</p>
                  <p className="mt-1">Click on a device row to view detailed bandwidth charts</p>
                </div>
              </Card>

              {/* Detailed Device View */}
              {selectedDevice && (
                <Card>
                  <div className="flex justify-between items-center mb-4">
                    <div>
                      <h3 className="text-lg font-semibold">
                        {selectedDevice.hostname || 'Unknown Device'}
                      </h3>
                      <p className="text-sm text-gray-600 dark:text-gray-400">
                        {selectedDevice.ip_address} • {selectedDevice.mac_address || 'No MAC'} • {selectedDevice.network.toUpperCase()}
                      </p>
                    </div>
                    <Button
                      size="sm"
                      color="light"
                      onClick={() => setSelectedDevice(null)}
                    >
                      Close Details
                    </Button>
                  </div>

                  {!deviceHistory ? (
                    <div className="text-center py-8">
                      <p className="text-gray-500">Loading device bandwidth history...</p>
                    </div>
                  ) : chartData.length === 0 ? (
                    <div className="text-center py-8">
                      <p className="text-gray-500">No historical data available for this time range.</p>
                    </div>
                  ) : (
                    <>
                      <ResponsiveContainer width="100%" height={400}>
                        <LineChart data={chartData}>
                          <CartesianGrid strokeDasharray="3 3" />
                          <XAxis
                            dataKey="time"
                            tick={{ fontSize: 12 }}
                            interval={Math.floor(chartData.length / 10)}
                          />
                          <YAxis label={{ value: 'Mbps', angle: -90, position: 'insideLeft' }} />
                          <Tooltip />
                          <Legend />
                          <Line
                            type="monotone"
                            dataKey="download"
                            stroke="#3b82f6"
                            name="Download"
                            strokeWidth={2}
                            dot={false}
                            isAnimationActive={false}
                          />
                          <Line
                            type="monotone"
                            dataKey="upload"
                            stroke="#10b981"
                            name="Upload"
                            strokeWidth={2}
                            dot={false}
                            isAnimationActive={false}
                          />
                        </LineChart>
                      </ResponsiveContainer>

                      <div className="mt-4 text-sm text-gray-600 dark:text-gray-400 text-center">
                        <p>
                          Bandwidth usage for {selectedDevice.hostname || selectedDevice.ip_address} over the last {timeRange === 'custom' ? customRange : timeRange}
                          {' • '}Showing {chartData.length} data points
                        </p>
                      </div>
                    </>
                  )}
                </Card>
              )}
            </>
          )}
        </main>
      </div>
    </div>
  );
}
