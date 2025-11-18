/**
 * Documentation Page - Links to the React documentation site
 * 
 * Opens the documentation in a new tab/window
 */
import { useNavigate } from 'react-router-dom';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { useState, useEffect } from 'react';

export function Documentation() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  const { connectionStatus } = useMetrics(token);

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Automatically open documentation in a new tab when component mounts
  useEffect(() => {
    const docsUrl = '/docs';
    window.open(docsUrl, '_blank', 'noopener,noreferrer');
  }, []);

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
          <div className="max-w-4xl mx-auto">
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-8 text-center">
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-4">
                Documentation
              </h1>
              <p className="text-gray-600 dark:text-gray-300 mb-6">
                The documentation should have opened in a new tab. If it didn't, click the link below.
              </p>
              <a
                href="/docs"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center px-6 py-3 text-base font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 focus:ring-4 focus:ring-blue-300 dark:focus:ring-blue-800 transition-colors"
              >
                Open Documentation
                <svg className="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                </svg>
              </a>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

