/**
 * Connection Details page - Shows per-connection bandwidth statistics for a specific client
 */
import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { Card, Table, Button, Modal, Select, Label, TextInput } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface ConnectionCurrent {
  remote_ip: string;
  remote_port: number;
  hostname: string | null;
  download_mb: number;
  download_mbps: number;
  upload_mb: number;
  upload_mbps: number;
}

interface ConnectionDataPoint {
  timestamp: string;
  rx_mbps: number;
  tx_mbps: number;
  rx_bytes: number;
  tx_bytes: number;
}

interface ConnectionDetailsProps {
  sourcePage: 'device-usage' | 'devices';
}

function validateTimeRange(value: string): boolean {
  const pattern = /^(\d+)([mhdwMy])$/;
  return pattern.test(value);
}

export function ConnectionDetails({ sourcePage }: ConnectionDetailsProps) {
  const { ipAddress } = useParams<{ ipAddress: string }>();
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [connections, setConnections] = useState<ConnectionCurrent[]>([]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [chartModalOpen, setChartModalOpen] = useState(false);
  const [selectedConnection, setSelectedConnection] = useState<{ remoteIp: string; remotePort: number } | null>(null);
  const [chartData, setChartData] = useState<ConnectionDataPoint[]>([]);
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(5);
  const [chartInterval, setChartInterval] = useState('raw');
  const [tableTimeRange, setTableTimeRange] = useState('1h');
  const [tableCustomRange, setTableCustomRange] = useState('');
  const [sortColumn, setSortColumn] = useState<string | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch connections
  const fetchConnections = async () => {
    if (!token || !ipAddress) return;
    
    try {
      const range = tableTimeRange === 'custom' && tableCustomRange ? tableCustomRange : tableTimeRange;
      if (tableTimeRange === 'custom' && !validateTimeRange(range)) {
        return; // Don't fetch if custom range is invalid
      }
      
      const data = await apiClient.getClientConnections(ipAddress, range);
      setConnections(data);
    } catch (error) {
      console.error('Failed to fetch connections:', error);
    }
  };

  useEffect(() => {
    fetchConnections();
    const interval = setInterval(fetchConnections, 5000); // Auto-refresh every 5 seconds
    return () => clearInterval(interval);
  }, [token, ipAddress, tableTimeRange, tableCustomRange]);

  // Fetch chart data
  const fetchChartData = async () => {
    if (!token || !ipAddress || !selectedConnection) return;
    
    try {
      const range = timeRange === 'custom' && customRange ? customRange : timeRange;
      if (timeRange === 'custom' && !validateTimeRange(range)) {
        return;
      }
      
      const data = await apiClient.getConnectionHistory(
        ipAddress,
        selectedConnection.remoteIp,
        selectedConnection.remotePort,
        range,
        chartInterval
      );
      setChartData(data.data || []);
    } catch (error) {
      console.error('Failed to fetch chart data:', error);
    }
  };

  useEffect(() => {
    if (chartModalOpen && selectedConnection) {
      fetchChartData();
      const interval = setInterval(fetchChartData, refreshInterval * 1000);
      return () => clearInterval(interval);
    }
  }, [token, ipAddress, selectedConnection, timeRange, customRange, chartInterval, refreshInterval, chartModalOpen]);

  const openChart = (connection: ConnectionCurrent) => {
    setSelectedConnection({
      remoteIp: connection.remote_ip,
      remotePort: connection.remote_port
    });
    setChartModalOpen(true);
  };

  // Sort IP address with zero-padded last octet for sorting (but not display)
  const getSortableIP = (ip: string): string => {
    const parts = ip.split('.');
    if (parts.length === 4) {
      const lastOctet = parts[3].padStart(3, '0');
      return `${parts[0]}.${parts[1]}.${parts[2]}.${lastOctet}`;
    }
    return ip;
  };

  // Handle column sorting
  const handleSort = (column: string) => {
    if (sortColumn === column) {
      // Toggle direction
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      // New column, start with ascending
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  // Sort connections based on selected column
  const sortedConnections = [...connections].sort((a, b) => {
    if (!sortColumn) {
      // Default: sort by IP address
      const ipA = getSortableIP(a.remote_ip);
      const ipB = getSortableIP(b.remote_ip);
      return ipA.localeCompare(ipB);
    }

    let comparison = 0;
    switch (sortColumn) {
      case 'ip':
        comparison = getSortableIP(a.remote_ip).localeCompare(getSortableIP(b.remote_ip));
        break;
      case 'hostname':
        comparison = (a.hostname || '').localeCompare(b.hostname || '');
        break;
      case 'download_mb':
        comparison = a.download_mb - b.download_mb;
        break;
      case 'download_mbps':
        comparison = a.download_mbps - b.download_mbps;
        break;
      case 'upload_mb':
        comparison = a.upload_mb - b.upload_mb;
        break;
      case 'upload_mbps':
        comparison = a.upload_mbps - b.upload_mbps;
        break;
      default:
        return 0;
    }

    return sortDirection === 'asc' ? comparison : -comparison;
  });

  // Get sort indicator for a column
  const getSortIndicator = (column: string) => {
    if (sortColumn !== column) return null;
    return sortDirection === 'asc' ? ' ↑' : ' ↓';
  };

  const chartDataFormatted = chartData.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString(),
    download: point.rx_mbps || 0,
    upload: point.tx_mbps || 0,
  }));

  const formatMB = (mb: number): string => {
    if (mb < 0.01) return '0.00';
    if (mb < 1) return mb.toFixed(2);
    if (mb < 1000) return mb.toFixed(1);
    return (mb / 1024).toFixed(2) + ' GB';
  };

  const breadcrumbLabel = sourcePage === 'device-usage' ? 'Device Usage' : 'Devices';

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
          {/* Breadcrumb */}
          <div className="mb-4 text-sm text-gray-600 dark:text-gray-400">
            <Link to={`/${sourcePage}`} className="hover:text-gray-900 dark:hover:text-gray-100">
              {breadcrumbLabel}
            </Link>
            <span className="mx-2">›</span>
            <span className="text-gray-900 dark:text-gray-100">{ipAddress}</span>
          </div>
          
          <h1 className="text-2xl md:text-3xl font-bold mb-4 md:mb-6">Connection Details - {ipAddress}</h1>
          
          <Card>
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
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('ip')}
                  >
                    IP Address : Port{getSortIndicator('ip')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('hostname')}
                  >
                    Hostname{getSortIndicator('hostname')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('download_mb')}
                  >
                    Download MB{getSortIndicator('download_mb')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('download_mbps')}
                  >
                    Download Mbit/s{getSortIndicator('download_mbps')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('upload_mb')}
                  >
                    Upload MB{getSortIndicator('upload_mb')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('upload_mbps')}
                  >
                    Upload Mbit/s{getSortIndicator('upload_mbps')}
                  </Table.HeadCell>
                  <Table.HeadCell>Chart</Table.HeadCell>
                </Table.Head>
                <Table.Body className="divide-y">
                  {sortedConnections.map((conn) => (
                    <Table.Row key={`${conn.remote_ip}:${conn.remote_port}`}>
                      <Table.Cell className="font-mono text-sm">
                        {conn.remote_ip}:{conn.remote_port}
                      </Table.Cell>
                      <Table.Cell>
                        {conn.hostname || '—'}
                      </Table.Cell>
                      <Table.Cell className="text-sm">
                        {formatMB(conn.download_mb)} MB
                      </Table.Cell>
                      <Table.Cell className="text-sm">
                        {conn.download_mbps.toFixed(2)} Mbit/s
                      </Table.Cell>
                      <Table.Cell className="text-sm">
                        {formatMB(conn.upload_mb)} MB
                      </Table.Cell>
                      <Table.Cell className="text-sm">
                        {conn.upload_mbps.toFixed(2)} Mbit/s
                      </Table.Cell>
                      <Table.Cell>
                        <Button size="xs" color="blue" onClick={() => openChart(conn)}>
                          Chart
                        </Button>
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </Table>
            </div>

            {/* Mobile Card View */}
            <div className="md:hidden space-y-3">
              {sortedConnections.map((conn) => (
                <div
                  key={`${conn.remote_ip}:${conn.remote_port}`}
                  className="p-4 rounded-lg border bg-white border-gray-200 dark:bg-gray-800 dark:border-gray-700"
                >
                  <div className="font-semibold text-lg mb-2 font-mono">
                    {conn.remote_ip}:{conn.remote_port}
                  </div>
                  {conn.hostname && (
                    <div className="text-sm text-gray-600 dark:text-gray-400 mb-3">
                      {conn.hostname}
                    </div>
                  )}
                  <div className="grid grid-cols-2 gap-2 text-sm mb-3">
                    <div>
                      <div className="font-semibold">Download</div>
                      <div>{formatMB(conn.download_mb)} MB</div>
                      <div className="text-xs text-gray-500">{conn.download_mbps.toFixed(2)} Mbit/s</div>
                    </div>
                    <div>
                      <div className="font-semibold">Upload</div>
                      <div>{formatMB(conn.upload_mb)} MB</div>
                      <div className="text-xs text-gray-500">{conn.upload_mbps.toFixed(2)} Mbit/s</div>
                    </div>
                  </div>
                  <Button size="xs" color="blue" onClick={() => openChart(conn)} className="w-full">
                    Chart
                  </Button>
                </div>
              ))}
            </div>

            {sortedConnections.length === 0 && (
              <div className="text-center py-8 text-gray-500">
                No connections found for this time period.
              </div>
            )}
          </Card>

          {/* Chart Modal */}
          <Modal show={chartModalOpen} onClose={() => setChartModalOpen(false)} size="xl">
            <Modal.Header>
              Connection - {selectedConnection ? `${selectedConnection.remoteIp}:${selectedConnection.remotePort}` : ''}
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
                    No connection data available for this time range.
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

