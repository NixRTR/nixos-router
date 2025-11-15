/**
 * Network bandwidth page with charts
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Select } from 'flowbite-react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function Network() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [selectedInterface, setSelectedInterface] = useState('ppp0');
  
  const { connectionStatus, interfaceHistory } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  const history = interfaceHistory.get(selectedInterface) || [];
  const chartData = history.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString(),
    download: point.rx_rate_mbps || 0,
    upload: point.tx_rate_mbps || 0,
  }));

  return (
    <div className="flex h-screen">
      <Sidebar onLogout={handleLogout} />
      
      <div className="flex-1 flex flex-col overflow-hidden">
        <Navbar
          hostname="nixos-router"
          username={username}
          connectionStatus={connectionStatus}
        />
        
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50 dark:bg-gray-900">
          <h1 className="text-3xl font-bold mb-6">Network Bandwidth</h1>
          
          <Card>
            <div className="mb-4">
              <label className="block text-sm font-medium mb-2">Select Interface</label>
              <Select
                value={selectedInterface}
                onChange={(e) => setSelectedInterface(e.target.value)}
              >
                <option value="ppp0">WAN (ppp0)</option>
                <option value="br0">HOMELAB (br0)</option>
                <option value="br1">LAN (br1)</option>
              </Select>
            </div>
            
            <ResponsiveContainer width="100%" height={400}>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="time" />
                <YAxis label={{ value: 'Mbps', angle: -90, position: 'insideLeft' }} />
                <Tooltip />
                <Legend />
                <Line type="monotone" dataKey="download" stroke="#3b82f6" name="Download" />
                <Line type="monotone" dataKey="upload" stroke="#10b981" name="Upload" />
              </LineChart>
            </ResponsiveContainer>
          </Card>
        </main>
      </div>
    </div>
  );
}

