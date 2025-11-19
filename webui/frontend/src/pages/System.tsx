/**
 * System monitoring page with sticky global controls and historical charts
 */
import { useState, useEffect, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput, Label } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { CustomTooltip } from '../components/charts/CustomTooltip';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface SystemDataPoint {
  timestamp: string;
  cpu_percent: number;
  memory_percent: number;
  load_avg_1m: number;
}

interface SystemHistory {
  data: SystemDataPoint[];
}

interface DiskIODataPoint {
  timestamp: string;
  read_mbps: number;
  write_mbps: number;
}

interface DiskIOHistory {
  device: string;
  data: DiskIODataPoint[];
}

interface TemperatureDataPoint {
  timestamp: string;
  temperature_c: number;
}

interface TemperatureHistory {
  sensor_name: string;
  data: TemperatureDataPoint[];
}

interface ClientStats {
  network: string;
  dhcp_clients: number;
  static_clients: number;
  total_clients: number;
  online_clients: number;
  offline_clients: number;
}

export function System() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  // Global controls (sticky header)
  const [timeRange, setTimeRange] = useState('30m');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(10);
  
  // Historical data from database
  const [cpuHistoricalData, setCpuHistoricalData] = useState<SystemDataPoint[]>([]);
  const [memHistoricalData, setMemHistoricalData] = useState<SystemDataPoint[]>([]);
  const [loadHistoricalData, setLoadHistoricalData] = useState<SystemDataPoint[]>([]);
  const [diskIOHistories, setDiskIOHistories] = useState<DiskIOHistory[]>([]);
  const [tempHistories, setTempHistories] = useState<TemperatureHistory[]>([]);
  const [clientStats, setClientStats] = useState<ClientStats[]>([]);
  
  const cpuLastDataRef = useRef<string>('');
  const memLastDataRef = useRef<string>('');
  const loadLastDataRef = useRef<string>('');
  const diskLastDataRef = useRef<string>('');
  const tempLastDataRef = useRef<string>('');
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch system metrics (CPU/Memory/Load) historical data
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setCpuHistoricalData([]);
          setMemHistoricalData([]);
          setLoadHistoricalData([]);
          cpuLastDataRef.current = '';
          memLastDataRef.current = '';
          loadLastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/system/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: SystemHistory = await response.json();
          const newDataString = JSON.stringify(data.data);
          
          if (newDataString !== cpuLastDataRef.current) {
            setCpuHistoricalData(data.data);
            setMemHistoricalData(data.data);
            setLoadHistoricalData(data.data);
            cpuLastDataRef.current = newDataString;
            memLastDataRef.current = newDataString;
            loadLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch system history:', error);
      }
    };
    
    cpuLastDataRef.current = '';
    memLastDataRef.current = '';
    loadLastDataRef.current = '';
    fetchHistory();
    const interval = setInterval(fetchHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, refreshInterval, token]);

  // Fetch disk I/O historical data
  useEffect(() => {
    const fetchDiskIOHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setDiskIOHistories([]);
          diskLastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/system/disk-io/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: DiskIOHistory[] = await response.json();
          // Filter out partitions (devices ending with numbers)
          const filteredData = data.filter(d => !d.device.match(/\d$/));
          const newDataString = JSON.stringify(filteredData);
          
          if (newDataString !== diskLastDataRef.current) {
            setDiskIOHistories(filteredData);
            diskLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch disk I/O history:', error);
      }
    };
    
    diskLastDataRef.current = '';
    fetchDiskIOHistory();
    const interval = setInterval(fetchDiskIOHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, refreshInterval, token]);

  // Fetch temperature historical data
  useEffect(() => {
    const fetchTempHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setTempHistories([]);
          tempLastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/system/temperatures/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: TemperatureHistory[] = await response.json();
          const newDataString = JSON.stringify(data);
          
          if (newDataString !== tempLastDataRef.current) {
            setTempHistories(data);
            tempLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch temperature history:', error);
      }
    };
    
    tempLastDataRef.current = '';
    fetchTempHistory();
    const interval = setInterval(fetchTempHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, refreshInterval, token]);

  // Fetch client stats
  useEffect(() => {
    const fetchClientStats = async () => {
      if (!token) return;
      
      try {
        const response = await fetch('/api/system/clients', {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: ClientStats[] = await response.json();
          setClientStats(data);
        }
      } catch (error) {
        console.error('Failed to fetch client stats:', error);
      }
    };
    
    fetchClientStats();
    const interval = setInterval(fetchClientStats, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [refreshInterval, token]);

  // Get physical disk name
  const getDiskName = (device: string) => {
    if (device.startsWith('nvme')) return `NVMe ${device}`;
    if (device.startsWith('sd')) return `Disk ${device.toUpperCase()}`;
    return device;
  };

  // Memoize chart data
  const cpuChartData = useMemo(() => {
    return cpuHistoricalData.map(p => ({
      time: new Date(p.timestamp).toLocaleTimeString(),
      cpu: p.cpu_percent || 0,
    }));
  }, [cpuHistoricalData]);

  const memChartData = useMemo(() => {
    return memHistoricalData.map(p => ({
      time: new Date(p.timestamp).toLocaleTimeString(),
      memory: p.memory_percent || 0,
    }));
  }, [memHistoricalData]);

  const loadChartData = useMemo(() => {
    return loadHistoricalData.map(p => ({
      time: new Date(p.timestamp).toLocaleTimeString(),
      load: p.load_avg_1m || 0,
    }));
  }, [loadHistoricalData]);

  const currentCpu = cpuChartData.length > 0 ? cpuChartData[cpuChartData.length - 1].cpu : 0;
  const currentMem = memChartData.length > 0 ? memChartData[memChartData.length - 1].memory : 0;
  const currentLoad = loadChartData.length > 0 ? loadChartData[loadChartData.length - 1].load : 0;

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
            <h1 className="text-2xl md:text-3xl font-bold">System Monitoring</h1>
            
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
                  <option value={1}>1 second</option>
                  <option value={5}>5 seconds</option>
                  <option value={10}>10 seconds</option>
                  <option value={30}>30 seconds</option>
                  <option value={60}>1 minute</option>
                </Select>
              </div>
            </div>
          </div>
        </div>
        
        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          {/* Grid: 2 columns on desktop, 1 on mobile */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* CPU Usage Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">CPU Usage</h3>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={cpuChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis 
                    domain={[0, 100]} 
                    tick={{ fontSize: 12 }} 
                    label={{ value: '%', angle: -90, position: 'insideLeft' }}
                  />
                  <Tooltip content={<CustomTooltip />} />
                  <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={2} dot={false} name="CPU" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentCpu.toFixed(1)}%</strong> • {cpuChartData.length} points
              </div>
            </Card>

            {/* Memory Usage Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">Memory Usage</h3>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={memChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis 
                    domain={[0, 100]} 
                    tick={{ fontSize: 12 }} 
                    label={{ value: '%', angle: -90, position: 'insideLeft' }}
                  />
                  <Tooltip content={<CustomTooltip />} />
                  <Line type="monotone" dataKey="memory" stroke="#10b981" strokeWidth={2} dot={false} name="Memory" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentMem.toFixed(1)}%</strong> • {memChartData.length} points
              </div>
            </Card>

            {/* Load Average Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">Load Average</h3>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={loadChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis 
                    tick={{ fontSize: 12 }} 
                    label={{ value: 'Load (1m)', angle: -90, position: 'insideLeft' }}
                  />
                  <Tooltip content={<CustomTooltip />} />
                  <Line type="monotone" dataKey="load" stroke="#f59e0b" strokeWidth={2} dot={false} name="Load" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentLoad.toFixed(2)}</strong> • {loadChartData.length} points
              </div>
            </Card>

            {/* Disk I/O Charts */}
            {diskIOHistories.map(diskHistory => {
              const diskData = diskHistory.data.map(d => ({
                time: new Date(d.timestamp).toLocaleTimeString(),
                read_mbps: d.read_mbps,
                write_mbps: d.write_mbps,
              }));
              const currentRead = diskData.length > 0 ? diskData[diskData.length - 1].read_mbps : 0;
              const currentWrite = diskData.length > 0 ? diskData[diskData.length - 1].write_mbps : 0;
              
              return (
                <Card key={diskHistory.device}>
                  <h3 className="text-lg font-semibold mb-4">Disk I/O - {getDiskName(diskHistory.device)}</h3>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={diskData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis 
                        tick={{ fontSize: 12 }} 
                        label={{ value: 'MB/s', angle: -90, position: 'insideLeft' }}
                      />
                      <Tooltip content={<CustomTooltip />} />
                      <Legend />
                      <Line type="monotone" dataKey="read_mbps" stroke="#3b82f6" strokeWidth={2} dot={false} name="Read (MB/s)" isAnimationActive={false} />
                      <Line type="monotone" dataKey="write_mbps" stroke="#ef4444" strokeWidth={2} dot={false} name="Write (MB/s)" isAnimationActive={false} />
                    </LineChart>
                  </ResponsiveContainer>
                  <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                    Current: <strong className="text-blue-600">↓ {currentRead.toFixed(2)} MB/s</strong> / <strong className="text-red-600">↑ {currentWrite.toFixed(2)} MB/s</strong> • {diskData.length} points
                  </div>
                </Card>
              );
            })}

            {/* Temperature Charts */}
            {tempHistories.map(tempHistory => {
              const tempData = tempHistory.data.map(d => ({
                time: new Date(d.timestamp).toLocaleTimeString(),
                temperature: d.temperature_c,
              }));
              const currentTemp = tempData.length > 0 ? tempData[tempData.length - 1].temperature : 0;
              
              return (
                <Card key={tempHistory.sensor_name}>
                  <h3 className="text-lg font-semibold mb-4">Temperature - {tempHistory.sensor_name}</h3>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={tempData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis 
                        tick={{ fontSize: 12 }} 
                        label={{ value: '°C', angle: -90, position: 'insideLeft' }}
                      />
                      <Tooltip content={<CustomTooltip />} />
                      <Line 
                        type="monotone" 
                        dataKey="temperature" 
                        stroke={currentTemp >= 80 ? '#ef4444' : currentTemp >= 70 ? '#f59e0b' : '#10b981'} 
                        strokeWidth={2} 
                        dot={false} 
                        name="Temperature" 
                        isAnimationActive={false} 
                      />
                    </LineChart>
                  </ResponsiveContainer>
                  <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                    Current: <strong className={currentTemp >= 80 ? 'text-red-600' : currentTemp >= 70 ? 'text-yellow-600' : 'text-green-600'}>
                      {currentTemp.toFixed(1)}°C
                    </strong> • {tempData.length} points
                  </div>
                </Card>
              );
            })}
          </div>

          {/* Network Clients - Full Width */}
          {clientStats.length > 0 && (
            <Card className="mt-6">
              <h3 className="text-lg font-semibold mb-4">Network Clients</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {clientStats.map((network) => (
                  <div key={network.network} className="border rounded-lg p-4 bg-gray-50 dark:bg-gray-800">
                    <div className="flex justify-between items-center mb-3">
                      <h4 className="font-semibold text-lg uppercase">{network.network}</h4>
                      <Badge color={network.network === 'homelab' ? 'info' : 'purple'}>
                        {network.total_clients} Total
                      </Badge>
                    </div>
                    <div className="space-y-2 text-sm">
                      <div className="flex justify-between">
                        <span className="text-gray-600 dark:text-gray-400">DHCP Clients:</span>
                        <span className="font-semibold">{network.dhcp_clients}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-600 dark:text-gray-400">Static Clients:</span>
                        <span className="font-semibold">{network.static_clients}</span>
                      </div>
                      <div className="flex justify-between border-t pt-2">
                        <span className="text-gray-600 dark:text-gray-400">Online:</span>
                        <span className="font-semibold text-green-600">{network.online_clients}</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-gray-600 dark:text-gray-400">Offline:</span>
                        <span className="font-semibold text-gray-500">{network.offline_clients}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </main>
      </div>
    </div>
  );
}
