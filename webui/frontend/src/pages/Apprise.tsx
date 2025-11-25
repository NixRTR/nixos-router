/**
 * Apprise Notifications Page
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Button, TextInput, Label, Textarea, Select, Badge, Alert, Modal, Table } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { HiBell, HiCheckCircle, HiXCircle, HiInformationCircle, HiPencil, HiTrash } from 'react-icons/hi';
import { AppriseUrlGenerator } from '../components/AppriseUrlGenerator';
import type { AppriseServiceInfo, AppriseService, AppriseServiceUpdate } from '../types/notifications';

export function Apprise() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [enabled, setEnabled] = useState(false);
  const [services, setServices] = useState<AppriseServiceInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Edit modal state
  const [editModalOpen, setEditModalOpen] = useState(false);
  const [editingService, setEditingService] = useState<AppriseService | null>(null);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [editUrl, setEditUrl] = useState('');
  const [editEnabled, setEditEnabled] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);
  
  // Notification form state
  const [notificationBody, setNotificationBody] = useState('');
  const [notificationTitle, setNotificationTitle] = useState('');
  const [notificationType, setNotificationType] = useState('info');
  const [sending, setSending] = useState(false);
  const [sendResult, setSendResult] = useState<{ success: boolean; message: string } | null>(null);
  
  // Send notification state - track status per service index
  const [sendingServices, setSendingServices] = useState<Set<number>>(new Set());
  const [sendResults, setSendResults] = useState<Map<number, { success: boolean; message: string; details?: string }>>(new Map());
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    fetchAppriseStatus();
  }, []);

  const fetchAppriseStatus = async () => {
    setLoading(true);
    setError(null);
    try {
      const status = await apiClient.getAppriseStatus();
      setEnabled(status.enabled);
      
      const serviceList = await apiClient.getAppriseServices();
      setServices(serviceList);
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

  const handleSendToService = async (serviceId: number) => {
    if (!notificationBody.trim()) {
      setSendResults(prev => new Map(prev).set(serviceId, { success: false, message: 'Message body is required' }));
      return;
    }

    setSendingServices(prev => new Set(prev).add(serviceId));
    setSendResults(prev => {
      const newMap = new Map(prev);
      newMap.delete(serviceId);
      return newMap;
    });
    
    try {
      const result = await apiClient.sendAppriseNotificationToService(
        serviceId,
        notificationBody,
        notificationTitle || undefined,
        notificationType || undefined
      );
      setSendResults(prev => new Map(prev).set(serviceId, result));
      
      if (!result.success) {
        const errorMsg = result.details 
          ? `${result.message}: ${result.details}`
          : result.message;
        setSendResults(prev => new Map(prev).set(serviceId, { success: false, message: errorMsg, details: result.details }));
      }
    } catch (err: any) {
      const errorMsg = err.response?.data?.detail || err.message || 'Failed to send notification';
      setSendResults(prev => new Map(prev).set(serviceId, {
        success: false,
        message: errorMsg,
      }));
    } finally {
      setSendingServices(prev => {
        const newSet = new Set(prev);
        newSet.delete(serviceId);
        return newSet;
      });
    }
  };

  const handleTestService = async (serviceId: number) => {
    setSendingServices(prev => new Set(prev).add(serviceId));
    try {
      const result = await apiClient.testAppriseServiceById(serviceId);
      setSendResults(prev => new Map(prev).set(serviceId, result));
      if (!result.success) {
        setSendResults(prev => new Map(prev).set(serviceId, { success: false, message: result.message, details: result.details }));
      }
    } catch (err: any) {
      setSendResults(prev => new Map(prev).set(serviceId, { success: false, message: err.response?.data?.detail || err.message }));
    } finally {
      setSendingServices(prev => {
        const newSet = new Set(prev);
        newSet.delete(serviceId);
        return newSet;
      });
    }
  };

  const handleEditService = async (serviceId: number) => {
    try {
      const service = await apiClient.getAppriseService(serviceId);
      setEditingService(service);
      setEditName(service.name);
      setEditDescription(service.description || '');
      setEditUrl(service.url);
      setEditEnabled(service.enabled);
      setEditError(null);
      setEditModalOpen(true);
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to load service');
    }
  };

  const handleSaveEdit = async () => {
    if (!editingService) return;
    if (!editName.trim()) {
      setEditError('Service name is required');
      return;
    }

    setSaving(true);
    setEditError(null);
    try {
      const update: AppriseServiceUpdate = {
        name: editName.trim(),
        description: editDescription.trim() || null,
        url: editUrl.trim(),
        enabled: editEnabled,
      };
      await apiClient.updateAppriseService(editingService.id, update);
      setEditModalOpen(false);
      await fetchAppriseStatus();
    } catch (err: any) {
      setEditError(err.response?.data?.detail || err.message || 'Failed to update service');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteService = async (serviceId: number) => {
    if (!confirm('Are you sure you want to delete this service? This action cannot be undone.')) {
      return;
    }
    try {
      await apiClient.deleteAppriseService(serviceId);
      await fetchAppriseStatus();
    } catch (err: any) {
      setError(err.response?.data?.detail || err.message || 'Failed to delete service');
    }
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
                  No notification services are configured. Use the URL Generator below to create a service.
                </Alert>
              ) : (
                <Table>
                  <Table.Head>
                    <Table.HeadCell>Name</Table.HeadCell>
                    <Table.HeadCell>Description</Table.HeadCell>
                    <Table.HeadCell>Status</Table.HeadCell>
                    <Table.HeadCell>Actions</Table.HeadCell>
                  </Table.Head>
                  <Table.Body className="divide-y">
                    {services.map((service) => {
                      const isSending = sendingServices.has(service.id);
                      const sendResult = sendResults.get(service.id);
                      
                      return (
                        <Table.Row key={service.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                          <Table.Cell className="whitespace-nowrap font-medium text-gray-900 dark:text-white">
                            {service.name}
                          </Table.Cell>
                          <Table.Cell className="text-gray-500 dark:text-gray-400">
                            {service.description || '-'}
                          </Table.Cell>
                          <Table.Cell>
                            <Badge color={service.enabled ? "success" : "gray"}>
                              {service.enabled ? "Enabled" : "Disabled"}
                            </Badge>
                          </Table.Cell>
                          <Table.Cell>
                            <div className="flex gap-2">
                              <Button
                                size="xs"
                                color="blue"
                                onClick={() => handleSendToService(service.id)}
                                disabled={isSending || !notificationBody.trim() || !service.enabled}
                              >
                                {isSending ? 'Sending...' : sendResult?.success ? 'Send Again' : 'Send'}
                              </Button>
                              <Button
                                size="xs"
                                color="gray"
                                onClick={() => handleTestService(service.id)}
                                disabled={!service.enabled}
                              >
                                Test
                              </Button>
                              <Button
                                size="xs"
                                color="gray"
                                onClick={() => handleEditService(service.id)}
                              >
                                <HiPencil className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="failure"
                                onClick={() => handleDeleteService(service.id)}
                                disabled={!service.enabled}
                              >
                                <HiTrash className="w-4 h-4" />
                              </Button>
                            </div>
                          </Table.Cell>
                        </Table.Row>
                      );
                    })}
                  </Table.Body>
                </Table>
              )}
            </Card>

            {/* Edit Service Modal */}
            <Modal show={editModalOpen} onClose={() => setEditModalOpen(false)} size="lg">
              <Modal.Header>Edit Apprise Service</Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {editError && (
                    <Alert color="failure">
                      {editError}
                    </Alert>
                  )}
                  <div>
                    <Label htmlFor="editName" value="Service Name *" />
                    <TextInput
                      id="editName"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="editDescription" value="Description (optional)" />
                    <Textarea
                      id="editDescription"
                      value={editDescription}
                      onChange={(e) => setEditDescription(e.target.value)}
                      rows={3}
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="editUrl" value="Service URL *" />
                    <TextInput
                      id="editUrl"
                      value={editUrl}
                      onChange={(e) => setEditUrl(e.target.value)}
                      required
                      className="mt-1 font-mono text-sm"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="editEnabled"
                      checked={editEnabled}
                      onChange={(e) => setEditEnabled(e.target.checked)}
                      className="w-4 h-4"
                    />
                    <Label htmlFor="editEnabled" value="Enabled" />
                  </div>
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button
                  color="blue"
                  onClick={handleSaveEdit}
                  disabled={saving || !editName.trim() || !editUrl.trim()}
                >
                  {saving ? 'Saving...' : 'Save'}
                </Button>
                <Button color="gray" onClick={() => setEditModalOpen(false)}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>
          </div>
        </main>
      </div>
    </div>
  );
}

