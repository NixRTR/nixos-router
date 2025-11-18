/**
 * Documentation Page - Displays project documentation
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function Documentation() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [docContent, setDocContent] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    fetchDocumentation();
  }, []);

  const fetchDocumentation = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.getDocumentation();
      setDocContent(data.content);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch documentation');
      setDocContent('');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Simple markdown to HTML converter
  const markdownToHtml = (markdown: string): string => {
    let html = markdown;
    
    // Code blocks (handle first to avoid interfering with inline code)
    html = html.replace(/```(\w+)?\n([\s\S]*?)```/gim, '<pre class="bg-gray-100 dark:bg-gray-800 p-4 rounded overflow-x-auto"><code>$2</code></pre>');
    
    // Headers
    html = html.replace(/^### (.*$)/gim, '<h3 class="text-xl font-bold mt-6 mb-3">$1</h3>');
    html = html.replace(/^## (.*$)/gim, '<h2 class="text-2xl font-bold mt-8 mb-4">$1</h2>');
    html = html.replace(/^# (.*$)/gim, '<h1 class="text-3xl font-bold mt-8 mb-4">$1</h1>');
    
    // Bold
    html = html.replace(/\*\*(.*?)\*\*/gim, '<strong class="font-semibold">$1</strong>');
    
    // Inline code
    html = html.replace(/`([^`\n]+)`/gim, '<code class="bg-gray-100 dark:bg-gray-800 px-1 py-0.5 rounded text-sm font-mono">$1</code>');
    
    // Links
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/gim, '<a href="$2" target="_blank" rel="noopener noreferrer" class="text-blue-600 dark:text-blue-400 hover:underline">$1</a>');
    
    // Lists - handle bullet lists
    const lines = html.split('\n');
    let inList = false;
    let result: string[] = [];
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.match(/^[\-\*] /)) {
        if (!inList) {
          result.push('<ul class="list-disc list-inside my-4 space-y-1">');
          inList = true;
        }
        result.push(`<li>${line.replace(/^[\-\*] /, '')}</li>`);
      } else {
        if (inList) {
          result.push('</ul>');
          inList = false;
        }
        if (line.trim()) {
          result.push(line);
        }
      }
    }
    if (inList) {
      result.push('</ul>');
    }
    html = result.join('\n');
    
    // Paragraphs (double newlines)
    html = html.split('\n\n').map(para => {
      para = para.trim();
      if (para && !para.match(/^<[h|u|p|d|p]/)) {
        return `<p class="my-4">${para}</p>`;
      }
      return para;
    }).join('\n');
    
    // Single line breaks
    html = html.replace(/\n/gim, '<br>');
    
    return html;
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
          <h1 className="text-3xl font-bold text-gray-900 dark:text-white mb-6">Documentation</h1>
          
          {loading && (
            <div className="text-center py-16 text-gray-500">
              Loading documentation...
            </div>
          )}
          
          {error && (
            <div className="text-center py-16 text-red-500">
              Error: {error}
            </div>
          )}
          
          {!loading && !error && docContent && (
            <div 
              className="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-sm text-gray-900 dark:text-gray-100"
              dangerouslySetInnerHTML={{ __html: markdownToHtml(docContent) }}
            />
          )}
        </main>
      </div>
    </div>
  );
}

