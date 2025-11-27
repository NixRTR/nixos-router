/**
 * Device Usage page - Shows per-client bandwidth statistics
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Table, Badge, Button, Modal, Select, Label, TextInput, Tooltip as FlowbiteTooltip } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { CustomTooltip } from '../components/charts/CustomTooltip';
import { HiSearch } from 'react-icons/hi';
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
  const [interfaceStats, setInterfaceStats] = useState<Record<string, { rx_mb: number; tx_mb: number }>>({});
  const [sortColumn, setSortColumn] = useState<string | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('all'); // all, online, offline
  const [filterType, setFilterType] = useState('all'); // all, dhcp, static
  const [filterNetwork, setFilterNetwork] = useState('all'); // all, homelab, lan
  
  // Determine if a column is numerical (should default to descending)
  const isNumericalColumn = (column: string): boolean => {
    return ['dl', 'ul'].includes(column);
  };
  
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

  // Fetch interface stats totals for the selected time period
  useEffect(() => {
    const fetchInterfaceStats = async () => {
      if (!token) return;
      
      const range = tableTimeRange === 'custom' ? tableCustomRange : tableTimeRange;
      if (!range || (tableTimeRange === 'custom' && !validateTimeRange(range))) {
        setInterfaceStats({});
        return;
      }
      
      try {
        const stats = await apiClient.getInterfaceTotals(range);
        setInterfaceStats(stats);
      } catch (error) {
        console.error('Failed to fetch interface stats:', error);
      }
    };
    
    fetchInterfaceStats();
    const interval = setInterval(fetchInterfaceStats, 60000); // Update every minute
    return () => clearInterval(interval);
  }, [token, tableTimeRange, tableCustomRange]);

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

  // Format bytes (input in MB) to best unit (TB, GB, MB, KB)
  const formatBytes = (mb: number): string => {
    if (mb === 0 || !mb || isNaN(mb)) return '0.00 MB';
    
    // Convert MB to bytes for calculation
    const bytes = mb * 1024 * 1024;
    
    // Determine best unit
    if (bytes >= 1024 * 1024 * 1024 * 1024) {
      // TB
      const tb = bytes / (1024 * 1024 * 1024 * 1024);
      return tb.toFixed(2) + ' TB';
    } else if (bytes >= 1024 * 1024 * 1024) {
      // GB
      const gb = bytes / (1024 * 1024 * 1024);
      return gb.toFixed(2) + ' GB';
    } else if (bytes >= 1024 * 1024) {
      // MB
      return mb.toFixed(2) + ' MB';
    } else if (bytes >= 1024) {
      // KB
      const kb = bytes / 1024;
      return kb.toFixed(2) + ' KB';
    } else {
      // Bytes (shouldn't happen with MB input, but handle it)
      return bytes.toFixed(0) + ' B';
    }
  };

  const getDisplayName = (device: NetworkDevice): string => {
    return device.nickname || device.hostname || 'Unknown';
  };

  // Helper function to truncate text with tooltip
  const TruncatedText = ({ text, maxLength = 20 }: { text: string; maxLength?: number }) => {
    if (text.length <= maxLength) {
      return <span>{text}</span>;
    }
    return (
      <FlowbiteTooltip content={text} placement="top">
        <span className="cursor-help truncate block max-w-[200px]">{text}</span>
      </FlowbiteTooltip>
    );
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

  // Handle column sorting
  const handleSort = (column: string) => {
    if (sortColumn === column) {
      // Toggle direction
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      // New column - numerical columns start with descending, text/IP start with ascending
      setSortColumn(column);
      setSortDirection(isNumericalColumn(column) ? 'desc' : 'asc');
    }
  };

  // Filter devices
  const filteredDevices = devices.filter((device) => {
    // Search filter
    const matchesSearch = !search || (
      device.hostname?.toLowerCase().includes(search.toLowerCase()) ||
      device.ip_address.includes(search) ||
      device.mac_address.includes(search) ||
      (device.nickname?.toLowerCase().includes(search.toLowerCase()))
    );
    
    // Status filter
    const matchesStatus = filterStatus === 'all' || 
      (filterStatus === 'online' && device.is_online) ||
      (filterStatus === 'offline' && !device.is_online);
    
    // Type filter
    const matchesType = filterType === 'all' ||
      (filterType === 'dhcp' && device.is_dhcp) ||
      (filterType === 'static' && !device.is_dhcp);
    
    // Network filter
    const matchesNetwork = filterNetwork === 'all' || device.network === filterNetwork;
    
    return matchesSearch && matchesStatus && matchesType && matchesNetwork;
  });

  // Sort devices based on selected column
  const sortedDevices = [...filteredDevices].sort((a, b) => {
    if (!sortColumn) {
      // Default: sort by IP address
      const ipA = getSortableIP(a.ip_address);
      const ipB = getSortableIP(b.ip_address);
      return ipA.localeCompare(ipB);
    }

    let comparison = 0;
    switch (sortColumn) {
      case 'hostname':
        comparison = getDisplayName(a).localeCompare(getDisplayName(b));
        break;
      case 'mac':
        comparison = a.mac_address.localeCompare(b.mac_address);
        break;
      case 'ip':
        comparison = getSortableIP(a.ip_address).localeCompare(getSortableIP(b.ip_address));
        break;
      case 'status':
        // Online first, then offline
        comparison = (a.is_online ? 0 : 1) - (b.is_online ? 0 : 1);
        break;
      case 'dl':
        const macA = a.mac_address.toLowerCase();
        const macB = b.mac_address.toLowerCase();
        const avgA = bandwidthAverages[macA]?.dl_1h || 0;
        const avgB = bandwidthAverages[macB]?.dl_1h || 0;
        comparison = avgA - avgB;
        break;
      case 'ul':
        const macA2 = a.mac_address.toLowerCase();
        const macB2 = b.mac_address.toLowerCase();
        const avgA2 = bandwidthAverages[macA2]?.ul_1h || 0;
        const avgB2 = bandwidthAverages[macB2]?.ul_1h || 0;
        comparison = avgA2 - avgB2;
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
                          <div>DL: {formatBytes(stats.rx_mb)}</div>
                          <div>UL: {formatBytes(stats.tx_mb)}</div>
                        </div>
                      ) : (
                        <div className="text-gray-400 dark:text-gray-500 mt-1">No data</div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Search and Filter Bar - Same as Devices page */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
              <div>
                <TextInput
                  icon={HiSearch}
                  placeholder="Search..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
              
              <div>
                <Select
                  value={filterStatus}
                  onChange={(e) => setFilterStatus(e.target.value)}
                >
                  <option value="all">All Status</option>
                  <option value="online">Online Only</option>
                  <option value="offline">Offline Only</option>
                </Select>
              </div>
              
              <div>
                <Select
                  value={filterType}
                  onChange={(e) => setFilterType(e.target.value)}
                >
                  <option value="all">All Types</option>
                  <option value="dhcp">DHCP Only</option>
                  <option value="static">Static Only</option>
                </Select>
              </div>
              
              <div>
                <Select
                  value={filterNetwork}
                  onChange={(e) => setFilterNetwork(e.target.value)}
                >
                  <option value="all">All Networks</option>
                  <option value="homelab">HOMELAB</option>
                  <option value="lan">LAN</option>
                </Select>
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

            {/* Legend for color indicators - only show below 1650px */}
            <div className="xl-custom:hidden mb-4 flex flex-wrap gap-4 text-xs text-gray-600 dark:text-gray-400">
              <div className="flex items-center gap-2">
                <span className="font-semibold">Network:</span>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded-full bg-blue-500"></div>
                  <span>HOMELAB</span>
                </div>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded-full bg-purple-500"></div>
                  <span>LAN</span>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <span className="font-semibold">Type:</span>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded-full bg-gray-500"></div>
                  <span>Static</span>
                </div>
                <div className="flex items-center gap-1">
                  <div className="w-3 h-3 rounded-full bg-yellow-500"></div>
                  <span>DHCP</span>
                </div>
              </div>
            </div>

            <div className="hidden min-[1000px]:block overflow-x-auto">
              <Table>
                <Table.Head>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('hostname')}
                  >
                    Hostname{getSortIndicator('hostname')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 hidden lg:table-cell"
                    onClick={() => handleSort('mac')}
                  >
                    MAC{getSortIndicator('mac')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('ip')}
                  >
                    IP{getSortIndicator('ip')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 w-12"
                    onClick={() => handleSort('status')}
                  >
                    Status{getSortIndicator('status')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('dl')}
                  >
                    DOWNLOAD{getSortIndicator('dl')}
                  </Table.HeadCell>
                  <Table.HeadCell 
                    className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
                    onClick={() => handleSort('ul')}
                  >
                    UPLOAD{getSortIndicator('ul')}
                  </Table.HeadCell>
                  <Table.HeadCell>Actions</Table.HeadCell>
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
                        <Table.Cell className="font-medium max-w-[200px]">
                          <TruncatedText text={getDisplayName(device)} maxLength={20} />
                        </Table.Cell>
                        <Table.Cell className="font-mono text-sm hidden lg:table-cell">
                          {device.mac_address}
                        </Table.Cell>
                        <Table.Cell className="font-mono text-sm">{device.ip_address}</Table.Cell>
                        <Table.Cell>
                          {/* Show text above 1650px, circle below */}
                          <div className="hidden xl-custom:block">
                            <Badge color={device.is_online ? 'success' : 'gray'} size="sm">
                              {device.is_online ? 'ONLINE' : 'OFFLINE'}
                            </Badge>
                          </div>
                          <div className="xl-custom:hidden">
                            <FlowbiteTooltip content={device.is_online ? 'Online' : 'Offline'} placement="top">
                              <div className={`w-3 h-3 rounded-full ${device.is_online ? 'bg-green-500' : 'bg-gray-400'}`}></div>
                            </FlowbiteTooltip>
                          </div>
                        </Table.Cell>
                        <Table.Cell className="text-sm">
                          {formatBytes(averages.dl_1h)}
                        </Table.Cell>
                        <Table.Cell className="text-sm">
                          {formatBytes(averages.ul_1h)}
                        </Table.Cell>
                        <Table.Cell>
                          <div className="flex gap-1">
                            <Button size="xs" color="blue" onClick={() => openChart(device)}>
                              Chart
                            </Button>
                            <Button size="xs" color="gray" onClick={() => navigate(`/device-usage/${device.ip_address}`)}>
                              Details
                            </Button>
                            <Button
                              size="xs"
                              color={isDeviceBlocked(device) ? 'success' : 'failure'}
                              onClick={() => handleBlockToggle(device)}
                            >
                              {isDeviceBlocked(device) ? 'Enable' : 'Disable'}
                            </Button>
                          </div>
                        </Table.Cell>
                      </Table.Row>
                    );
                  })}
                </Table.Body>
              </Table>
            </div>

            {/* Mobile Card View */}
            <div className="min-[1000px]:hidden">
              {/* Sort Controls for Mobile */}
              <div className="mb-4 flex gap-2">
                <div className="flex-1">
                  <Label htmlFor="mobile-sort-field" value="Sort By" className="text-xs mb-1" />
                  <Select 
                    id="mobile-sort-field" 
                    sizing="sm" 
                    value={sortColumn || 'ip'} 
                    onChange={(e) => {
                      const newColumn = e.target.value;
                      setSortColumn(newColumn);
                      // Set default direction based on column type
                      setSortDirection(isNumericalColumn(newColumn) ? 'desc' : 'asc');
                    }}
                  >
                    <option value="hostname">Hostname</option>
                    <option value="mac">MAC</option>
                    <option value="ip">IP</option>
                    <option value="status">Status</option>
                    <option value="dl">Download</option>
                    <option value="ul">Upload</option>
                  </Select>
                </div>
                <div className="flex-1">
                  <Label htmlFor="mobile-sort-direction" value="Direction" className="text-xs mb-1" />
                  <Select 
                    id="mobile-sort-direction" 
                    sizing="sm" 
                    value={sortDirection} 
                    onChange={(e) => setSortDirection(e.target.value as 'asc' | 'desc')}
                  >
                    <option value="asc">Ascending</option>
                    <option value="desc">Descending</option>
                  </Select>
                </div>
              </div>
              
              <div className="space-y-3">
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
                        <div>{formatBytes(averages.dl_1h)}</div>
                      </div>
                      <div>
                        <div className="font-semibold">Upload</div>
                        <div>{formatBytes(averages.ul_1h)}</div>
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
            </div>
          </Card>

          {/* Chart Modal */}
          <Modal show={chartModalOpen} onClose={() => setChartModalOpen(false)} size="xl">
            <Modal.Header>
              Bandwidth Usage - {selectedDevice ? getDisplayName(selectedDevice) : ''}
            </Modal.Header>
            <Modal.Body className="max-h-[80vh] overflow-y-auto">
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
                      <Tooltip content={<CustomTooltip />} />
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

