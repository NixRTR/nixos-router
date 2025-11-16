/**
 * System monitoring page with comprehensive metrics and charts
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Progress } from 'flowbite-react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
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
    read_ops_per_sec: number;
    write_ops_per_sec: number;
  }>;
  disk_space: Array<{
    mountpoint: string;
    device: string;
    total_gb: number;
    used_gb: number;
    free_gb: number;
    percent_used: number;
  }>;
  temperatures: Array<{
    sensor_name: string;
    temperature_c: number;
    label: string | null;
    critical: number | null;
  }>;
  fans: Array<{
    fan_name: string;
    rpm: number;
    label: string | null;
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
  cpu: number;
  memory: number;
  load1m: number;
}

export function System() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [systemData, setSystemData] = useState<SystemSnapshot | null>(null);
  const [historicalData, setHistoricalData] = useState<HistoricalDataPoint[]>([]);
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
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
          
          // Add to historical data (keep last 30 points)
          const now = new Date().toLocaleTimeString();
          setHistoricalData(prev => {
            const newData = [...prev, {
              time: now,
              cpu: data.system.cpu_percent,
              memory: data.system.memory_percent,
              load1m: data.system.load_avg_1m,
            }];
            return newData.slice(-30); // Keep last 30 points
          });
        }
      } catch (error) {
        console.error('Failed to fetch system data:', error);
      }
    };
    
    fetchSystemData();
    const interval = setInterval(fetchSystemData, 2000); // Update every 2 seconds
    return () => clearInterval(interval);
  }, [token]);

  const formatUptime = (seconds: number) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    return `${days}d ${hours}h ${mins}m`;
  };

  const formatBytes = (bytes: number) => {
    if (bytes < 1024) return `${bytes.toFixed(1)} B/s`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB/s`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB/s`;
  };

  const getTemperatureColor = (temp: number, critical: number | null) => {
    if (critical && temp >= critical * 0.9) return 'red';
    if (temp >= 80) return 'red';
    if (temp >= 70) return 'yellow';
    return 'blue';
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
          <h1 className="text-2xl md:text-3xl font-bold mb-4 md:mb-6">System Monitoring</h1>
          
          {!systemData && (
            <Card>
              <p className="text-center text-gray-500">Loading system data...</p>
            </Card>
          )}

          {systemData && (
            <>
              {/* System Overview Cards */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                <Card>
                  <h3 className="text-sm font-semibold mb-2">CPU Usage</h3>
                  <div className="text-2xl font-bold mb-2">
                    {systemData.system.cpu_percent.toFixed(1)}%
                  </div>
                  <Progress
                    progress={systemData.system.cpu_percent}
                    size="sm"
                    color={
                      systemData.system.cpu_percent > 80
                        ? 'red'
                        : systemData.system.cpu_percent > 60
                        ? 'yellow'
                        : 'blue'
                    }
                  />
                </Card>

                <Card>
                  <h3 className="text-sm font-semibold mb-2">Memory Usage</h3>
                  <div className="text-2xl font-bold mb-2">
                    {systemData.system.memory_percent.toFixed(1)}%
                  </div>
                  <Progress
                    progress={systemData.system.memory_percent}
                    size="sm"
                    color={
                      systemData.system.memory_percent > 80
                        ? 'red'
                        : systemData.system.memory_percent > 60
                        ? 'yellow'
                        : 'blue'
                    }
                  />
                  <div className="text-xs text-gray-500 mt-1">
                    {(systemData.system.memory_used_mb / 1024).toFixed(1)} / {(systemData.system.memory_total_mb / 1024).toFixed(1)} GB
                  </div>
                </Card>

                <Card>
                  <h3 className="text-sm font-semibold mb-2">Load Average</h3>
                  <div className="text-2xl font-bold mb-2">
                    {systemData.system.load_avg_1m.toFixed(2)}
                  </div>
                  <div className="text-xs text-gray-500">
                    5m: {systemData.system.load_avg_5m.toFixed(2)} | 15m: {systemData.system.load_avg_15m.toFixed(2)}
                  </div>
                </Card>

                <Card>
                  <h3 className="text-sm font-semibold mb-2">Uptime</h3>
                  <div className="text-xl font-bold">
                    {formatUptime(systemData.system.uptime_seconds)}
                  </div>
                </Card>
              </div>

              {/* Historical Charts */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
                {/* CPU Chart */}
                <Card>
                  <h3 className="text-lg font-semibold mb-4">CPU Usage Over Time</h3>
                  <ResponsiveContainer width="100%" height={200}>
                    <LineChart data={historicalData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
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
                </Card>

                {/* Memory Chart */}
                <Card>
                  <h3 className="text-lg font-semibold mb-4">Memory Usage Over Time</h3>
                  <ResponsiveContainer width="100%" height={200}>
                    <LineChart data={historicalData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="time" tick={{ fontSize: 12 }} />
                      <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
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
                </Card>

                {/* Load Average Chart */}
                <Card>
                  <h3 className="text-lg font-semibold mb-4">Load Average Over Time</h3>
                  <ResponsiveContainer width="100%" height={200}>
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
                </Card>

                {/* Client Statistics Chart */}
                <Card>
                  <h3 className="text-lg font-semibold mb-4">Network Clients</h3>
                  <ResponsiveContainer width="100%" height={200}>
                    <BarChart data={systemData.clients}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="network" tick={{ fontSize: 12 }} />
                      <YAxis tick={{ fontSize: 12 }} />
                      <Tooltip />
                      <Legend />
                      <Bar dataKey="dhcp_clients" fill="#3b82f6" name="DHCP" />
                      <Bar dataKey="static_clients" fill="#10b981" name="Static" />
                      <Bar dataKey="offline_clients" fill="#6b7280" name="Offline" />
                    </BarChart>
                  </ResponsiveContainer>
                  <div className="mt-4 grid grid-cols-2 gap-2 text-sm">
                    {systemData.clients.map((network) => (
                      <div key={network.network} className="border rounded p-2">
                        <div className="font-semibold text-xs uppercase">{network.network}</div>
                        <div className="text-xs text-gray-600">
                          Total: {network.total_clients} | Online: {network.online_clients}
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              </div>

              {/* Disk I/O */}
              {systemData.disk_io.length > 0 && (
                <Card className="mb-6">
                  <h3 className="text-lg font-semibold mb-4">Disk I/O</h3>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    {systemData.disk_io.map((disk) => (
                      <div key={disk.device} className="border rounded-lg p-4">
                        <h4 className="font-semibold mb-2">{disk.device}</h4>
                        <div className="space-y-1 text-sm">
                          <div className="flex justify-between">
                            <span>Read:</span>
                            <span className="font-mono">{formatBytes(disk.read_bytes_per_sec)}</span>
                          </div>
                          <div className="flex justify-between">
                            <span>Write:</span>
                            <span className="font-mono">{formatBytes(disk.write_bytes_per_sec)}</span>
                          </div>
                          <div className="flex justify-between text-gray-500">
                            <span>Ops/s:</span>
                            <span className="font-mono">
                              {disk.read_ops_per_sec.toFixed(0)}r / {disk.write_ops_per_sec.toFixed(0)}w
                            </span>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              )}

              {/* Disk Space */}
              {systemData.disk_space.length > 0 && (
                <Card className="mb-6">
                  <h3 className="text-lg font-semibold mb-4">Disk Space</h3>
                  <div className="space-y-4">
                    {systemData.disk_space.map((disk) => (
                      <div key={disk.mountpoint} className="border rounded-lg p-4">
                        <div className="flex justify-between items-center mb-2">
                          <div>
                            <h4 className="font-semibold">{disk.mountpoint}</h4>
                            <div className="text-xs text-gray-500">{disk.device}</div>
                          </div>
                          <Badge color={disk.percent_used > 90 ? 'red' : disk.percent_used > 75 ? 'yellow' : 'green'}>
                            {disk.percent_used.toFixed(1)}%
                          </Badge>
                        </div>
                        <Progress progress={disk.percent_used} size="sm" color={disk.percent_used > 90 ? 'red' : disk.percent_used > 75 ? 'yellow' : 'blue'} />
                        <div className="text-xs text-gray-500 mt-1">
                          {disk.used_gb.toFixed(1)} GB used / {disk.total_gb.toFixed(1)} GB total ({disk.free_gb.toFixed(1)} GB free)
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              )}

              {/* Temperatures */}
              {systemData.temperatures.length > 0 && (
                <Card className="mb-6">
                  <h3 className="text-lg font-semibold mb-4">Temperature Sensors</h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                    {systemData.temperatures.map((temp, idx) => (
                      <div key={idx} className="border rounded-lg p-3">
                        <div className="text-xs text-gray-500 mb-1">
                          {temp.label || temp.sensor_name}
                        </div>
                        <div className="text-2xl font-bold">
                          {temp.temperature_c.toFixed(1)}°C
                        </div>
                        <Progress 
                          progress={(temp.temperature_c / (temp.critical || 100)) * 100} 
                          size="sm"
                          color={getTemperatureColor(temp.temperature_c, temp.critical)}
                        />
                        {temp.critical && (
                          <div className="text-xs text-gray-500 mt-1">
                            Critical: {temp.critical}°C
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </Card>
              )}

              {/* Fan Speeds */}
              {systemData.fans.length > 0 && (
                <Card className="mb-6">
                  <h3 className="text-lg font-semibold mb-4">Fan Speeds</h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                    {systemData.fans.map((fan, idx) => (
                      <div key={idx} className="border rounded-lg p-3">
                        <div className="text-xs text-gray-500 mb-1">
                          {fan.label || fan.fan_name}
                        </div>
                        <div className="text-2xl font-bold">
                          {fan.rpm.toLocaleString()} RPM
                        </div>
                      </div>
                    ))}
                  </div>
                </Card>
              )}

              {/* No Data Messages */}
              {systemData.temperatures.length === 0 && systemData.fans.length === 0 && (
                <Card className="mb-6">
                  <p className="text-center text-gray-500">
                    Temperature and fan sensors not available on this system
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

