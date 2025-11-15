/**
 * Historical data page (placeholder for Stage 1)
 */
import { useNavigate } from 'react-router-dom';
import { Card } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function History() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

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
          <h1 className="text-3xl font-bold mb-6">Historical Data</h1>
          
          <Card>
            <p className="text-gray-600">
              Historical data visualization will be implemented here.
              This page will show long-term bandwidth trends, system metrics over time,
              and service uptime statistics.
            </p>
          </Card>
        </main>
      </div>
    </div>
  );
}

