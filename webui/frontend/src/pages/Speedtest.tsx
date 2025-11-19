/**
 * Speedtest page - View past results and trigger new tests
 */
import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Button, Select, Table, TextInput, Label, Progress } from 'flowbite-react';
import { HiX, HiArrowDown, HiArrowUp } from 'react-icons/hi';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { CustomTooltip } from '../components/charts/CustomTooltip';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface SpeedtestResult {
  id: number;
  timestamp: string;
  download_mbps: number;
  upload_mbps: number;
  ping_ms: number;
  server_name?: string;
  server_location?: string;
}

interface SpeedtestHistoryResponse {
  results: SpeedtestResult[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

interface SpeedtestStatus {
  is_running: boolean;
  progress?: number;
  current_phase?: string;
  download_mbps?: number;
  upload_mbps?: number;
  ping_ms?: number;
}

interface ChartDataPoint {
  timestamp: string;
  download_mbps: number;
  upload_mbps: number;
  ping_ms: number;
}

const TIME_RANGES = [
  { value: 1, label: '1 hour' },
  { value: 3, label: '3 hours' },
  { value: 6, label: '6 hours' },
  { value: 12, label: '12 hours' },
  { value: 24, label: '1 day' },
  { value: 168, label: '1 week' },
  { value: 336, label: '2 weeks' },
  { value: 720, label: '1 month' },
  { value: 2160, label: '3 months' },
  { value: 4320, label: '6 months' },
  { value: 8760, label: '1 year' },
];

const PAGE_SIZES = [10, 25, 50, 100];

export function Speedtest() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  const { connectionStatus } = useMetrics(token);
  
  // Time range for chart
  const [timeRangeHours, setTimeRangeHours] = useState(24);
  
  // Chart data
  const [chartData, setChartData] = useState<ChartDataPoint[]>([]);
  
  // Table pagination
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const [customPageSize, setCustomPageSize] = useState('');
  const [showCustomPageSize, setShowCustomPageSize] = useState(false);
  const [tableData, setTableData] = useState<SpeedtestHistoryResponse | null>(null);
  
  // Speedtest status
  const [status, setStatus] = useState<SpeedtestStatus>({ is_running: false });
  const [showResults, setShowResults] = useState(false);
  const statusIntervalRef = useRef<number | null>(null);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch chart data
  useEffect(() => {
    const fetchChartData = async () => {
      if (!token) return;
      
      try {
        const response = await fetch(`/api/speedtest/chart-data?hours=${timeRangeHours}`, {
          headers: {
            'Authorization': `Bearer ${token}`,
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          setChartData(data.data || []);
        }
      } catch (error) {
        console.error('Error fetching chart data:', error);
      }
    };
    
    fetchChartData();
    const interval = setInterval(fetchChartData, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, [token, timeRangeHours]);

  // Fetch table data
  useEffect(() => {
    const fetchTableData = async () => {
      if (!token) return;
      
      try {
        const endTime = new Date();
        const startTime = new Date(endTime.getTime() - timeRangeHours * 60 * 60 * 1000);
        
        const response = await fetch(
          `/api/speedtest/history?start_time=${startTime.toISOString()}&end_time=${endTime.toISOString()}&page=${currentPage}&page_size=${pageSize}`,
          {
            headers: {
              'Authorization': `Bearer ${token}`,
            },
          }
        );
        
        if (response.ok) {
          const data: SpeedtestHistoryResponse = await response.json();
          setTableData(data);
        }
      } catch (error) {
        console.error('Error fetching table data:', error);
      }
    };
    
    fetchTableData();
  }, [token, timeRangeHours, currentPage, pageSize]);

  // Poll speedtest status when running
  useEffect(() => {
    if (status.is_running) {
      const pollStatus = async () => {
        try {
          const response = await fetch('/api/speedtest/status', {
            headers: {
              'Authorization': `Bearer ${token}`,
            },
          });
          
          if (response.ok) {
            const newStatus: SpeedtestStatus = await response.json();
            setStatus(newStatus);
            
            // If test completed, refresh data and keep results visible
            if (!newStatus.is_running && status.is_running) {
              // Keep showResults true so results stay visible
              // Refresh chart and table
              const fetchChartData = async () => {
                try {
                  const response = await fetch(`/api/speedtest/chart-data?hours=${timeRangeHours}`, {
                    headers: { 'Authorization': `Bearer ${token}` },
                  });
                  if (response.ok) {
                    const data = await response.json();
                    setChartData(data.data || []);
                  }
                } catch (error) {
                  console.error('Error fetching chart data:', error);
                }
              };
              
              const fetchTableData = async () => {
                try {
                  const endTime = new Date();
                  const startTime = new Date(endTime.getTime() - timeRangeHours * 60 * 60 * 1000);
                  const response = await fetch(
                    `/api/speedtest/history?start_time=${startTime.toISOString()}&end_time=${endTime.toISOString()}&page=${currentPage}&page_size=${pageSize}`,
                    { headers: { 'Authorization': `Bearer ${token}` } }
                  );
                  if (response.ok) {
                    const data: SpeedtestHistoryResponse = await response.json();
                    setTableData(data);
                  }
                } catch (error) {
                  console.error('Error fetching table data:', error);
                }
              };
              
              fetchChartData();
              fetchTableData();
            }
          }
        } catch (error) {
          console.error('Error polling status:', error);
        }
      };
      
      statusIntervalRef.current = window.setInterval(pollStatus, 1000); // Poll every second
      return () => {
        if (statusIntervalRef.current) {
          clearInterval(statusIntervalRef.current);
        }
      };
    } else {
      if (statusIntervalRef.current) {
        clearInterval(statusIntervalRef.current);
        statusIntervalRef.current = null;
      }
    }
  }, [status.is_running, token, timeRangeHours, currentPage, pageSize]);

  const handleTriggerSpeedtest = async () => {
    if (!token) return;
    
    try {
      const response = await fetch('/api/speedtest/trigger', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
      
      if (response.ok) {
        // Start polling status and show results
        setStatus({ is_running: true, progress: 0 });
        setShowResults(true);
      }
    } catch (error) {
      console.error('Error triggering speedtest:', error);
    }
  };

  const handlePageSizeChange = (value: string) => {
    if (value === 'custom') {
      setShowCustomPageSize(true);
    } else {
      setPageSize(parseInt(value));
      setCurrentPage(1);
      setShowCustomPageSize(false);
      setCustomPageSize('');
    }
  };

  const handleCustomPageSizeSubmit = () => {
    const size = parseInt(customPageSize);
    if (size >= 1 && size <= 200) {
      setPageSize(size);
      setCurrentPage(1);
      setShowCustomPageSize(false);
      setCustomPageSize('');
    }
  };

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  return (
    <div className="flex h-screen bg-gray-50 dark:bg-gray-900">
      <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} onLogout={handleLogout} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Navbar
          hostname="nixos-router"
          username={username}
          connectionStatus={connectionStatus}
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
        />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-7xl mx-auto space-y-6">
            <div className="flex justify-between items-center">
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Speedtest</h1>
              <Button
                onClick={handleTriggerSpeedtest}
                disabled={status.is_running}
                color="blue"
              >
                {status.is_running ? 'Running...' : 'Run Speedtest'}
              </Button>
            </div>

            {/* Speedtest Results Display */}
            {(status.is_running || showResults) && (
              <Card className="relative">
                {/* Close Button */}
                <button
                  onClick={() => setShowResults(false)}
                  className="absolute top-4 right-4 p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                  aria-label="Close results"
                >
                  <HiX className="w-5 h-5" />
                </button>
                
                <div className="text-center pr-8">
                  <h3 className="text-xl font-semibold mb-6">
                    {status.is_running ? 'Speedtest in Progress' : 'Speedtest Results'}
                  </h3>
                  
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-6">
                    {/* Download */}
                    <div className="text-center">
                      <div className="flex items-center justify-center gap-2 mb-2">
                        <span className="text-sm font-medium text-gray-600 dark:text-gray-400">Download</span>
                        <HiArrowDown 
                          className={`w-5 h-5 text-blue-600 dark:text-blue-400 ${
                            status.is_running && status.current_phase === 'download' 
                              ? 'animate-pulse drop-shadow-lg' 
                              : ''
                          }`}
                          style={
                            status.is_running && status.current_phase === 'download'
                              ? {
                                  filter: 'drop-shadow(0 0 8px rgba(59, 130, 246, 0.8))',
                                  animation: 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
                                }
                              : {}
                          }
                        />
                      </div>
                      <div className={`text-5xl font-bold text-blue-600 dark:text-blue-400 ${
                        status.is_running && status.current_phase === 'download' 
                          ? 'drop-shadow-lg' 
                          : ''
                      }`}
                      style={
                        status.is_running && status.current_phase === 'download'
                          ? {
                              filter: 'drop-shadow(0 0 12px rgba(59, 130, 246, 0.6))',
                              animation: 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
                            }
                          : {}
                      }>
                        {status.download_mbps ? `${status.download_mbps.toFixed(2)}` : '--'}
                      </div>
                      <div className="text-lg text-gray-500 dark:text-gray-400 mt-1">Mbps</div>
                    </div>

                    {/* Upload */}
                    <div className="text-center">
                      <div className="flex items-center justify-center gap-2 mb-2">
                        <span className="text-sm font-medium text-gray-600 dark:text-gray-400">Upload</span>
                        <HiArrowUp 
                          className={`w-5 h-5 text-green-600 dark:text-green-400 ${
                            status.is_running && status.current_phase === 'upload' 
                              ? 'animate-pulse drop-shadow-lg' 
                              : ''
                          }`}
                          style={
                            status.is_running && status.current_phase === 'upload'
                              ? {
                                  filter: 'drop-shadow(0 0 8px rgba(16, 185, 129, 0.8))',
                                  animation: 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
                                }
                              : {}
                          }
                        />
                      </div>
                      <div className={`text-5xl font-bold text-green-600 dark:text-green-400 ${
                        status.is_running && status.current_phase === 'upload' 
                          ? 'drop-shadow-lg' 
                          : ''
                      }`}
                      style={
                        status.is_running && status.current_phase === 'upload'
                          ? {
                              filter: 'drop-shadow(0 0 12px rgba(16, 185, 129, 0.6))',
                              animation: 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite',
                            }
                          : {}
                      }>
                        {status.upload_mbps ? `${status.upload_mbps.toFixed(2)}` : '--'}
                      </div>
                      <div className="text-lg text-gray-500 dark:text-gray-400 mt-1">Mbps</div>
                    </div>

                    {/* Ping */}
                    <div className="text-center">
                      <div className="text-sm font-medium text-gray-600 dark:text-gray-400 mb-2">Ping</div>
                      <div className="text-5xl font-bold text-gray-700 dark:text-gray-300">
                        {status.ping_ms ? `${status.ping_ms.toFixed(2)}` : '--'}
                      </div>
                      <div className="text-lg text-gray-500 dark:text-gray-400 mt-1">ms</div>
                    </div>
                  </div>
                  
                  {status.is_running && status.progress !== undefined && (
                    <div className="mt-4">
                      <Progress progress={status.progress} color="blue" />
                      <div className="text-sm text-gray-500 mt-2 text-center">
                        {status.current_phase || 'Starting...'}
                      </div>
                    </div>
                  )}
                </div>
              </Card>
            )}

            {/* Chart */}
            <Card>
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-xl font-semibold">Speedtest Results</h3>
                <Select
                  value={timeRangeHours}
                  onChange={(e) => {
                    setTimeRangeHours(parseInt(e.target.value));
                    setCurrentPage(1);
                  }}
                  className="w-48"
                >
                  {TIME_RANGES.map(range => (
                    <option key={range.value} value={range.value}>{range.label}</option>
                  ))}
                </Select>
              </div>
              <ResponsiveContainer width="100%" height={400}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis 
                    dataKey="timestamp" 
                    tickFormatter={(value) => new Date(value).toLocaleTimeString()}
                  />
                  <YAxis label={{ value: 'Mbps', angle: -90, position: 'insideLeft' }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Legend />
                  <Line 
                    type="monotone" 
                    dataKey="download_mbps" 
                    stroke="#3b82f6" 
                    name="Download"
                    dot={false}
                  />
                  <Line 
                    type="monotone" 
                    dataKey="upload_mbps" 
                    stroke="#10b981" 
                    name="Upload"
                    dot={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            </Card>

            {/* Results Table */}
            <Card>
              <div className="flex justify-between items-center mb-4">
                <h3 className="text-xl font-semibold">Test History</h3>
                <div className="flex items-center gap-2">
                  <Label htmlFor="page-size">Results per page:</Label>
                  {showCustomPageSize ? (
                    <div className="flex gap-2">
                      <TextInput
                        id="custom-page-size"
                        type="number"
                        min="1"
                        max="200"
                        value={customPageSize}
                        onChange={(e) => setCustomPageSize(e.target.value)}
                        onKeyPress={(e) => {
                          if (e.key === 'Enter') {
                            handleCustomPageSizeSubmit();
                          }
                        }}
                        className="w-20"
                      />
                      <Button size="sm" onClick={handleCustomPageSizeSubmit}>Apply</Button>
                      <Button size="sm" color="gray" onClick={() => {
                        setShowCustomPageSize(false);
                        setCustomPageSize('');
                      }}>Cancel</Button>
                    </div>
                  ) : (
                    <Select
                      id="page-size"
                      value={pageSize.toString()}
                      onChange={(e) => handlePageSizeChange(e.target.value)}
                      className="w-32"
                    >
                      {PAGE_SIZES.map(size => (
                        <option key={size} value={size.toString()}>{size}</option>
                      ))}
                      <option value="custom">Custom</option>
                    </Select>
                  )}
                </div>
              </div>
              <Table>
                <Table.Head>
                  <Table.HeadCell>Timestamp</Table.HeadCell>
                  <Table.HeadCell>Download (Mbps)</Table.HeadCell>
                  <Table.HeadCell>Upload (Mbps)</Table.HeadCell>
                  <Table.HeadCell>Ping (ms)</Table.HeadCell>
                  <Table.HeadCell>Server</Table.HeadCell>
                </Table.Head>
                <Table.Body className="divide-y">
                  {tableData?.results.map((result) => (
                    <Table.Row key={result.id}>
                      <Table.Cell>{formatTimestamp(result.timestamp)}</Table.Cell>
                      <Table.Cell>{result.download_mbps.toFixed(2)}</Table.Cell>
                      <Table.Cell>{result.upload_mbps.toFixed(2)}</Table.Cell>
                      <Table.Cell>{result.ping_ms.toFixed(2)}</Table.Cell>
                      <Table.Cell>{result.server_name || '-'}</Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </Table>
              {tableData && tableData.total_pages > 1 && (
                <div className="flex justify-between items-center mt-4">
                  <div className="text-sm text-gray-500">
                    Showing {((currentPage - 1) * pageSize) + 1} to {Math.min(currentPage * pageSize, tableData.total)} of {tableData.total} results
                  </div>
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      color="gray"
                      disabled={currentPage === 1}
                      onClick={() => setCurrentPage(currentPage - 1)}
                    >
                      Previous
                    </Button>
                    <Button
                      size="sm"
                      color="gray"
                      disabled={currentPage === tableData.total_pages}
                      onClick={() => setCurrentPage(currentPage + 1)}
                    >
                      Next
                    </Button>
                  </div>
                </div>
              )}
            </Card>
          </div>
        </main>
      </div>
    </div>
  );
}

