/**
 * System monitoring page with comprehensive metrics and charts
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface SystemSnapshot {
  timestamp: string;
  system: {
    cpu_percent: number;
    memory_percent: number;
    memory_used_mb: number;
    memory_total_mb: number;
    load_avg_1m: number;
    load_avg_5m: number;
    load_avg_15m: number;
    uptime_seconds: number;
  };
  disk_io: Array<{
    device: string;
    read_bytes_per_sec: number;
    write_bytes_per_sec: number;
  }>;
  temperatures: Array<{
    sensor_name: string;
    temperature_c: number;
    label: string | null;
    critical: number | null;
  }>;
  clients: Array<{
    network: string;
    dhcp_clients: number;
    static_clients: number;
    total_clients: number;
    online_clients: number;
    offline_clients: number;
  }>;
}

interface HistoricalDataPoint {
  time: string;
  timestamp: number;
  cpu: number;
  memory: number;
  load1m: number;
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

export function System() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [systemData, setSystemData] = useState<SystemSnapshot | null>(null);
  const [timeRange, setTimeRange] = useState('30m');
  const [customRange, setCustomRange] = useState('');
  
  // Historical data storage
  const [historicalData, setHistoricalData] = useState<HistoricalDataPoint[]>([]);
  const [diskIOHistory, setDiskIOHistory] = useState<Map<string, DiskIODataPoint[]>>(new Map());
  const [tempHistory, setTempHistory] = useState<Map<string, TempDataPoint[]>>(new Map());
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Parse time range to milliseconds
  const getTimeRangeMs = () => {
    const range = timeRange === 'custom' ? customRange : timeRange;
    const match = range.match(/^(\d+)([mhd])$/);
    if (!match) return 30 * 60 * 1000; // Default 30 minutes
    
    const value = parseInt(match[1]);
    const unit = match[2];
    
    switch (unit) {
      case 'm': return value * 60 * 1000;
      case 'h': return value * 60 * 60 * 1000;
      case 'd': return value * 24 * 60 * 60 * 1000;
      default: return 30 * 60 * 1000;
    }
  };

  // Fetch current system snapshot
  useEffect(() => {
    const fetchSystemData = async () => {
      if (!token) return;
      
      try {
        const response = await fetch('/api/system/current', {
          headers: {
            'Authorization': `Bearer ${token}`,
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          setSystemData(data);
          
          const now = Date.now();
          const timeStr = new Date().toLocaleTimeString();
          const maxAge = getTimeRangeMs();
          const cutoff = now - maxAge;
          
          // Update system metrics history
          setHistoricalData(prev => {
            const newData = [...prev, {
              time: timeStr,
              timestamp: now,
              cpu: data.system.cpu_percent,
              memory: data.system.memory_percent,
              load1m: data.system.load_avg_1m,
            }];
            // Filter to time range
            return newData.filter(d => d.timestamp > cutoff);
          });
          
          // Update disk I/O history
          if (data.disk_io && data.disk_io.length > 0) {
            setDiskIOHistory(prev => {
              const newMap = new Map(prev);
              
              data.disk_io.forEach((disk: any) => {
                // Only track physical disks (sda, sdb, nvme0n1, etc), not partitions
                if (disk.device.match(/\d$/)) return; // Skip if ends with number (partition)
                
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
        }
      } catch (error) {
        console.error('Failed to fetch system data:', error);
      }
    };
    
    fetchSystemData();
    const interval = setInterval(fetchSystemData, 2000); // Update every 2 seconds
    return () => clearInterval(interval);
  }, [token, timeRange, customRange]);

  // Get friendly sensor names
  const getSensorName = (sensorName: string, label: string | null) => {
    if (label) return label;
    
    // Common sensor name mappings
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
      if (sensorName.toLowerCase().includes(key.toLowerCase())) {
        return name;
      }
    }
    
    return sensorName;
  };

  // Get physical disk name
  const getDiskName = (device: string) => {
    if (device.startsWith('nvme')) return `NVMe ${device}`;
    if (device.startsWith('sd')) return `Disk ${device.toUpperCase()}`;
    return device;
  };

  // Get physical disks (no partitions)
  const getPhysicalDisks = () => {
    return Array.from(diskIOHistory.keys()).filter(device => !device.match(/\d$/));
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
        
        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-4 md:mb-6 gap-3">
            <h1 className="text-2xl md:text-3xl font-bold">System Monitoring</h1>
            
            {/* Time Range Selector */}
            <div className="flex gap-2 flex-wrap">
              <Select
                value={timeRange}
                onChange={(e) => setTimeRange(e.target.value)}
                sizing="sm"
              >
                <option value="10m">10 minutes</option>
                <option value="30m">30 minutes</option>
                <option value="1h">1 hour</option>
                <option value="3h">3 hours</option>
                <option value="6h">6 hours</option>
                <option value="12h">12 hours</option>
                <option value="1d">1 day</option>
                <option value="custom">Custom</option>
              </Select>
              
              {timeRange === 'custom' && (
                <TextInput
                  placeholder="e.g., 45m, 2h, 1d"
                  value={customRange}
                  onChange={(e) => setCustomRange(e.target.value)}
                  sizing="sm"
                  className="w-32"
                />
              )}
            </div>
          </div>
          
          {!systemData && (
            <Card>
              <p className="text-center text-gray-500">Loading system data...</p>
            </Card>
          )}

          {systemData && (
            <>
              {/* 1. CPU Usage Chart */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">CPU Usage</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={historicalData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                    <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} label={{ value: '%', angle: -90, position: 'insideLeft' }} />
                    <Tooltip />
                    <Line 
                      type="monotone" 
                      dataKey="cpu" 
                      stroke="#3b82f6" 
                      strokeWidth={2} 
                      dot={false}
                      name="CPU %"
                      isAnimationActive={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
                <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                  Current: <strong>{systemData.system.cpu_percent.toFixed(1)}%</strong>
                </div>
              </Card>

              {/* 2. Memory Usage Chart */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">Memory Usage</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={historicalData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                    <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} label={{ value: '%', angle: -90, position: 'insideLeft' }} />
                    <Tooltip />
                    <Line 
                      type="monotone" 
                      dataKey="memory" 
                      stroke="#10b981" 
                      strokeWidth={2} 
                      dot={false}
                      name="Memory %"
                      isAnimationActive={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
                <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                  Current: <strong>{systemData.system.memory_percent.toFixed(1)}%</strong>
                  {' '}({(systemData.system.memory_used_mb / 1024).toFixed(1)} / {(systemData.system.memory_total_mb / 1024).toFixed(1)} GB)
                </div>
              </Card>

              {/* 3. Load Average Chart */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">Load Average (1 minute)</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={historicalData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                    <YAxis tick={{ fontSize: 12 }} />
                    <Tooltip />
                    <Line 
                      type="monotone" 
                      dataKey="load1m" 
                      stroke="#f59e0b" 
                      strokeWidth={2} 
                      dot={false}
                      name="Load (1m)"
                      isAnimationActive={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
                <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                  Current: <strong>{systemData.system.load_avg_1m.toFixed(2)}</strong>
                  {' '}(5m: {systemData.system.load_avg_5m.toFixed(2)}, 15m: {systemData.system.load_avg_15m.toFixed(2)})
                </div>
              </Card>

              {/* 4. Disk I/O Charts - One per physical disk */}
              {getPhysicalDisks().map(device => {
                const diskData = diskIOHistory.get(device) || [];
                return (
                  <Card key={device} className="mb-6">
                    <h3 className="text-lg font-semibold mb-4">Disk I/O - {getDiskName(device)}</h3>
                    <ResponsiveContainer width="100%" height={250}>
                      <LineChart data={diskData}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                        <YAxis tick={{ fontSize: 12 }} label={{ value: 'MB/s', angle: -90, position: 'insideLeft' }} />
                        <Tooltip />
                        <Legend />
                        <Line 
                          type="monotone" 
                          dataKey="read_mbps" 
                          stroke="#3b82f6" 
                          strokeWidth={2} 
                          dot={false}
                          name="Read"
                          isAnimationActive={false}
                        />
                        <Line 
                          type="monotone" 
                          dataKey="write_mbps" 
                          stroke="#ef4444" 
                          strokeWidth={2} 
                          dot={false}
                          name="Write"
                          isAnimationActive={false}
                        />
                      </LineChart>
                    </ResponsiveContainer>
                    <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                      {diskData.length > 0 && (
                        <>
                          Current: <strong className="text-blue-600">↓ {diskData[diskData.length - 1].read_mbps.toFixed(2)} MB/s</strong>
                          {' / '}
                          <strong className="text-red-600">↑ {diskData[diskData.length - 1].write_mbps.toFixed(2)} MB/s</strong>
                        </>
                      )}
                    </div>
                  </Card>
                );
              })}

              {/* 5. Temperature Charts - One per sensor */}
              {Array.from(tempHistory.keys()).map(sensorName => {
                const tempData = tempHistory.get(sensorName) || [];
                const currentTemp = tempData.length > 0 ? tempData[tempData.length - 1].temperature : 0;
                
                return (
                  <Card key={sensorName} className="mb-6">
                    <h3 className="text-lg font-semibold mb-4">Temperature - {sensorName}</h3>
                    <ResponsiveContainer width="100%" height={250}>
                      <LineChart data={tempData}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                        <YAxis tick={{ fontSize: 12 }} label={{ value: '°C', angle: -90, position: 'insideLeft' }} />
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
                      </strong>
                    </div>
                  </Card>
                );
              })}

              {/* 6. Network Clients (Text Display) */}
              <Card className="mb-6">
                <h3 className="text-lg font-semibold mb-4">Network Clients</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {systemData.clients.map((network) => (
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

              {/* No Sensors Message */}
              {systemData.temperatures.length === 0 && (
                <Card className="mb-6">
                  <p className="text-center text-gray-500">
                    Temperature sensors not available on this system
                  </p>
                </Card>
              )}
            </>
          )}
        </main>
      </div>
    </div>
  );
}
