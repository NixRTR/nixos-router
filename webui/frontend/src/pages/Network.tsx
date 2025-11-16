/**
 * Network bandwidth page with charts
 */
import { useState, useEffect, useRef, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Select, TextInput, Label } from 'flowbite-react';
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
  const [selectedInterface, setSelectedInterface] = useState('ppp0');
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(10); // seconds
  const [historicalData, setHistoricalData] = useState<BandwidthDataPoint[]>([]);
  const [loading, setLoading] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const lastDataRef = useRef<string>(''); // Track last data to prevent unnecessary updates
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch historical data when interface or time range changes
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token) return;
      
      // Only show loading on first load or when changing settings
      if (historicalData.length === 0) {
        setLoading(true);
      }
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setHistoricalData([]);
          lastDataRef.current = '';
          return;
        }
        
        const response = await fetch(
          `/api/bandwidth/history?interface=${selectedInterface}&range=${range}`,
          {
            headers: {
              'Authorization': `Bearer ${token}`,
            },
          }
        );
        
        if (response.ok) {
          const data: BandwidthHistory[] = await response.json();
          const interfaceData = data.find(d => d.interface === selectedInterface);
          const newData = interfaceData?.data || [];
          
          // Only update if data actually changed (prevents unnecessary re-renders)
          const newDataString = JSON.stringify(newData);
          if (newDataString !== lastDataRef.current) {
            setHistoricalData(newData);
            lastDataRef.current = newDataString;
          }
        }
      } catch (error) {
        console.error('Failed to fetch bandwidth history:', error);
      } finally {
        setLoading(false);
      }
    };
    
    // Reset on interface/range change
    lastDataRef.current = '';
    fetchHistory();
    
    // Refresh based on user-selected interval
    const interval = setInterval(fetchHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [selectedInterface, timeRange, customRange, refreshInterval, token]);

  // Memoize chart data to prevent unnecessary recalculations
  const chartData = useMemo(() => {
    return historicalData.map((point) => ({
      time: new Date(point.timestamp).toLocaleTimeString(),
      download: point.rx_mbps || 0,
      upload: point.tx_mbps || 0,
    }));
  }, [historicalData]);

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
          <h1 className="text-3xl font-bold mb-6">Network Bandwidth</h1>
          
          <Card>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
              {/* Interface Selector */}
              <div>
                <Label htmlFor="interface" value="Select Interface" />
                <Select
                  id="interface"
                  value={selectedInterface}
                  onChange={(e) => setSelectedInterface(e.target.value)}
                >
                  <option value="ppp0">WAN (ppp0)</option>
                  <option value="br0">HOMELAB (br0)</option>
                  <option value="br1">LAN (br1)</option>
                </Select>
              </div>
              
              {/* Time Range Selector */}
              <div>
                <Label htmlFor="timeRange" value="Time Range" />
                <Select
                  id="timeRange"
                  value={timeRange}
                  onChange={(e) => setTimeRange(e.target.value)}
                >
                  <option value="10m">10 minutes</option>
                  <option value="30m">30 minutes</option>
                  <option value="1h">1 hour</option>
                  <option value="3h">3 hours</option>
                  <option value="12h">12 hours</option>
                  <option value="24h">24 hours</option>
                  <option value="3d">3 days</option>
                  <option value="7d">7 days</option>
                  <option value="1M">1 month</option>
                  <option value="1y">1 year</option>
                  <option value="custom">Custom</option>
                </Select>
              </div>
              
              {/* Refresh Interval Selector */}
              <div>
                <Label htmlFor="refreshInterval" value="Update Every" />
                <Select
                  id="refreshInterval"
                  value={refreshInterval}
                  onChange={(e) => setRefreshInterval(Number(e.target.value))}
                >
                  <option value={1}>1 second</option>
                  <option value={5}>5 seconds</option>
                  <option value={10}>10 seconds</option>
                  <option value={30}>30 seconds</option>
                  <option value={60}>1 minute</option>
                </Select>
              </div>
              
              {/* Custom Range Input (shows when "custom" is selected) */}
              {timeRange === 'custom' && (
                <div>
                  <Label htmlFor="customRange" value="Custom Range" />
                  <TextInput
                    id="customRange"
                    type="text"
                    placeholder="e.g., 5m, 2h, 1d"
                    value={customRange}
                    onChange={(e) => setCustomRange(e.target.value)}
                    helperText="Examples: 5m, 30m, 1h, 2d, 1w"
                  />
                </div>
              )}
            </div>
            
            {loading && (
              <div className="text-center py-4">
                <p className="text-gray-500">Loading bandwidth data...</p>
              </div>
            )}
            
            {!loading && chartData.length === 0 && (
              <div className="text-center py-8">
                <p className="text-gray-500">No bandwidth data available for this time range.</p>
              </div>
            )}
            
            {!loading && chartData.length > 0 && (
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
                    name="⬇ Download"
                    strokeWidth={2}
                    dot={false}
                    isAnimationActive={false}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="upload" 
                    stroke="#10b981" 
                    name="⬆ Upload"
                    strokeWidth={2}
                    dot={false}
                    isAnimationActive={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
            
            <div className="mt-4 text-sm text-gray-500">
              <p>
                Showing {chartData.length} data points over the last {timeRange === 'custom' ? customRange : timeRange}
                {' • '}Auto-refreshing every {refreshInterval === 1 ? '1 second' : `${refreshInterval} seconds`}
              </p>
            </div>
          </Card>
        </main>
      </div>
    </div>
  );
}

