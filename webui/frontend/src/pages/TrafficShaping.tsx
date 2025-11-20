/**
 * Traffic Shaping (CAKE) monitoring page
 */
import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Badge, Select, TextInput, Label, Accordion } from 'flowbite-react';
import { 
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  BarChart, Bar, AreaChart, Area
} from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { CustomTooltip } from '../components/charts/CustomTooltip';

interface CakeTrafficClass {
  pk_delay_ms?: number;
  av_delay_ms?: number;
  sp_delay_ms?: number;
  bytes?: number;
  packets?: number;
  drops?: number;
  marks?: number;
}

interface CakeStats {
  timestamp: string;
  interface: string;
  rate_mbps?: number;
  target_ms?: number;
  interval_ms?: number;
  classes?: Record<string, CakeTrafficClass>;
  way_inds?: number;
  way_miss?: number;
  way_cols?: number;
}

interface CakeDataPoint {
  timestamp: string;
  rate_mbps?: number;
  target_ms?: number;
  interval_ms?: number;
  classes?: Record<string, CakeTrafficClass>;
  way_inds?: number;
  way_miss?: number;
  way_cols?: number;
}

interface CakeHistory {
  interface: string;
  data: CakeDataPoint[];
}

export function TrafficShaping() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  // CAKE status
  const [cakeEnabled, setCakeEnabled] = useState(false);
  const [cakeInterface, setCakeInterface] = useState<string | null>(null);
  
  // Controls
  const [timeRange, setTimeRange] = useState('1h');
  const [customRange, setCustomRange] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(10);
  
  // Current stats
  const [currentStats, setCurrentStats] = useState<CakeStats | null>(null);
  
  // Historical data
  const [history, setHistory] = useState<CakeHistory | null>(null);
  
  const lastStatsRef = useRef<string>('');
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Check CAKE status
  useEffect(() => {
    const checkStatus = async () => {
      if (!token) return;
      
      try {
        const status = await apiClient.getCakeStatus();
        setCakeEnabled(status.enabled);
        setCakeInterface(status.interface || null);
      } catch (error) {
        console.error('Failed to check CAKE status:', error);
        setCakeEnabled(false);
      }
    };
    
    checkStatus();
    const interval = setInterval(checkStatus, 60000); // Check every minute
    return () => clearInterval(interval);
  }, [token]);

  // Fetch current stats
  useEffect(() => {
    const fetchCurrent = async () => {
      if (!token || !cakeEnabled) return;
      
      try {
        const stats = await apiClient.getCurrentCakeStats();
        if (stats) {
          setCurrentStats(stats);
        }
      } catch (error) {
        console.error('Failed to fetch current CAKE stats:', error);
      }
    };
    
    fetchCurrent();
    const interval = setInterval(fetchCurrent, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [token, cakeEnabled, refreshInterval]);

  // Fetch historical data
  useEffect(() => {
    const fetchHistory = async () => {
      if (!token || !cakeEnabled) return;
      
      try {
        const range = timeRange === 'custom' ? customRange : timeRange;
        if (!range || (timeRange === 'custom' && !customRange)) {
          setHistory(null);
          return;
        }
        
        const data = await apiClient.getCakeHistory(range, cakeInterface || undefined);
        setHistory(data);
      } catch (error) {
        console.error('Failed to fetch CAKE history:', error);
      }
    };
    
    fetchHistory();
    const interval = setInterval(fetchHistory, refreshInterval * 1000);
    return () => clearInterval(interval);
  }, [token, cakeEnabled, timeRange, customRange, refreshInterval, cakeInterface]);

  // Calculate average latency
  const getAverageLatency = (): number | null => {
    if (!currentStats?.classes) return null;
    
    const delays: number[] = [];
    Object.values(currentStats.classes).forEach(cls => {
      if (cls.av_delay_ms !== undefined) {
        delays.push(cls.av_delay_ms);
      }
    });
    
    return delays.length > 0 ? delays.reduce((a, b) => a + b, 0) / delays.length : null;
  };

  // Calculate total throughput
  const getTotalThroughput = (): number => {
    if (!currentStats?.classes) return 0;
    
    let totalBytes = 0;
    Object.values(currentStats.classes).forEach(cls => {
      if (cls.bytes) totalBytes += cls.bytes;
    });
    
    // This is cumulative bytes, not rate. For rate, we'd need to track changes over time.
    return 0; // Placeholder
  };

  // Calculate total drops and marks
  const getTotalDropsMarks = (): { drops: number; marks: number } => {
    if (!currentStats?.classes) return { drops: 0, marks: 0 };
    
    let drops = 0;
    let marks = 0;
    Object.values(currentStats.classes).forEach(cls => {
      if (cls.drops) drops += cls.drops;
      if (cls.marks) marks += cls.marks;
    });
    
    return { drops, marks };
  };

  // Prepare chart data
  const prepareChartData = () => {
    if (!history?.data) return [];
    
    return history.data.map(point => ({
      time: new Date(point.timestamp).toLocaleTimeString(),
      timestamp: point.timestamp,
      rate_mbps: point.rate_mbps || 0,
      bulk_av_delay: point.classes?.bulk?.av_delay_ms || 0,
      bulk_pk_delay: point.classes?.bulk?.pk_delay_ms || 0,
      besteffort_av_delay: point.classes?.['best-effort']?.av_delay_ms || 0,
      besteffort_pk_delay: point.classes?.['best-effort']?.pk_delay_ms || 0,
      video_av_delay: point.classes?.video?.av_delay_ms || 0,
      video_pk_delay: point.classes?.video?.pk_delay_ms || 0,
      voice_av_delay: point.classes?.voice?.av_delay_ms || 0,
      voice_pk_delay: point.classes?.voice?.pk_delay_ms || 0,
      bulk_bytes: point.classes?.bulk?.bytes || 0,
      besteffort_bytes: point.classes?.['best-effort']?.bytes || 0,
      video_bytes: point.classes?.video?.bytes || 0,
      voice_bytes: point.classes?.voice?.bytes || 0,
      bulk_drops: point.classes?.bulk?.drops || 0,
      besteffort_drops: point.classes?.['best-effort']?.drops || 0,
      video_drops: point.classes?.video?.drops || 0,
      voice_drops: point.classes?.voice?.drops || 0,
      bulk_marks: point.classes?.bulk?.marks || 0,
      besteffort_marks: point.classes?.['best-effort']?.marks || 0,
      video_marks: point.classes?.video?.marks || 0,
      voice_marks: point.classes?.voice?.marks || 0,
    }));
  };

  const chartData = prepareChartData();
  const avgLatency = getAverageLatency();
  const totalThroughput = getTotalThroughput();
  const { drops, marks } = getTotalDropsMarks();

  if (!cakeEnabled) {
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
          
          <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900 flex items-center justify-center">
            <Card className="max-w-md w-full">
              <div className="text-center">
                <h2 className="text-2xl font-bold mb-4">CAKE Traffic Shaping Disabled</h2>
                <p className="text-gray-600 dark:text-gray-400">
                  CAKE traffic shaping is not enabled on this router.
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-500 mt-2">
                  Enable CAKE in router-config.nix to view traffic shaping statistics.
                </p>
              </div>
            </Card>
          </main>
        </div>
      </div>
    );
  }

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
            <h1 className="text-2xl md:text-3xl font-bold">Traffic Shaping</h1>
            
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
          {/* Status Header Card */}
          <Card className="mb-6">
            <div className="flex justify-between items-center">
              <div>
                <h2 className="text-xl font-semibold mb-2">CAKE Status</h2>
                <div className="flex gap-4 text-sm">
                  <div>
                    <span className="text-gray-600 dark:text-gray-400">Interface: </span>
                    <Badge color="info">{cakeInterface || 'Unknown'}</Badge>
                  </div>
                  <div>
                    <span className="text-gray-600 dark:text-gray-400">Status: </span>
                    <Badge color="success">Enabled</Badge>
                  </div>
                  {currentStats && (
                    <div>
                      <span className="text-gray-600 dark:text-gray-400">Last Updated: </span>
                      <span className="text-gray-900 dark:text-gray-100">
                        {new Date(currentStats.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </Card>

          {/* Key Metrics Cards */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <Card>
              <div className="text-center">
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Detected Bandwidth</p>
                <p className="text-3xl font-bold">
                  {currentStats?.rate_mbps ? `${currentStats.rate_mbps.toFixed(2)}` : '--'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500 mt-1">Mbps</p>
              </div>
            </Card>
            
            <Card>
              <div className="text-center">
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Average Latency</p>
                <p className="text-3xl font-bold">
                  {avgLatency ? `${avgLatency.toFixed(2)}` : '--'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500 mt-1">ms</p>
              </div>
            </Card>
            
            <Card>
              <div className="text-center">
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Total Throughput</p>
                <p className="text-3xl font-bold">
                  {totalThroughput > 0 ? `${totalThroughput.toFixed(2)}` : '--'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500 mt-1">Mbps</p>
              </div>
            </Card>
            
            <Card>
              <div className="text-center">
                <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Packet Drops/Marks</p>
                <p className="text-2xl font-bold">
                  {drops} / {marks}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-500 mt-1">drops / marks</p>
              </div>
            </Card>
          </div>

          {/* Charts */}
          <div className="grid grid-cols-1 gap-6 mb-6">
            {/* Bandwidth Detection Chart */}
            {chartData.length > 0 && (
              <Card>
                <h3 className="text-lg font-semibold mb-4">Bandwidth Detection</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <LineChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="time" 
                      tick={{ fontSize: 12 }}
                      interval={Math.floor(chartData.length / 8)}
                    />
                    <YAxis 
                      tick={{ fontSize: 12 }} 
                      label={{ value: 'Mbps', angle: -90, position: 'insideLeft' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Line 
                      type="monotone" 
                      dataKey="rate_mbps" 
                      stroke="#3b82f6" 
                      name="Rate (Mbps)"
                      strokeWidth={2}
                      dot={false}
                      isAnimationActive={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </Card>
            )}

            {/* Latency Over Time Chart */}
            {chartData.length > 0 && (
              <Card>
                <h3 className="text-lg font-semibold mb-4">Latency Over Time</h3>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="time" 
                      tick={{ fontSize: 12 }}
                      interval={Math.floor(chartData.length / 8)}
                    />
                    <YAxis 
                      tick={{ fontSize: 12 }} 
                      label={{ value: 'ms', angle: -90, position: 'insideLeft' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Line type="monotone" dataKey="bulk_av_delay" stroke="#6b7280" name="Bulk Avg" strokeWidth={2} dot={false} isAnimationActive={false} />
                    <Line type="monotone" dataKey="besteffort_av_delay" stroke="#3b82f6" name="Best Effort Avg" strokeWidth={2} dot={false} isAnimationActive={false} />
                    <Line type="monotone" dataKey="video_av_delay" stroke="#f97316" name="Video Avg" strokeWidth={2} dot={false} isAnimationActive={false} />
                    <Line type="monotone" dataKey="voice_av_delay" stroke="#ef4444" name="Voice Avg" strokeWidth={2} dot={false} isAnimationActive={false} />
                  </LineChart>
                </ResponsiveContainer>
              </Card>
            )}

            {/* Traffic Class Distribution */}
            {chartData.length > 0 && (
              <Card>
                <h3 className="text-lg font-semibold mb-4">Traffic Class Distribution (Bytes)</h3>
                <ResponsiveContainer width="100%" height={300}>
                  <AreaChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="time" 
                      tick={{ fontSize: 12 }}
                      interval={Math.floor(chartData.length / 8)}
                    />
                    <YAxis 
                      tick={{ fontSize: 12 }} 
                      label={{ value: 'Bytes', angle: -90, position: 'insideLeft' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Area type="monotone" dataKey="bulk_bytes" stackId="1" stroke="#6b7280" fill="#6b7280" name="Bulk" />
                    <Area type="monotone" dataKey="besteffort_bytes" stackId="1" stroke="#3b82f6" fill="#3b82f6" name="Best Effort" />
                    <Area type="monotone" dataKey="video_bytes" stackId="1" stroke="#f97316" fill="#f97316" name="Video" />
                    <Area type="monotone" dataKey="voice_bytes" stackId="1" stroke="#ef4444" fill="#ef4444" name="Voice" />
                  </AreaChart>
                </ResponsiveContainer>
              </Card>
            )}

            {/* Packet Drops and Marks */}
            {chartData.length > 0 && (
              <Card>
                <h3 className="text-lg font-semibold mb-4">Packet Drops and ECN Marks</h3>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="time" 
                      tick={{ fontSize: 12 }}
                      interval={Math.floor(chartData.length / 8)}
                    />
                    <YAxis 
                      yAxisId="left"
                      tick={{ fontSize: 12 }} 
                      label={{ value: 'Drops', angle: -90, position: 'insideLeft' }}
                    />
                    <YAxis 
                      yAxisId="right"
                      orientation="right"
                      tick={{ fontSize: 12 }} 
                      label={{ value: 'Marks', angle: 90, position: 'insideRight' }}
                    />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Line yAxisId="left" type="monotone" dataKey="bulk_drops" stroke="#ef4444" name="Bulk Drops" strokeWidth={2} dot={false} isAnimationActive={false} />
                    <Line yAxisId="right" type="monotone" dataKey="bulk_marks" stroke="#fbbf24" name="Bulk Marks" strokeWidth={2} dot={false} isAnimationActive={false} />
                  </LineChart>
                </ResponsiveContainer>
              </Card>
            )}
          </div>

          {/* Traffic Class Details Accordion */}
          {currentStats?.classes && Object.keys(currentStats.classes).length > 0 && (
            <Card className="mb-6">
              <h3 className="text-lg font-semibold mb-4">Traffic Class Details</h3>
              <Accordion>
                {Object.entries(currentStats.classes).map(([className, classStats]) => (
                  <Accordion.Panel key={className}>
                    <Accordion.Title className="capitalize">{className}</Accordion.Title>
                    <Accordion.Content>
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Peak Delay</p>
                          <p className="text-lg font-semibold">
                            {classStats.pk_delay_ms !== undefined ? `${classStats.pk_delay_ms.toFixed(2)} ms` : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Average Delay</p>
                          <p className="text-lg font-semibold">
                            {classStats.av_delay_ms !== undefined ? `${classStats.av_delay_ms.toFixed(2)} ms` : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Sparse Delay</p>
                          <p className="text-lg font-semibold">
                            {classStats.sp_delay_ms !== undefined ? `${classStats.sp_delay_ms.toFixed(2)} ms` : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Bytes</p>
                          <p className="text-lg font-semibold">
                            {classStats.bytes !== undefined ? `${(classStats.bytes / 1024 / 1024).toFixed(2)} MB` : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Packets</p>
                          <p className="text-lg font-semibold">
                            {classStats.packets !== undefined ? classStats.packets.toLocaleString() : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Drops</p>
                          <p className="text-lg font-semibold text-red-600">
                            {classStats.drops !== undefined ? classStats.drops.toLocaleString() : '--'}
                          </p>
                        </div>
                        <div>
                          <p className="text-sm text-gray-600 dark:text-gray-400">Marks</p>
                          <p className="text-lg font-semibold text-yellow-600">
                            {classStats.marks !== undefined ? classStats.marks.toLocaleString() : '--'}
                          </p>
                        </div>
                      </div>
                    </Accordion.Content>
                  </Accordion.Panel>
                ))}
              </Accordion>
            </Card>
          )}

          {/* Hash Performance */}
          {currentStats && (currentStats.way_inds !== undefined || currentStats.way_miss !== undefined || currentStats.way_cols !== undefined) && (
            <Card>
              <h3 className="text-lg font-semibold mb-4">Hash Performance</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="text-center">
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Indirect Hits</p>
                  <p className="text-2xl font-bold">
                    {currentStats.way_inds !== undefined ? currentStats.way_inds.toLocaleString() : '--'}
                  </p>
                </div>
                <div className="text-center">
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Misses</p>
                  <p className="text-2xl font-bold">
                    {currentStats.way_miss !== undefined ? currentStats.way_miss.toLocaleString() : '--'}
                  </p>
                </div>
                <div className="text-center">
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">Collisions</p>
                  <p className="text-2xl font-bold">
                    {currentStats.way_cols !== undefined ? currentStats.way_cols.toLocaleString() : '--'}
                  </p>
                </div>
              </div>
              {(currentStats.way_inds !== undefined && currentStats.way_miss !== undefined) && (
                <div className="mt-4 text-center text-sm text-gray-600 dark:text-gray-400">
                  Hit Rate: {((currentStats.way_inds / (currentStats.way_inds + currentStats.way_miss)) * 100).toFixed(2)}%
                </div>
              )}
            </Card>
          )}

          {chartData.length === 0 && currentStats === null && (
            <div className="text-center py-8">
              <p className="text-gray-500">No CAKE statistics available. Ensure CAKE is properly configured.</p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

