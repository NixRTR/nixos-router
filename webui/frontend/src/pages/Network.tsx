/**
 * Network bandwidth page with all interface charts
 */
import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput, Label } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface BandwidthDataPoint {
  timestamp: string;
  rx_mbps: number;
  tx_mbps: number;
}

interface BandwidthHistory {
  interface: string;
  data: BandwidthDataPoint[];
}

export function Network() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(10);
  const [bandwidthHistories, setBandwidthHistories] = useState<BandwidthHistory[]>([]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const lastDataRef = useRef<string>('');
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch historical data for all interfaces
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setBandwidthHistories([]);
          lastDataRef.current = '';
          return;
        }
        
        const response = await fetch(`/api/bandwidth/history?range=${range}`, {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        
        if (response.ok) {
          const data: BandwidthHistory[] = await response.json();
          // Filter to main interfaces only
          const filteredData = data.filter(d => ['ppp0', 'br0', 'br1'].includes(d.interface));
          const newDataString = JSON.stringify(filteredData);
          
          if (newDataString !== lastDataRef.current) {
            setBandwidthHistories(filteredData);
            lastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch bandwidth history:', error);
      }
    };
    
    lastDataRef.current = '';
    fetchHistory();
    const interval = setInterval(fetchHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [timeRange, customRange, refreshInterval, token]);

  // Get friendly interface name
  const getInterfaceName = (iface: string) => {
    const names: { [key: string]: string } = {
      'ppp0': 'WAN',
      'br0': 'HOMELAB',
      'br1': 'LAN',
    };
    return names[iface] || iface;
  };

  // Get color for interface badge
  const getInterfaceColor = (iface: string): 'info' | 'success' | 'purple' | 'gray' => {
    const colors: { [key: string]: 'info' | 'success' | 'purple' } = {
      'ppp0': 'info',
      'br0': 'success',
      'br1': 'purple',
    };
    return colors[iface] || 'gray';
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
        
        {/* Sticky Global Controls */}
        <div className="sticky top-0 z-10 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-4 md:px-6 py-3 shadow-sm">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-3">
            <h1 className="text-2xl md:text-3xl font-bold">Network Bandwidth</h1>
            
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
                  <option value="3d">3 days</option>
                  <option value="7d">7 days</option>
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
          {/* Grid: 1 column on all devices */}
          <div className="grid grid-cols-1 gap-6">
            {bandwidthHistories.map((history) => {
              const chartData = history.data.map((point) => ({
                time: new Date(point.timestamp).toLocaleTimeString(),
                download: point.rx_mbps || 0,
                upload: point.tx_mbps || 0,
              }));

              const currentDownload = chartData.length > 0 ? chartData[chartData.length - 1].download : 0;
              const currentUpload = chartData.length > 0 ? chartData[chartData.length - 1].upload : 0;

              return (
                <Card key={history.interface}>
                  <div className="flex justify-between items-center mb-4">
                    <h3 className="text-lg font-semibold">{getInterfaceName(history.interface)}</h3>
                    <Badge color={getInterfaceColor(history.interface)} size="sm">
                      {history.interface}
                    </Badge>
                  </div>
                  
                  <ResponsiveContainer width="100%" height={250}>
                    <LineChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis 
                        dataKey="time" 
                        tick={{ fontSize: 12 }}
                        interval={Math.floor(chartData.length / 8)}
                      />
                      <YAxis tick={{ fontSize: 12 }} />
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
                  
                  <div className="mt-2 text-sm text-gray-600 dark:text-gray-400 text-center">
                    Current: <strong className="text-blue-600">↓ {currentDownload.toFixed(2)} Mbps</strong> / <strong className="text-green-600">↑ {currentUpload.toFixed(2)} Mbps</strong> • {chartData.length} points
                  </div>
                </Card>
              );
            })}
          </div>

          {bandwidthHistories.length === 0 && (
            <div className="text-center py-8">
              <p className="text-gray-500">No bandwidth data available for this time range.</p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
