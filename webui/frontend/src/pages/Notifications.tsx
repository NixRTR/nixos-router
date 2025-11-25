import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Alert,
  Badge,
  Button,
  Card,
  Checkbox,
  Label,
  Modal,
  Select,
  Spinner,
  Table,
  TextInput,
  Textarea,
  ToggleSwitch,
} from 'flowbite-react';
import { HiCheckCircle, HiXCircle, HiInformationCircle, HiPencil, HiTrash } from 'react-icons/hi';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import type {
  NotificationRule,
  NotificationParameterMetadata,
  NotificationHistoryRecord,
  NotificationRuleCreate,
  ComparisonOperator,
  AppriseServiceInfo,
  AppriseService,
  AppriseServiceUpdate,
} from '../types/notifications';
import { AppriseUrlGenerator } from '../components/AppriseUrlGenerator';

interface NotificationRuleFormState {
  id?: number;
  name: string;
  enabled: boolean;
  parameter_type: string;
  parameter_config: Record<string, string>;
  threshold_info: string;
  threshold_warning: string;
  threshold_failure: string;
  comparison_operator: ComparisonOperator;
  duration_seconds: number;
  cooldown_seconds: number;
  apprise_service_indices: number[];
  message_template: string;
}

interface HistoryModalState {
  open: boolean;
  items: NotificationHistoryRecord[];
  ruleName: string;
}

const DEFAULT_TEMPLATE = '{{ parameter_name }} is {{ current_value }} ({{ current_level | upper }})';

const emptyForm: NotificationRuleFormState = {
  name: '',
  enabled: true,
  parameter_type: '',
  parameter_config: {},
  threshold_info: '',
  threshold_warning: '',
  threshold_failure: '',
  comparison_operator: 'gt',
  duration_seconds: 60,
  cooldown_seconds: 300,
  apprise_service_indices: [],
  message_template: DEFAULT_TEMPLATE,
};

export function Notifications() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const { connectionStatus } = useMetrics(token);
  const navigate = useNavigate();

  const [rules, setRules] = useState<NotificationRule[]>([]);
  const [parameters, setParameters] = useState<NotificationParameterMetadata[]>([]);
  const [services, setServices] = useState<AppriseServiceInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [formOpen, setFormOpen] = useState(false);
  const [historyState, setHistoryState] = useState<HistoryModalState>({
    open: false,
    items: [],
    ruleName: '',
  });
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [formState, setFormState] = useState<NotificationRuleFormState>(emptyForm);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<string | null>(null);
  
  // Apprise service management state
  const [appriseServices, setAppriseServices] = useState<AppriseServiceInfo[]>([]);
  const [appriseEnabled, setAppriseEnabled] = useState(false);
  const [urlGeneratorModalOpen, setUrlGeneratorModalOpen] = useState(false);
  
  // Apprise edit modal state
  const [editModalOpen, setEditModalOpen] = useState(false);
  const [editingService, setEditingService] = useState<AppriseService | null>(null);
  const [editName, setEditName] = useState('');
  const [editDescription, setEditDescription] = useState('');
  const [editUrl, setEditUrl] = useState('');
  const [editEnabled, setEditEnabled] = useState(true);
  const [savingService, setSavingService] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);
  
  // Apprise notification form state
  const [notificationBody, setNotificationBody] = useState('');
  const [notificationTitle, setNotificationTitle] = useState('');
  const [notificationType, setNotificationType] = useState('info');
  const [sending, setSending] = useState(false);
  const [sendResult, setSendResult] = useState<{ success: boolean; message: string } | null>(null);
  
  // Send notification state - track status per service
  const [sendingServices, setSendingServices] = useState<Set<number>>(new Set());
  const [sendResults, setSendResults] = useState<Map<number, { success: boolean; message: string; details?: string }>>(new Map());

  useEffect(() => {
    const bootstrap = async () => {
      try {
        setLoading(true);
        const [rulesData, paramsData, serviceData] = await Promise.all([
          apiClient.getNotificationRules(),
          apiClient.getNotificationParameters(),
          apiClient.getAppriseServices(),
        ]);
        setRules(rulesData);
        setParameters(paramsData);
        setServices(serviceData);
      } catch (err: any) {
        setError(err?.response?.data?.detail || err.message || 'Failed to load notifications');
      } finally {
        setLoading(false);
      }
    };

    bootstrap();
    fetchAppriseStatus();
  }, []);

  const fetchAppriseStatus = async () => {
    try {
      const status = await apiClient.getAppriseStatus();
      setAppriseEnabled(status.enabled);
      
      const serviceList = await apiClient.getAppriseServices();
      setAppriseServices(serviceList);
    } catch (err: any) {
      setAppriseEnabled(false);
    }
  };

  const selectedParameter = useMemo(
    () => parameters.find((param) => param.type === formState.parameter_type),
    [parameters, formState.parameter_type]
  );

  const openCreateModal = () => {
    setFormState(emptyForm);
    setFormError(null);
    setFormSuccess(null);
    setTestResult(null);
    setFormOpen(true);
  };

  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  const openEditModal = (rule: NotificationRule) => {
    setFormState({
      id: rule.id,
      name: rule.name,
      enabled: rule.enabled,
      parameter_type: rule.parameter_type,
      parameter_config: Object.fromEntries(
        Object.entries(rule.parameter_config || {}).map(([key, value]) => [key, String(value ?? '')])
      ),
      threshold_info: rule.threshold_info !== null && rule.threshold_info !== undefined ? String(rule.threshold_info) : '',
      threshold_warning:
        rule.threshold_warning !== null && rule.threshold_warning !== undefined
          ? String(rule.threshold_warning)
          : '',
      threshold_failure:
        rule.threshold_failure !== null && rule.threshold_failure !== undefined
          ? String(rule.threshold_failure)
          : '',
      comparison_operator: rule.comparison_operator,
      duration_seconds: rule.duration_seconds,
      cooldown_seconds: rule.cooldown_seconds,
      apprise_service_indices: [...(rule.apprise_service_indices || [])],
      message_template: rule.message_template || DEFAULT_TEMPLATE,
    });
    setFormError(null);
    setFormSuccess(null);
    setTestResult(null);
    setFormOpen(true);
  };

  const closeForm = () => {
    setFormOpen(false);
    setFormState(emptyForm);
    setFormError(null);
    setFormSuccess(null);
    setTestResult(null);
  };

  const handleInputChange = (field: keyof NotificationRuleFormState, value: string | number | boolean) => {
    setFormState((prev) => ({
      ...prev,
      [field]: value,
    }));
  };

  const handleConfigFieldChange = (name: string, value: string) => {
    setFormState((prev) => ({
      ...prev,
      parameter_config: {
        ...prev.parameter_config,
        [name]: value,
      },
    }));
  };

  const handleServiceToggle = (serviceId: number) => {
    setFormState((prev) => {
      const exists = prev.apprise_service_indices.includes(serviceId);
      const updated = exists
        ? prev.apprise_service_indices.filter((id) => id !== serviceId)
        : [...prev.apprise_service_indices, serviceId].sort((a, b) => a - b);
      return { ...prev, apprise_service_indices: updated };
    });
  };

  const toNumberOrUndefined = (value: string) => {
    if (value === '' || value === null || value === undefined) return undefined;
    const parsed = Number(value);
    return Number.isNaN(parsed) ? undefined : parsed;
  };

  const refreshRules = async () => {
    const data = await apiClient.getNotificationRules();
    setRules(data);
  };

  const handleSubmit = async () => {
    setFormError(null);
    setFormSuccess(null);

    if (!formState.parameter_type) {
      setFormError('Please select a parameter to monitor.');
      return;
    }

    const payload: NotificationRuleCreate = {
      name: formState.name,
      enabled: formState.enabled,
      parameter_type: formState.parameter_type,
      parameter_config: formState.parameter_config,
      threshold_info: toNumberOrUndefined(formState.threshold_info),
      threshold_warning: toNumberOrUndefined(formState.threshold_warning),
      threshold_failure: toNumberOrUndefined(formState.threshold_failure),
      comparison_operator: formState.comparison_operator,
      duration_seconds: formState.duration_seconds,
      cooldown_seconds: formState.cooldown_seconds,
      apprise_service_indices: formState.apprise_service_indices,
      message_template: formState.message_template || DEFAULT_TEMPLATE,
    };

    try {
      if (formState.id) {
        await apiClient.updateNotificationRule(formState.id, payload);
        setFormSuccess('Notification rule updated.');
      } else {
        await apiClient.createNotificationRule(payload);
        setFormSuccess('Notification rule created.');
      }
      await refreshRules();
      setTimeout(closeForm, 600);
    } catch (err: any) {
      setFormError(err?.response?.data?.detail || err.message || 'Failed to save notification rule');
    }
  };

  const handleToggleEnabled = async (rule: NotificationRule) => {
    await apiClient.updateNotificationRule(rule.id, { enabled: !rule.enabled });
    await refreshRules();
  };

  const handleDelete = async (rule: NotificationRule) => {
    if (!window.confirm(`Delete notification "${rule.name}"? This cannot be undone.`)) {
      return;
    }
    await apiClient.deleteNotificationRule(rule.id);
    await refreshRules();
  };

  const handleTest = async (rule: NotificationRule) => {
    setTestResult(null);
    try {
      const result = await apiClient.testNotificationRule(rule.id);
      if (result.success) {
        setTestResult(`Test sent (${result.level.toUpperCase()}): ${result.message}`);
      } else {
        setTestResult(result.error || 'Test failed to send');
      }
    } catch (err: any) {
      setTestResult(err?.response?.data?.detail || err.message || 'Test failed');
    }
  };

  const openHistory = async (rule: NotificationRule) => {
    try {
      const history = await apiClient.getNotificationHistory(rule.id);
      setHistoryState({
        open: true,
        items: history.items,
        ruleName: rule.name,
      });
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to load history');
    }
  };

  const formatTimestamp = (value?: string | null) => {
    if (!value) return '—';
    return new Date(value).toLocaleString();
  };

  // Apprise functions
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
      const result = await apiClient.sendAppriseNotificationToServiceById(
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

    setSavingService(true);
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
      setSavingService(false);
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

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="xl" />
      </div>
    );
  }

  return (
    <div className="flex h-screen">
      <Sidebar onLogout={handleLogout} isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <div className="flex flex-1 flex-col overflow-hidden">
        <Navbar
          hostname="nixos-router"
          username={username}
          connectionStatus={connectionStatus}
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
        />
        <main className="flex-1 overflow-y-auto bg-gray-50 p-6 dark:bg-gray-900">
          <div className="mx-auto flex max-w-7xl items-center justify-between pb-6">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-white">Notifications</h1>
              <p className="text-sm text-gray-500">
                Automatically send Apprise notifications when monitored metrics cross thresholds.
              </p>
            </div>
            <Button onClick={openCreateModal}>New Rule</Button>
          </div>

          {error && (
            <Alert color="failure" className="mb-4" onDismiss={() => setError(null)}>
              {error}
            </Alert>
          )}

          <Card className="mb-6">
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-xl font-semibold">Configured Rules</h2>
            </div>
            {rules.length === 0 ? (
              <p className="text-sm text-gray-500">No notifications configured yet. Click “New Rule” to begin.</p>
            ) : (
              <div className="overflow-x-auto">
                <Table>
                  <Table.Head>
                    <Table.HeadCell>Name</Table.HeadCell>
                    <Table.HeadCell>Parameter</Table.HeadCell>
                    <Table.HeadCell>Thresholds</Table.HeadCell>
                    <Table.HeadCell>Status</Table.HeadCell>
                    <Table.HeadCell>Last Notification</Table.HeadCell>
                    <Table.HeadCell>Actions</Table.HeadCell>
                  </Table.Head>
                  <Table.Body className="divide-y">
                    {rules.map((rule) => (
                      <Table.Row key={rule.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                        <Table.Cell>
                          <div className="font-semibold text-gray-900 dark:text-white">{rule.name}</div>
                          <div className="text-xs text-gray-500">#{rule.id}</div>
                        </Table.Cell>
                        <Table.Cell>
                          <div className="text-sm font-medium">{rule.parameter_type}</div>
                          <div className="text-xs text-gray-500">
                            Duration {rule.duration_seconds}s · Cooldown {rule.cooldown_seconds}s
                          </div>
                        </Table.Cell>
                        <Table.Cell>
                          <div className="text-xs text-gray-500">
                            <span className="font-semibold">Info:</span>{' '}
                            {rule.threshold_info ?? '—'} · <span className="font-semibold">Warn:</span>{' '}
                            {rule.threshold_warning ?? '—'} · <span className="font-semibold">Fail:</span>{' '}
                            {rule.threshold_failure ?? '—'}
                          </div>
                        </Table.Cell>
                        <Table.Cell>
                          <div className="flex items-center gap-2">
                            <Badge color={rule.enabled ? 'success' : 'gray'}>
                              {rule.enabled ? 'Enabled' : 'Disabled'}
                            </Badge>
                            {rule.current_level && (
                              <Badge color={rule.current_level === 'failure' ? 'failure' : 'warning'}>
                                {rule.current_level.toUpperCase()}
                              </Badge>
                            )}
                          </div>
                        </Table.Cell>
                        <Table.Cell>
                          <div className="text-xs text-gray-500">
                            {formatTimestamp(rule.last_notification_at)}
                          </div>
                          <div className="text-xs text-gray-400">{rule.last_notification_level ?? ''}</div>
                        </Table.Cell>
                        <Table.Cell>
                          <div className="flex flex-wrap gap-2">
                            <Button size="xs" onClick={() => openEditModal(rule)}>
                              Edit
                            </Button>
                            <Button size="xs" color="light" onClick={() => handleToggleEnabled(rule)}>
                              {rule.enabled ? 'Disable' : 'Enable'}
                            </Button>
                            <Button size="xs" color="purple" onClick={() => handleTest(rule)}>
                              Test
                            </Button>
                            <Button size="xs" color="info" onClick={() => openHistory(rule)}>
                              History
                            </Button>
                            <Button size="xs" color="failure" onClick={() => handleDelete(rule)}>
                              Delete
                            </Button>
                          </div>
                        </Table.Cell>
                      </Table.Row>
                    ))}
                  </Table.Body>
                </Table>
              </div>
            )}
          </Card>

          {/* Apprise Service Management Sections */}
          {appriseEnabled && (
            <>
              {/* Configured Services Section */}
              <Card className="mb-6">
                <div className="flex items-center justify-between mb-4">
                  <h2 className="text-xl font-semibold text-gray-900 dark:text-white">
                    Configured Services ({appriseServices.length})
                  </h2>
                  <Button
                    color="blue"
                    onClick={() => setUrlGeneratorModalOpen(true)}
                  >
                    New Service
                  </Button>
                </div>
                
                {sendResult && (
                  <Alert 
                    color={sendResult.success ? "success" : "failure"} 
                    icon={sendResult.success ? HiCheckCircle : HiXCircle}
                    className="mb-4"
                    onDismiss={() => setSendResult(null)}
                  >
                    {sendResult.message}
                  </Alert>
                )}
                
                {appriseServices.length === 0 ? (
                  <Alert color="info" icon={HiInformationCircle}>
                    No notification services are configured. Use the "New Service" button to create a service.
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
                      {appriseServices.map((service) => {
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

              {/* Send Notification Section */}
              <Card className="mb-6">
                <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">Send Notification</h2>
                <div className="space-y-4">
                  <div>
                    <Label htmlFor="apprise-title" value="Title (optional)" />
                    <TextInput
                      id="apprise-title"
                      type="text"
                      placeholder="Notification title"
                      value={notificationTitle}
                      onChange={(e) => setNotificationTitle(e.target.value)}
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="apprise-body" value="Message Body *" />
                    <Textarea
                      id="apprise-body"
                      placeholder="Enter your notification message..."
                      value={notificationBody}
                      onChange={(e) => setNotificationBody(e.target.value)}
                      rows={4}
                      className="mt-1"
                      required
                    />
                  </div>
                  <div>
                    <Label htmlFor="apprise-type" value="Notification Type" />
                    <Select
                      id="apprise-type"
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

              {/* How It Works Section */}
              <Card>
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
            </>
          )}
        </main>
      </div>

      <Modal show={formOpen} size="4xl" onClose={closeForm}>
        <Modal.Header>{formState.id ? 'Edit Notification Rule' : 'Create Notification Rule'}</Modal.Header>
        <Modal.Body>
          <div className="space-y-4">
            {formError && (
              <Alert color="failure" onDismiss={() => setFormError(null)}>
                {formError}
              </Alert>
            )}
            {formSuccess && (
              <Alert color="success" onDismiss={() => setFormSuccess(null)}>
                {formSuccess}
              </Alert>
            )}
            {testResult && (
              <Alert color="info" onDismiss={() => setTestResult(null)}>
                {testResult}
              </Alert>
            )}
            <div className="grid gap-4 md:grid-cols-2">
              <div>
                <Label htmlFor="name" value="Name" />
                <TextInput
                  id="name"
                  value={formState.name}
                  onChange={(e) => handleInputChange('name', e.target.value)}
                  placeholder="CPU usage alerts"
                />
              </div>
              <div className="flex items-end justify-between">
                <div>
                  <Label value="Enabled" />
                  <ToggleSwitch
                    checked={formState.enabled}
                    onChange={(checked) => handleInputChange('enabled', checked)}
                  />
                </div>
                <div>
                  <Label value="Comparison" />
                  <Select
                    value={formState.comparison_operator}
                    onChange={(e) => handleInputChange('comparison_operator', e.target.value as ComparisonOperator)}
                  >
                    <option value="gt">Greater than (&gt;=)</option>
                    <option value="lt">Less than (&lt;=)</option>
                  </Select>
                </div>
              </div>
            </div>

            <div>
              <Label htmlFor="parameter" value="Parameter" />
              <Select
                id="parameter"
                value={formState.parameter_type}
                onChange={(e) =>
                  setFormState((prev) => ({
                    ...prev,
                    parameter_type: e.target.value,
                    parameter_config: {},
                  }))
                }
              >
                <option value="">Select parameter</option>
                {parameters.map((param) => (
                  <option key={param.type} value={param.type}>
                    {param.label}
                  </option>
                ))}
              </Select>
              {selectedParameter?.description && (
                <p className="text-xs text-gray-500">{selectedParameter.description}</p>
              )}
            </div>

            {selectedParameter?.requires_config && (
              <Card>
                <h3 className="mb-2 text-sm font-semibold">Parameter Settings</h3>
                <div className="grid gap-4 md:grid-cols-2">
                  {selectedParameter.config_fields.map((field) => (
                    <div key={field.name}>
                      <Label htmlFor={`config-${field.name}`} value={field.label} />
                      {field.field_type === 'select' && field.options ? (
                        <Select
                          id={`config-${field.name}`}
                          value={formState.parameter_config[field.name] || ''}
                          onChange={(e) => handleConfigFieldChange(field.name, e.target.value)}
                        >
                          <option value="">Select...</option>
                          {field.options.map((option) => (
                            <option key={option.value} value={option.value}>
                              {option.label}
                            </option>
                          ))}
                        </Select>
                      ) : (
                        <TextInput
                          id={`config-${field.name}`}
                          value={formState.parameter_config[field.name] || ''}
                          onChange={(e) => handleConfigFieldChange(field.name, e.target.value)}
                          placeholder={field.description}
                        />
                      )}
                      {field.description && <p className="text-xs text-gray-500">{field.description}</p>}
                    </div>
                  ))}
                </div>
              </Card>
            )}

            <Card>
              <h3 className="mb-2 text-sm font-semibold">Thresholds</h3>
              <div className="grid gap-4 md:grid-cols-3">
                <div>
                  <Label value="Info threshold" />
                  <TextInput
                    value={formState.threshold_info}
                    onChange={(e) => handleInputChange('threshold_info', e.target.value)}
                    placeholder="Optional"
                  />
                </div>
                <div>
                  <Label value="Warning threshold" />
                  <TextInput
                    value={formState.threshold_warning}
                    onChange={(e) => handleInputChange('threshold_warning', e.target.value)}
                    placeholder="Optional"
                  />
                </div>
                <div>
                  <Label value="Failure threshold" />
                  <TextInput
                    value={formState.threshold_failure}
                    onChange={(e) => handleInputChange('threshold_failure', e.target.value)}
                    placeholder="Optional"
                  />
                </div>
              </div>
              <div className="mt-4 grid gap-4 md:grid-cols-2">
                <div>
                  <Label value="Duration (seconds)" />
                  <TextInput
                    type="number"
                    min={5}
                    value={formState.duration_seconds}
                    onChange={(e) => handleInputChange('duration_seconds', Number(e.target.value))}
                  />
                </div>
                <div>
                  <Label value="Cooldown (seconds)" />
                  <TextInput
                    type="number"
                    min={0}
                    value={formState.cooldown_seconds}
                    onChange={(e) => handleInputChange('cooldown_seconds', Number(e.target.value))}
                  />
                </div>
              </div>
            </Card>

            <Card>
              <h3 className="mb-2 text-sm font-semibold">Apprise Services</h3>
              {services.length === 0 ? (
                <p className="text-xs text-gray-500">No Apprise services configured.</p>
              ) : (
                <div className="grid gap-2 md:grid-cols-2">
                  {services.map((service) => (
                    <label key={service.id} className="flex items-center gap-2 text-sm text-gray-700 dark:text-gray-200">
                      <Checkbox
                        checked={formState.apprise_service_indices.includes(service.id)}
                        onChange={() => handleServiceToggle(service.id)}
                      />
                      <span>
                        <span className="font-semibold">{service.name}</span>
                        {service.description && (
                          <span className="ml-2 text-xs text-gray-500">{service.description}</span>
                        )}
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </Card>

            <div>
              <Label htmlFor="messageTemplate" value="Message Template" />
              <Textarea
                id="messageTemplate"
                rows={4}
                value={formState.message_template}
                onChange={(e) => handleInputChange('message_template', e.target.value)}
              />
              <div className="mt-2 text-xs text-gray-500">
                Available variables:{' '}
                {(selectedParameter?.variables || []).map((variable) => (
                  <Badge key={variable} color="info" className="mr-1">
                    {variable}
                  </Badge>
                ))}
              </div>
            </div>
          </div>
        </Modal.Body>
        <Modal.Footer>
          <Button onClick={handleSubmit}>{formState.id ? 'Save Changes' : 'Create Rule'}</Button>
          <Button color="light" onClick={closeForm}>
            Cancel
          </Button>
        </Modal.Footer>
      </Modal>

      <Modal show={historyState.open} onClose={() => setHistoryState({ open: false, items: [], ruleName: '' })}>
        <Modal.Header>Notification History · {historyState.ruleName}</Modal.Header>
        <Modal.Body>
          {historyState.items.length === 0 ? (
            <p className="text-sm text-gray-500">No history recorded.</p>
          ) : (
            <div className="space-y-3">
              {historyState.items.map((item) => (
                <Card key={item.id}>
                  <div className="flex items-center justify-between">
                    <div>
                      <div className="text-sm font-semibold">{formatTimestamp(item.timestamp)}</div>
                      <div className="text-xs text-gray-500">Value: {item.value}</div>
                    </div>
                    <Badge color={item.sent_successfully ? 'success' : 'failure'}>{item.level.toUpperCase()}</Badge>
                  </div>
                  {item.message && <p className="mt-2 text-sm text-gray-600">{item.message}</p>}
                </Card>
              ))}
            </div>
          )}
        </Modal.Body>
        <Modal.Footer>
          <Button color="light" onClick={() => setHistoryState({ open: false, items: [], ruleName: '' })}>
            Close
          </Button>
        </Modal.Footer>
      </Modal>

      {/* URL Generator Modal */}
      <Modal show={urlGeneratorModalOpen} onClose={() => setUrlGeneratorModalOpen(false)} size="6xl">
        <Modal.Header>Create New Apprise Service</Modal.Header>
        <Modal.Body>
          <div className="max-h-[70vh] overflow-y-auto">
            <AppriseUrlGenerator 
              onServiceSaved={() => {
                setUrlGeneratorModalOpen(false);
                fetchAppriseStatus();
              }}
            />
          </div>
        </Modal.Body>
      </Modal>

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
              <TextInput
                id="editDescription"
                value={editDescription}
                onChange={(e) => setEditDescription(e.target.value)}
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
            disabled={savingService || !editName.trim() || !editUrl.trim()}
          >
            {savingService ? 'Saving...' : 'Save'}
          </Button>
          <Button color="gray" onClick={() => setEditModalOpen(false)}>
            Cancel
          </Button>
        </Modal.Footer>
      </Modal>
    </div>
  );
}

