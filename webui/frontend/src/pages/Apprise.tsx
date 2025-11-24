/**
 * Apprise Notifications Page
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Button, TextInput, Label, Textarea, Select, Badge, Alert } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { HiBell, HiCheckCircle, HiXCircle, HiInformationCircle } from 'react-icons/hi';
import { AppriseUrlGenerator } from '../components/AppriseUrlGenerator';

interface ServiceInfo {
  url: string;
  description: string;
}

export function Apprise() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [services, setServices] = useState<ServiceInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Notification form state
  const [notificationBody, setNotificationBody] = useState('');
  const [notificationTitle, setNotificationTitle] = useState('');
  const [notificationType, setNotificationType] = useState('info');
  const [sending, setSending] = useState(false);
  const [sendResult, setSendResult] = useState<{ success: boolean; message: string } | null>(null);
  
  // Send notification state - track status per service index
  const [sendingServices, setSendingServices] = useState<Set<number>>(new Set());
  const [sendResults, setSendResults] = useState<Map<number, { success: boolean; message: string; details?: string }>>(new Map());
  const [sendErrors, setSendErrors] = useState<Map<number, string>>(new Map());
  
  // Copy to clipboard state
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    fetchAppriseStatus();
  }, []);

  const fetchAppriseStatus = async () => {
    setLoading(true);
    setError(null);
    try {
      const [status, config] = await Promise.all([
        apiClient.getAppriseStatus(),
        apiClient.getAppriseConfig(),
      ]);
      
      setEnabled(status.enabled);
      
      if (config.enabled && config.services) {
        // Handle legacy format (array of strings) or new format (array of objects)
        setServices(config.services.map((s: any) => 
          typeof s === 'string' ? { url: s, description: getServiceName(s) } : s
        ));
      } else {
        const serviceList = await apiClient.getAppriseServices();
        setServices(serviceList);
      }
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to fetch Apprise status');
      setEnabled(false);
    } finally {
      setLoading(false);
    }
  };

  const handleSendNotification = async () => {
    if (!notificationBody.trim()) {
      setSendResult({ success: false, message: 'Message body is required' });
      return;
    }

    setSending(true);
    setSendResult(null);
    
    try {
      const result = await apiClient.sendAppriseNotification(
        notificationBody,
        notificationTitle || undefined,
        notificationType || undefined
      );
      setSendResult(result);
      if (result.success) {
        setNotificationBody('');
        setNotificationTitle('');
        setNotificationType('info');
      }
    } catch (err: any) {
      setSendResult({
        success: false,
        message: err.response?.data?.detail || err.message || 'Failed to send notification',
      });
    } finally {
      setSending(false);
    }
  };

  const handleSendToService = async (serviceIndex: number) => {
    if (!notificationBody.trim()) {
      setSendErrors(prev => new Map(prev).set(serviceIndex, 'Message body is required'));
      return;
    }

    setSendingServices(prev => new Set(prev).add(serviceIndex));
    setSendErrors(prev => {
      const newMap = new Map(prev);
      newMap.delete(serviceIndex);
      return newMap;
    });
    setSendResults(prev => {
      const newMap = new Map(prev);
      newMap.delete(serviceIndex);
      return newMap;
    });
    
    try {
      const result = await apiClient.sendAppriseNotificationToService(
        serviceIndex,
        notificationBody,
        notificationTitle || undefined,
        notificationType || undefined
      );
      setSendResults(prev => new Map(prev).set(serviceIndex, result));
      
      if (!result.success) {
        const errorMsg = result.details 
          ? `${result.message}: ${result.details}`
          : result.message;
        setSendErrors(prev => new Map(prev).set(serviceIndex, errorMsg));
      }
    } catch (err: any) {
      const errorMsg = err.response?.data?.detail || err.message || 'Failed to send notification';
      setSendErrors(prev => new Map(prev).set(serviceIndex, errorMsg));
      setSendResults(prev => new Map(prev).set(serviceIndex, {
        success: false,
        message: errorMsg,
      }));
    } finally {
      setSendingServices(prev => {
        const newSet = new Set(prev);
        newSet.delete(serviceIndex);
        return newSet;
      });
    }
  };

  const getCurlCommand = (serviceIndex?: number) => {
    const baseUrl = window.location.origin;
    const authToken = localStorage.getItem('access_token');
    
    // Use service-specific endpoint if index is provided
    const endpoint = serviceIndex !== undefined 
      ? `${baseUrl}/api/apprise/send/${serviceIndex}`
      : `${baseUrl}/api/apprise/notify`;
    
    return `curl -X POST ${endpoint} \\
  -H "Authorization: Bearer ${authToken}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "body": "Your notification message here",
    "title": "Notification Title (optional)",
    "notification_type": "info"
  }'`;
  };

  const copyCurlCommand = async (index: number) => {
    const command = getCurlCommand(index);
    try {
      // Try modern clipboard API first
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(command);
        setCopiedIndex(index);
        setTimeout(() => setCopiedIndex(null), 2000);
      } else {
        // Fallback for older browsers or non-HTTPS contexts
        const textArea = document.createElement('textarea');
        textArea.value = command;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        try {
          document.execCommand('copy');
          setCopiedIndex(index);
          setTimeout(() => setCopiedIndex(null), 2000);
        } catch (err) {
          console.error('Fallback copy failed:', err);
          alert('Failed to copy. Please select and copy manually.');
        }
        document.body.removeChild(textArea);
      }
    } catch (err) {
      console.error('Failed to copy:', err);
      // Fallback: try the old method
      try {
        const textArea = document.createElement('textarea');
        textArea.value = command;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        setCopiedIndex(index);
        setTimeout(() => setCopiedIndex(null), 2000);
      } catch (fallbackErr) {
        console.error('Fallback copy also failed:', fallbackErr);
        alert('Failed to copy. Please select and copy manually.');
      }
    }
  };

  const getServiceName = (url: string): string => {
    // Extract service name from URL
    const match = url.match(/^([^:]+):/);
    if (match) {
      return match[1].charAt(0).toUpperCase() + match[1].slice(1);
    }
    return 'Unknown Service';
  };

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  if (loading) {
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
            <div className="text-center py-16 text-gray-500">
              Loading Apprise configuration...
            </div>
          </main>
        </div>
      </div>
    );
  }

  if (!enabled) {
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
            <Alert color="warning" icon={HiInformationCircle}>
              <span className="font-medium">Apprise is not enabled.</span>
              <div className="mt-2 text-sm">
                To enable Apprise notifications, set <code className="px-1 py-0.5 bg-gray-200 dark:bg-gray-700 rounded">apprise.enable = true</code> in your <code className="px-1 py-0.5 bg-gray-200 dark:bg-gray-700 rounded">router-config.nix</code> file.
              </div>
            </Alert>
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
        
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50 dark:bg-gray-900">
          <div className="max-w-7xl mx-auto">
            <div className="flex items-center gap-3 mb-6">
              <HiBell className="w-8 h-8 text-gray-900 dark:text-white" />
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Apprise Notifications</h1>
            </div>

            {error && (
              <Alert color="failure" className="mb-6">
                {error}
              </Alert>
            )}

            {sendResult && (
              <Alert 
                color={sendResult.success ? "success" : "failure"} 
                icon={sendResult.success ? HiCheckCircle : HiXCircle}
                className="mb-6"
                onDismiss={() => setSendResult(null)}
              >
                {sendResult.message}
              </Alert>
            )}

            {/* How It Works Section */}
            <Card className="mb-6">
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">How It Works</h2>
              <div className="space-y-3 text-gray-700 dark:text-gray-300">
                <p>
                  Apprise is integrated into the NixOS Router WebUI backend, allowing you to send notifications
                  to multiple services configured in <code className="px-1 py-0.5 bg-gray-200 dark:bg-gray-700 rounded">router-config.nix</code>.
                </p>
                <p>
                  Notifications can be sent to all configured services simultaneously, or to individual services.
                </p>
                <p>
                  <strong>Notification Types:</strong>
                </p>
                <ul className="list-disc list-inside ml-4 space-y-1">
                  <li><strong>info</strong> - General information (default)</li>
                  <li><strong>success</strong> - Success messages</li>
                  <li><strong>warning</strong> - Warning messages</li>
                  <li><strong>failure</strong> - Error/failure messages</li>
                </ul>
              </div>
            </Card>

            {/* URL Generator Section */}
            <div className="mb-6">
              <AppriseUrlGenerator />
            </div>

            {/* Send Notification Section */}
            <Card className="mb-6">
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">Send Notification</h2>
              <div className="space-y-4">
                <div>
                  <Label htmlFor="title" value="Title (optional)" />
                  <TextInput
                    id="title"
                    type="text"
                    placeholder="Notification title"
                    value={notificationTitle}
                    onChange={(e) => setNotificationTitle(e.target.value)}
                    className="mt-1"
                  />
                </div>
                <div>
                  <Label htmlFor="body" value="Message Body *" />
                  <Textarea
                    id="body"
                    placeholder="Enter your notification message..."
                    value={notificationBody}
                    onChange={(e) => setNotificationBody(e.target.value)}
                    rows={4}
                    className="mt-1"
                    required
                  />
                </div>
                <div>
                  <Label htmlFor="type" value="Notification Type" />
                  <Select
                    id="type"
                    value={notificationType}
                    onChange={(e) => setNotificationType(e.target.value)}
                    className="mt-1"
                  >
                    <option value="info">Info</option>
                    <option value="success">Success</option>
                    <option value="warning">Warning</option>
                    <option value="failure">Failure</option>
                  </Select>
                </div>
                <Button
                  onClick={handleSendNotification}
                  disabled={sending || !notificationBody.trim()}
                  className="w-full sm:w-auto"
                >
                  {sending ? 'Sending...' : 'Send to All Services'}
                </Button>
              </div>
            </Card>

            {/* Configured Services Section */}
            <Card>
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
                Configured Services ({services.length})
              </h2>
              
              {services.length === 0 ? (
                <Alert color="info" icon={HiInformationCircle}>
                  No notification services are configured. Add services in <code className="px-1 py-0.5 bg-gray-200 dark:bg-gray-700 rounded">router-config.nix</code>.
                </Alert>
              ) : (
                <div className="space-y-4">
                  {services.map((service, index) => {
                    const isSending = sendingServices.has(index);
                    const sendResult = sendResults.get(index);
                    const sendError = sendErrors.get(index);
                    const isSendSuccess = sendResult?.success === true;
                    
                    return (
                      <Card key={index} className="bg-gray-50 dark:bg-gray-800">
                        <div className="flex items-start justify-between gap-4">
                          <div className="flex-1">
                            <div className="flex items-center gap-2 mb-2">
                              <Badge color="info">{service.description}</Badge>
                              {isSendSuccess && (
                                <HiCheckCircle className="w-5 h-5 text-blue-500" title="Notification sent" />
                              )}
                            </div>
                            <code className="text-sm text-gray-600 dark:text-gray-400 break-all">
                              {service.url}
                            </code>
                            {sendError && (
                              <Alert color="failure" className="mt-2">
                                <div className="text-sm">
                                  <strong>Send Error:</strong> {sendError}
                                </div>
                              </Alert>
                            )}
                            {sendResult?.success && sendResult.details && (
                              <Alert color="success" className="mt-2">
                                <div className="text-sm">{sendResult.details}</div>
                              </Alert>
                            )}
                          </div>
                          <div className="flex gap-2">
                            <div className="relative">
                              <Button
                                size="sm"
                                color={isSendSuccess ? "success" : "blue"}
                                onClick={() => handleSendToService(index)}
                                disabled={isSending || !notificationBody.trim()}
                              >
                                {isSending ? 'Sending...' : isSendSuccess ? 'Send Again' : 'Send'}
                              </Button>
                              {isSendSuccess && !isSending && (
                                <HiCheckCircle className="absolute -top-1 -right-1 w-5 h-5 text-blue-500 bg-white dark:bg-gray-800 rounded-full" />
                              )}
                            </div>
                          </div>
                        </div>
                        
                        <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
                          <Label value="Example cURL Command" className="mb-2 block" />
                          <div className="relative">
                            <pre className="bg-gray-900 text-gray-100 p-4 rounded-lg text-xs overflow-x-auto pr-20">
                              <code>{getCurlCommand(index)}</code>
                            </pre>
                            <Button
                              size="xs"
                              color={copiedIndex === index ? "success" : "light"}
                              className="absolute top-2 right-2"
                              onClick={(e) => {
                                e.preventDefault();
                                e.stopPropagation();
                                copyCurlCommand(index);
                              }}
                            >
                              {copiedIndex === index ? 'Copied!' : 'Copy'}
                            </Button>
                          </div>
                          <p className="text-xs text-gray-500 dark:text-gray-400 mt-2">
                            Replace the message body, title, and notification_type as needed.
                          </p>
                        </div>
                      </Card>
                    );
                  })}
                </div>
              )}
            </Card>
          </div>
        </main>
      </div>
    </div>
  );
}

