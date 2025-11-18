/**
 * System Info Page - Displays system information with NixOS logo
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function SystemInfo() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [textData, setTextData] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    fetchFastfetch();
  }, []);

  const fetchFastfetch = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getFastfetch();
      setTextData(data.text);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch system info');
      setTextData('');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
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
        
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50 dark:bg-gray-900">
          <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-6">System Info</h1>
          
          {loading && (
            <div className="text-center py-16 text-gray-500">
              Loading system information...
            </div>
          )}
          
          {error && (
            <div className="text-center py-16 text-red-500">
              Error: {error}
            </div>
          )}
          
          {!loading && !error && textData && (
            <div className="flex gap-6 items-stretch">
              {/* NixOS Logo */}
              <div className="flex-shrink-0 flex items-center">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 128 128"
                  className="h-full w-auto dark:opacity-90"
                  preserveAspectRatio="xMidYMid meet"
                >
                  <path
                    fill="#7EBAE4"
                    d="M50.732 43.771L20.525 96.428l-7.052-12.033 8.14-14.103-16.167-.042L2 64.237l3.519-6.15 23.013.073 8.27-14.352 13.93-.037zm2.318 42.094l60.409.003-6.827 12.164-16.205-.045 8.047 14.115-3.45 6.01-7.05.008-11.445-20.097-16.483-.034-6.996-12.124zm35.16-23.074l-30.202-52.66L71.888 10l8.063 14.148 8.12-14.072 6.897.002 3.532 6.143-11.57 20.024 8.213 14.386-6.933 12.16z"
                    clipRule="evenodd"
                    fillRule="evenodd"
                  />
                  <path
                    fill="#5277C3"
                    d="M39.831 65.463l30.202 52.66-13.88.131-8.063-14.148-8.12 14.072-6.897-.002-3.532-6.143 11.57-20.024-8.213-14.386 6.933-12.16zm35.08-23.207l-60.409-.003L21.33 30.09l16.204.045-8.047-14.115 3.45-6.01 7.051-.01 11.444 20.097 16.484.034 6.996 12.124zm2.357 42.216l30.207-52.658 7.052 12.034-8.141 14.102 16.168.043L126 64.006l-3.519 6.15-23.013-.073-8.27 14.352-13.93.037z"
                    clipRule="evenodd"
                    fillRule="evenodd"
                  />
                </svg>
              </div>
              
              {/* Fastfetch Text Output */}
              <div className="flex-1">
                <pre className="font-mono text-sm whitespace-pre-wrap text-white dark:text-gray-200 bg-transparent dark:bg-transparent p-0 overflow-auto">
                  {textData}
                </pre>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

