/**
 * System monitoring page with historical charts
 */
import { useState, useEffect, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput, Label } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
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
  time: string;
  timestamp: number;
  read_mbps: number;
  write_mbps: number;
}

interface TempDataPoint {
  time: string;
  timestamp: number;
  temperature: number;
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
  
  // Shared time range for all charts
  const [timeRange, setTimeRange] = useState('30m');
  const [customRange, setCustomRange] = useState('');
  
  // System metrics (CPU/Memory/Load) - from database
  const [cpuRefreshInterval, setCpuRefreshInterval] = useState(10);
  const [cpuHistoricalData, setCpuHistoricalData] = useState<SystemDataPoint[]>([]);
  const cpuLastDataRef = useRef<string>('');
  
  const [memRefreshInterval, setMemRefreshInterval] = useState(10);
  const [memHistoricalData, setMemHistoricalData] = useState<SystemDataPoint[]>([]);
  const memLastDataRef = useRef<string>('');
  
  const [loadRefreshInterval, setLoadRefreshInterval] = useState(10);
  const [loadHistoricalData, setLoadHistoricalData] = useState<SystemDataPoint[]>([]);
  const loadLastDataRef = useRef<string>('');
  
  // Real-time data (Disk I/O, Temps, Clients)
  const [diskRefreshInterval, setDiskRefreshInterval] = useState(10);
  const [diskIOHistory, setDiskIOHistory] = useState<Map<string, DiskIODataPoint[]>>(new Map());
  
  const [tempRefreshInterval, setTempRefreshInterval] = useState(10);
  const [tempHistory, setTempHistory] = useState<Map<string, TempDataPoint[]>>(new Map());
  
  const [clientStats, setClientStats] = useState<ClientStats[]>([]);
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Parse time range to milliseconds
  const getTimeRangeMs = () => {
    const rangeStr = timeRange === 'custom' ? customRange : timeRange;
    const match = rangeStr.match(/^(\d+)([mhd])$/);
    if (!match) return 30 * 60 * 1000;
    
    const value = parseInt(match[1]);
    const unit = match[2];
    
    switch (unit) {
      case 'm': return value * 60 * 1000;
      case 'h': return value * 60 * 60 * 1000;
      case 'd': return value * 24 * 60 * 60 * 1000;
      default: return 30 * 60 * 1000;
    }
  };

  // Fetch CPU historical data
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setCpuHistoricalData([]);
          cpuLastDataRef.current = '';
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
            cpuLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch CPU history:', error);
      }
    };
    
    cpuLastDataRef.current = '';
    fetchHistory();
    const interval = setInterval(fetchHistory, cpuRefreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, cpuRefreshInterval, token]);

  // Fetch Memory historical data
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setMemHistoricalData([]);
          memLastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/system/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: SystemHistory = await response.json();
          const newDataString = JSON.stringify(data.data);
          if (newDataString !== memLastDataRef.current) {
            setMemHistoricalData(data.data);
            memLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch memory history:', error);
      }
    };
    
    memLastDataRef.current = '';
    fetchHistory();
    const interval = setInterval(fetchHistory, memRefreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, memRefreshInterval, token]);

  // Fetch Load historical data
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setLoadHistoricalData([]);
          loadLastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/system/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: SystemHistory = await response.json();
          const newDataString = JSON.stringify(data.data);
          if (newDataString !== loadLastDataRef.current) {
            setLoadHistoricalData(data.data);
            loadLastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch load history:', error);
      }
    };
    
    loadLastDataRef.current = '';
    fetchHistory();
    const interval = setInterval(fetchHistory, loadRefreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, loadRefreshInterval, token]);

  // Fetch real-time data for disk I/O, temps, clients
  useEffect(() => {
    const fetchRealTimeData = async () => {
      if (!token) return;
      
      try {
        const response = await fetch('/api/system/current', {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data = await response.json();
          const now = Date.now();
          const timeStr = new Date().toLocaleTimeString();
          
          // Update disk I/O history
          if (data.disk_io && data.disk_io.length > 0) {
            const maxAge = getTimeRangeMs();
            const cutoff = now - maxAge;
            
            setDiskIOHistory(prev => {
              const newMap = new Map(prev);
              data.disk_io.forEach((disk: any) => {
                if (disk.device.match(/\d$/)) return;
                const history = newMap.get(disk.device) || [];
                const newPoint = {
                  time: timeStr,
                  timestamp: now,
                  read_mbps: disk.read_bytes_per_sec / (1024 * 1024),
                  write_mbps: disk.write_bytes_per_sec / (1024 * 1024),
                };
                const updated = [...history, newPoint].filter(d => d.timestamp > cutoff);
                newMap.set(disk.device, updated);
              });
              return newMap;
            });
          }
          
          // Update temperature history
          if (data.temperatures && data.temperatures.length > 0) {
            const maxAge = getTimeRangeMs();
            const cutoff = now - maxAge;
            
            setTempHistory(prev => {
              const newMap = new Map(prev);
              data.temperatures.forEach((temp: any) => {
                const key = getSensorName(temp.sensor_name, temp.label);
                const history = newMap.get(key) || [];
                const newPoint = {
                  time: timeStr,
                  timestamp: now,
                  temperature: temp.temperature_c,
                };
                const updated = [...history, newPoint].filter(d => d.timestamp > cutoff);
                newMap.set(key, updated);
              });
              return newMap;
            });
          }
          
          // Update client stats
          if (data.clients) {
            setClientStats(data.clients);
          }
        }
      } catch (error) {
        console.error('Failed to fetch real-time data:', error);
      }
    };
    
    fetchRealTimeData();
    const diskInterval = setInterval(fetchRealTimeData, diskRefreshInterval * 1000);
    return () => clearInterval(diskInterval);
  }, [timeRange, customRange, diskRefreshInterval, tempRefreshInterval, token]);

  // Get friendly sensor names
  const getSensorName = (sensorName: string, label: string | null) => {
    if (label) return label;
    const nameMap: { [key: string]: string } = {
      'coretemp': 'CPU',
      'k10temp': 'CPU',
      'cpu_thermal': 'CPU',
      'acpitz': 'Motherboard',
      'pch_skylake': 'PCH',
      'iwlwifi_1': 'WiFi',
      'nvme': 'NVMe SSD',
      'drivetemp': 'HDD',
    };
    for (const [key, name] of Object.entries(nameMap)) {
      if (sensorName.toLowerCase().includes(key.toLowerCase())) return name;
    }
    return sensorName;
  };

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
        
        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          <h1 className="text-2xl md:text-3xl font-bold mb-4 md:mb-6">System Monitoring</h1>
          
          {/* Grid: 2 columns on desktop, 1 on mobile */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* CPU Usage Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">CPU Usage</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2 mb-4">
                <div>
                  <Label htmlFor="cpu-range" value="Time Range" className="text-xs" />
                  <Select id="cpu-range" sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                    <option value="10m">10 min</option>
                    <option value="30m">30 min</option>
                    <option value="1h">1 hour</option>
                    <option value="3h">3 hours</option>
                    <option value="6h">6 hours</option>
                    <option value="12h">12 hours</option>
                    <option value="1d">1 day</option>
                    <option value="custom">Custom</option>
                  </Select>
                </div>
                {timeRange === 'custom' && (
                  <div>
                    <Label htmlFor="cpu-custom" value="Custom" className="text-xs" />
                    <TextInput id="cpu-custom" sizing="sm" placeholder="e.g., 45m" value={customRange} onChange={(e) => setCustomRange(e.target.value)} />
                  </div>
                )}
                <div>
                  <Label htmlFor="cpu-refresh" value="Update Every" className="text-xs" />
                  <Select id="cpu-refresh" sizing="sm" value={cpuRefreshInterval} onChange={(e) => setCpuRefreshInterval(Number(e.target.value))}>
                    <option value={1}>1 sec</option>
                    <option value={5}>5 sec</option>
                    <option value={10}>10 sec</option>
                    <option value={30}>30 sec</option>
                    <option value={60}>1 min</option>
                  </Select>
                </div>
              </div>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={cpuChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Line type="monotone" dataKey="cpu" stroke="#3b82f6" strokeWidth={2} dot={false} name="CPU %" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentCpu.toFixed(1)}%</strong> • {cpuChartData.length} points
              </div>
            </Card>

            {/* Memory Usage Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">Memory Usage</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2 mb-4">
                <div>
                  <Label htmlFor="mem-range" value="Time Range" className="text-xs" />
                  <Select id="mem-range" sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                    <option value="10m">10 min</option>
                    <option value="30m">30 min</option>
                    <option value="1h">1 hour</option>
                    <option value="3h">3 hours</option>
                    <option value="6h">6 hours</option>
                    <option value="12h">12 hours</option>
                    <option value="1d">1 day</option>
                    <option value="custom">Custom</option>
                  </Select>
                </div>
                {timeRange === 'custom' && (
                  <div>
                    <Label htmlFor="mem-custom" value="Custom" className="text-xs" />
                    <TextInput id="mem-custom" sizing="sm" placeholder="e.g., 45m" value={customRange} onChange={(e) => setCustomRange(e.target.value)} />
                  </div>
                )}
                <div>
                  <Label htmlFor="mem-refresh" value="Update Every" className="text-xs" />
                  <Select id="mem-refresh" sizing="sm" value={memRefreshInterval} onChange={(e) => setMemRefreshInterval(Number(e.target.value))}>
                    <option value={1}>1 sec</option>
                    <option value={5}>5 sec</option>
                    <option value={10}>10 sec</option>
                    <option value={30}>30 sec</option>
                    <option value={60}>1 min</option>
                  </Select>
                </div>
              </div>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={memChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Line type="monotone" dataKey="memory" stroke="#10b981" strokeWidth={2} dot={false} name="Memory %" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentMem.toFixed(1)}%</strong> • {memChartData.length} points
              </div>
            </Card>

            {/* Load Average Chart */}
            <Card>
              <h3 className="text-lg font-semibold mb-4">Load Average</h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2 mb-4">
                <div>
                  <Label htmlFor="load-range" value="Time Range" className="text-xs" />
                  <Select id="load-range" sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                    <option value="10m">10 min</option>
                    <option value="30m">30 min</option>
                    <option value="1h">1 hour</option>
                    <option value="3h">3 hours</option>
                    <option value="6h">6 hours</option>
                    <option value="12h">12 hours</option>
                    <option value="1d">1 day</option>
                    <option value="custom">Custom</option>
                  </Select>
                </div>
                {timeRange === 'custom' && (
                  <div>
                    <Label htmlFor="load-custom" value="Custom" className="text-xs" />
                    <TextInput id="load-custom" sizing="sm" placeholder="e.g., 45m" value={customRange} onChange={(e) => setCustomRange(e.target.value)} />
                  </div>
                )}
                <div>
                  <Label htmlFor="load-refresh" value="Update Every" className="text-xs" />
                  <Select id="load-refresh" sizing="sm" value={loadRefreshInterval} onChange={(e) => setLoadRefreshInterval(Number(e.target.value))}>
                    <option value={1}>1 sec</option>
                    <option value={5}>5 sec</option>
                    <option value={10}>10 sec</option>
                    <option value={30}>30 sec</option>
                    <option value={60}>1 min</option>
                  </Select>
                </div>
              </div>
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={loadChartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Line type="monotone" dataKey="load" stroke="#f59e0b" strokeWidth={2} dot={false} name="Load (1m)" isAnimationActive={false} />
                </LineChart>
              </ResponsiveContainer>
              <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                Current: <strong>{currentLoad.toFixed(2)}</strong> • {loadChartData.length} points
              </div>
            </Card>

            {/* Disk I/O Charts */}
            {Array.from(diskIOHistory.keys()).map(device => {
              const diskData = diskIOHistory.get(device) || [];
              const currentRead = diskData.length > 0 ? diskData[diskData.length - 1].read_mbps : 0;
              const currentWrite = diskData.length > 0 ? diskData[diskData.length - 1].write_mbps : 0;
              
              return (
                <Card key={device}>
                  <h3 className="text-lg font-semibold mb-4">Disk I/O - {getDiskName(device)}</h3>
                  <div className="grid grid-cols-2 gap-2 mb-4">
                    <div>
                      <Label htmlFor={`disk-${device}-range`} value="Time Range" className="text-xs" />
                      <Select id={`disk-${device}-range`} sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                        <option value="10m">10 min</option>
                        <option value="30m">30 min</option>
                        <option value="1h">1 hour</option>
                        <option value="3h">3 hours</option>
                        <option value="6h">6 hours</option>
                        <option value="12h">12 hours</option>
                        <option value="1d">1 day</option>
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`disk-${device}-refresh`} value="Update Every" className="text-xs" />
                      <Select id={`disk-${device}-refresh`} sizing="sm" value={diskRefreshInterval} onChange={(e) => setDiskRefreshInterval(Number(e.target.value))}>
                        <option value={1}>1 sec</option>
                        <option value={5}>5 sec</option>
                        <option value={10}>10 sec</option>
                        <option value={30}>30 sec</option>
                        <option value={60}>1 min</option>
                      </Select>
                    </div>
                  </div>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={diskData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Legend />
                      <Line type="monotone" dataKey="read_mbps" stroke="#3b82f6" strokeWidth={2} dot={false} name="Read" isAnimationActive={false} />
                      <Line type="monotone" dataKey="write_mbps" stroke="#ef4444" strokeWidth={2} dot={false} name="Write" isAnimationActive={false} />
                    </LineChart>
                  </ResponsiveContainer>
                  <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                    Current: <strong className="text-blue-600">↓ {currentRead.toFixed(2)} MB/s</strong> / <strong className="text-red-600">↑ {currentWrite.toFixed(2)} MB/s</strong> • {diskData.length} points
                  </div>
                </Card>
              );
            })}

            {/* Temperature Charts */}
            {Array.from(tempHistory.keys()).map(sensorName => {
              const tempData = tempHistory.get(sensorName) || [];
              const currentTemp = tempData.length > 0 ? tempData[tempData.length - 1].temperature : 0;
              
              return (
                <Card key={sensorName}>
                  <h3 className="text-lg font-semibold mb-4">Temperature - {sensorName}</h3>
                  <div className="grid grid-cols-2 gap-2 mb-4">
                    <div>
                      <Label htmlFor={`temp-${sensorName}-range`} value="Time Range" className="text-xs" />
                      <Select id={`temp-${sensorName}-range`} sizing="sm" value={timeRange} onChange={(e) => setTimeRange(e.target.value)}>
                        <option value="10m">10 min</option>
                        <option value="30m">30 min</option>
                        <option value="1h">1 hour</option>
                        <option value="3h">3 hours</option>
                        <option value="6h">6 hours</option>
                        <option value="12h">12 hours</option>
                        <option value="1d">1 day</option>
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`temp-${sensorName}-refresh`} value="Update Every" className="text-xs" />
                      <Select id={`temp-${sensorName}-refresh`} sizing="sm" value={tempRefreshInterval} onChange={(e) => setTempRefreshInterval(Number(e.target.value))}>
                        <option value={1}>1 sec</option>
                        <option value={5}>5 sec</option>
                        <option value={10}>10 sec</option>
                        <option value={30}>30 sec</option>
                        <option value={60}>1 min</option>
                      </Select>
                    </div>
                  </div>
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={tempData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Line 
                        type="monotone" 
                        dataKey="temperature" 
                        stroke={currentTemp >= 80 ? '#ef4444' : currentTemp >= 70 ? '#f59e0b' : '#10b981'} 
                        strokeWidth={2} 
                        dot={false} 
                        name="Temp °C" 
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
