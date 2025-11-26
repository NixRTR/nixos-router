/**
 * DNS Management Page
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Button, TextInput, Label, Select, Badge, Alert, Modal, Table } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { HiGlobe, HiPencil, HiTrash, HiPlus, HiInformationCircle, HiPlay, HiStop, HiRefresh } from 'react-icons/hi';
import type { DnsZone, DnsZoneCreate, DnsZoneUpdate, DnsRecord, DnsRecordCreate, DnsRecordUpdate } from '../types/dns';

export function Dns() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [zones, setZones] = useState<DnsZone[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [networkFilter, setNetworkFilter] = useState<'all' | 'homelab' | 'lan'>('all');
  const [serviceStatuses, setServiceStatuses] = useState<Record<string, { is_active: boolean; is_enabled: boolean; exists: boolean }>>({});
  const [controllingService, setControllingService] = useState<string | null>(null);
  
  // Zone modal state
  const [zoneModalOpen, setZoneModalOpen] = useState(false);
  const [editingZone, setEditingZone] = useState<DnsZone | null>(null);
  const [zoneName, setZoneName] = useState('');
  const [zoneNetwork, setZoneNetwork] = useState<'homelab' | 'lan'>('homelab');
  const [zoneAuthoritative, setZoneAuthoritative] = useState(true);
  const [zoneForwardTo, setZoneForwardTo] = useState('');
  const [zoneDelegateTo, setZoneDelegateTo] = useState('');
  const [zoneEnabled, setZoneEnabled] = useState(true);
  const [saving, setSaving] = useState(false);
  const [zoneError, setZoneError] = useState<string | null>(null);
  
  // Record modal state
  const [recordsViewModalOpen, setRecordsViewModalOpen] = useState(false);
  const [recordEditModalOpen, setRecordEditModalOpen] = useState(false);
  const [selectedZone, setSelectedZone] = useState<DnsZone | null>(null);
  const [records, setRecords] = useState<DnsRecord[]>([]);
  const [editingRecord, setEditingRecord] = useState<DnsRecord | null>(null);
  const [recordName, setRecordName] = useState('');
  const [recordType, setRecordType] = useState<'A' | 'CNAME'>('A');
  const [recordValue, setRecordValue] = useState('');
  const [recordComment, setRecordComment] = useState('');
  const [recordEnabled, setRecordEnabled] = useState(true);
  const [recordError, setRecordError] = useState<string | null>(null);
  
  // Delete confirmation
  const [deleteZoneModalOpen, setDeleteZoneModalOpen] = useState(false);
  const [deleteRecordModalOpen, setDeleteRecordModalOpen] = useState(false);
  const [zoneToDelete, setZoneToDelete] = useState<DnsZone | null>(null);
  const [recordToDelete, setRecordToDelete] = useState<DnsRecord | null>(null);
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    if (!token) {
      navigate('/login');
      return;
    }
    fetchZones();
    fetchServiceStatuses();
  }, [token, networkFilter]);

  const fetchZones = async () => {
    setLoading(true);
    setError(null);
    try {
      const network = networkFilter === 'all' ? undefined : networkFilter;
      const data = await apiClient.getDnsZones(network);
      setZones(data);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to load DNS zones');
    } finally {
      setLoading(false);
    }
  };

  const fetchServiceStatuses = async () => {
    try {
      const [homelabStatus, lanStatus] = await Promise.all([
        apiClient.getDnsServiceStatus('homelab'),
        apiClient.getDnsServiceStatus('lan'),
      ]);
      setServiceStatuses({
        homelab: homelabStatus,
        lan: lanStatus,
      });
    } catch (err: any) {
      console.error('Failed to fetch DNS service statuses:', err);
    }
  };

  const handleServiceControl = async (network: 'homelab' | 'lan', action: 'start' | 'stop' | 'restart' | 'reload') => {
    const serviceKey = `${network}-${action}`;
    setControllingService(serviceKey);
    try {
      await apiClient.controlDnsService(network, action);
      // Refresh service status after a short delay
      setTimeout(() => {
        fetchServiceStatuses();
      }, 1000);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || `Failed to ${action} DNS service`);
    } finally {
      setControllingService(null);
    }
  };

  const getServiceStatusForZone = (zone: DnsZone) => {
    const status = serviceStatuses[zone.network];
    if (!status || !status.exists) {
      return { is_active: false, is_enabled: false };
    }
    return { is_active: status.is_active, is_enabled: status.is_enabled };
  };

  const fetchRecords = async (zoneId: number) => {
    try {
      const data = await apiClient.getDnsRecords(zoneId);
      setRecords(data);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to load DNS records');
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('access_token');
    localStorage.removeItem('username');
    navigate('/login');
  };

  const openZoneModal = (zone?: DnsZone) => {
    if (zone) {
      setEditingZone(zone);
      setZoneName(zone.name);
      setZoneNetwork(zone.network);
      setZoneAuthoritative(zone.authoritative);
      setZoneForwardTo(zone.forward_to || '');
      setZoneDelegateTo(zone.delegate_to || '');
      setZoneEnabled(zone.enabled);
    } else {
      setEditingZone(null);
      setZoneName('');
      setZoneNetwork('homelab');
      setZoneAuthoritative(true);
      setZoneForwardTo('');
      setZoneDelegateTo('');
      setZoneEnabled(true);
    }
    setZoneError(null);
    setZoneModalOpen(true);
  };

  const closeZoneModal = () => {
    setZoneModalOpen(false);
    setEditingZone(null);
    setZoneError(null);
  };

  const handleSaveZone = async () => {
    setZoneError(null);
    setSaving(true);
    
    try {
      if (!zoneName.trim()) {
        setZoneError('Zone name is required');
        setSaving(false);
        return;
      }
      
      if (editingZone) {
        const update: DnsZoneUpdate = {
          name: zoneName.trim(),
          network: zoneNetwork,
          authoritative: zoneAuthoritative,
          forward_to: zoneForwardTo.trim() || null,
          delegate_to: zoneDelegateTo.trim() || null,
          enabled: zoneEnabled,
        };
        await apiClient.updateDnsZone(editingZone.id, update);
      } else {
        const create: DnsZoneCreate = {
          name: zoneName.trim(),
          network: zoneNetwork,
          authoritative: zoneAuthoritative,
          forward_to: zoneForwardTo.trim() || null,
          delegate_to: zoneDelegateTo.trim() || null,
          enabled: zoneEnabled,
        };
        await apiClient.createDnsZone(create);
      }
      
      await fetchZones();
      closeZoneModal();
    } catch (err: any) {
      setZoneError(err?.response?.data?.detail || err.message || 'Failed to save zone');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteZone = async () => {
    if (!zoneToDelete) return;
    
    try {
      await apiClient.deleteDnsZone(zoneToDelete.id);
      await fetchZones();
      setDeleteZoneModalOpen(false);
      setZoneToDelete(null);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to delete zone');
    }
  };

  const openRecordsView = async (zone: DnsZone) => {
    setSelectedZone(zone);
    await fetchRecords(zone.id);
    setRecordsViewModalOpen(true);
  };

  const openRecordEditModal = (zone: DnsZone, record?: DnsRecord) => {
    setSelectedZone(zone);
    if (record) {
      setEditingRecord(record);
      setRecordName(record.name);
      setRecordType(record.type);
      setRecordValue(record.value);
      setRecordComment(record.comment || '');
      setRecordEnabled(record.enabled);
    } else {
      setEditingRecord(null);
      setRecordName('');
      setRecordType('A');
      setRecordValue('');
      setRecordComment('');
      setRecordEnabled(true);
    }
    setRecordError(null);
    setRecordEditModalOpen(true);
  };

  const closeRecordsView = () => {
    setRecordsViewModalOpen(false);
    setSelectedZone(null);
    setRecords([]);
  };

  const closeRecordEditModal = () => {
    setRecordEditModalOpen(false);
    setEditingRecord(null);
    setRecordError(null);
    if (selectedZone) {
      fetchRecords(selectedZone.id);
    }
  };

  const handleSaveRecord = async () => {
    if (!selectedZone) return;
    
    setRecordError(null);
    setSaving(true);
    
    try {
      if (!recordName.trim()) {
        setRecordError('Record name is required');
        setSaving(false);
        return;
      }
      
      if (!recordValue.trim()) {
        setRecordError('Record value is required');
        setSaving(false);
        return;
      }
      
      if (editingRecord) {
        const update: DnsRecordUpdate = {
          name: recordName.trim(),
          type: recordType,
          value: recordValue.trim(),
          comment: recordComment.trim() || null,
          enabled: recordEnabled,
        };
        await apiClient.updateDnsRecord(editingRecord.id, update);
      } else {
        const create: DnsRecordCreate = {
          zone_id: selectedZone.id,
          name: recordName.trim(),
          type: recordType,
          value: recordValue.trim(),
          comment: recordComment.trim() || null,
          enabled: recordEnabled,
        };
        await apiClient.createDnsRecord(selectedZone.id, create);
      }
      
      await fetchRecords(selectedZone.id);
      closeRecordEditModal();
    } catch (err: any) {
      setRecordError(err?.response?.data?.detail || err.message || 'Failed to save record');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteRecord = async () => {
    if (!recordToDelete) return;
    
    try {
      await apiClient.deleteDnsRecord(recordToDelete.id);
      if (selectedZone) {
        await fetchRecords(selectedZone.id);
      }
      setDeleteRecordModalOpen(false);
      setRecordToDelete(null);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to delete record');
    }
  };


  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600 dark:text-gray-400">Loading DNS zones...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-screen">
      <Sidebar onLogout={handleLogout} isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Navbar
          hostname="nixos-router"
          username={username}
          connectionStatus={connectionStatus}
          onMenuClick={() => setSidebarOpen(!sidebarOpen)}
        />
        
        <main className="flex-1 overflow-y-auto p-6 bg-gray-50 dark:bg-gray-900">
          <div className="max-w-7xl mx-auto">
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-3">
                <HiGlobe className="w-8 h-8 text-gray-900 dark:text-white" />
                <h1 className="text-3xl font-bold text-gray-900 dark:text-white">DNS Management</h1>
              </div>
              <Button
                color="blue"
                onClick={() => openZoneModal()}
              >
                New Zone
              </Button>
            </div>

            {error && (
              <Alert color="failure" className="mb-6" onDismiss={() => setError(null)}>
                {error}
              </Alert>
            )}

            {/* Network Filter */}
            <div className="mb-4">
              <Label htmlFor="networkFilter" value="Filter by Network" />
              <Select
                id="networkFilter"
                value={networkFilter}
                onChange={(e) => setNetworkFilter(e.target.value as 'all' | 'homelab' | 'lan')}
                className="mt-1 w-48"
              >
                <option value="all">All Networks</option>
                <option value="homelab">HOMELAB</option>
                <option value="lan">LAN</option>
              </Select>
            </div>

            {/* Zones Cards */}
            <Card>
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
                DNS Zones ({zones.length})
              </h2>
              
              {zones.length === 0 ? (
                <Alert color="info" icon={HiInformationCircle}>
                  No DNS zones configured. Create a zone to get started.
                </Alert>
              ) : (
                <>
                  {/* Desktop Table View */}
                  <div className="hidden md:block overflow-x-auto">
                    <Table>
                      <Table.Head>
                        <Table.HeadCell>Name</Table.HeadCell>
                        <Table.HeadCell>Network</Table.HeadCell>
                        <Table.HeadCell>Authoritative</Table.HeadCell>
                        <Table.HeadCell>Forward To</Table.HeadCell>
                        <Table.HeadCell>Delegate To</Table.HeadCell>
                        <Table.HeadCell>Status</Table.HeadCell>
                        <Table.HeadCell>Actions</Table.HeadCell>
                      </Table.Head>
                      <Table.Body className="divide-y">
                        {zones.map((zone) => (
                          <Table.Row key={zone.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                            <Table.Cell className="whitespace-nowrap font-medium text-gray-900 dark:text-white">
                              {zone.name}
                            </Table.Cell>
                            <Table.Cell>
                              <Badge color="blue">{zone.network}</Badge>
                            </Table.Cell>
                            <Table.Cell>
                              <Badge color={zone.authoritative ? "success" : "gray"}>
                                {zone.authoritative ? "Yes" : "No"}
                              </Badge>
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {zone.forward_to || '-'}
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {zone.delegate_to || '-'}
                            </Table.Cell>
                            <Table.Cell>
                              {(() => {
                                const serviceStatus = getServiceStatusForZone(zone);
                                return (
                                  <Badge color={serviceStatus.is_active ? "success" : "gray"}>
                                    {serviceStatus.is_active ? "Running" : serviceStatus.is_enabled ? "Stopped" : "Disabled"}
                                  </Badge>
                                );
                              })()}
                            </Table.Cell>
                            <Table.Cell>
                              <div className="flex gap-2 flex-wrap">
                                <Button
                                  size="xs"
                                  color="blue"
                                  onClick={() => openRecordsView(zone)}
                                >
                                  Records
                                </Button>
                                <Button
                                  size="xs"
                                  color="gray"
                                  onClick={() => openZoneModal(zone)}
                                >
                                  <HiPencil className="w-4 h-4" />
                                </Button>
                                {(() => {
                                  const serviceStatus = getServiceStatusForZone(zone);
                                  const serviceKey = `${zone.network}-`;
                                  const isControlling = controllingService?.startsWith(serviceKey);
                                  return (
                                    <>
                                      <Button
                                        size="xs"
                                        color="success"
                                        onClick={() => handleServiceControl(zone.network, 'start')}
                                        disabled={isControlling || serviceStatus.is_active}
                                        title="Start Service"
                                      >
                                        <HiPlay className="w-4 h-4" />
                                      </Button>
                                      <Button
                                        size="xs"
                                        color="failure"
                                        onClick={() => handleServiceControl(zone.network, 'stop')}
                                        disabled={isControlling || !serviceStatus.is_active}
                                        title="Stop Service"
                                      >
                                        <HiStop className="w-4 h-4" />
                                      </Button>
                                      <Button
                                        size="xs"
                                        color="warning"
                                        onClick={() => handleServiceControl(zone.network, 'reload')}
                                        disabled={isControlling || !serviceStatus.is_active}
                                        title="Reload Service"
                                      >
                                        <HiRefresh className="w-4 h-4" />
                                      </Button>
                                      <Button
                                        size="xs"
                                        color="purple"
                                        onClick={() => handleServiceControl(zone.network, 'restart')}
                                        disabled={isControlling}
                                        title="Restart Service"
                                      >
                                        <HiRefresh className="w-4 h-4" />
                                      </Button>
                                    </>
                                  );
                                })()}
                                <Button
                                  size="xs"
                                  color="failure"
                                  onClick={() => {
                                    setZoneToDelete(zone);
                                    setDeleteZoneModalOpen(true);
                                  }}
                                >
                                  <HiTrash className="w-4 h-4" />
                                </Button>
                              </div>
                            </Table.Cell>
                          </Table.Row>
                        ))}
                      </Table.Body>
                    </Table>
                  </div>

                  {/* Mobile/Tablet Card View */}
                  <div className="md:hidden space-y-3">
                    {zones.map((zone) => {
                      const serviceStatus = getServiceStatusForZone(zone);
                      const serviceKey = `${zone.network}-`;
                      const isControlling = controllingService?.startsWith(serviceKey);
                      return (
                        <div
                          key={zone.id}
                          className="p-4 rounded-lg border bg-white border-gray-200 dark:bg-gray-800 dark:border-gray-700"
                        >
                          {/* Header Row */}
                          <div className="flex justify-between items-start mb-3">
                            <div className="flex-1">
                              <div className="font-semibold text-lg mb-1 text-gray-900 dark:text-white">
                                {zone.name}
                              </div>
                              <Badge color="blue" size="sm" className="mt-1">
                                {zone.network}
                              </Badge>
                            </div>
                            <Badge color={serviceStatus.is_active ? "success" : "gray"} size="sm">
                              {serviceStatus.is_active ? "Running" : serviceStatus.is_enabled ? "Stopped" : "Disabled"}
                            </Badge>
                          </div>

                          {/* Details Grid */}
                          <div className="space-y-2 text-sm mb-4">
                            <div className="flex justify-between items-center">
                              <span className="text-gray-500 dark:text-gray-400">Authoritative:</span>
                              <Badge color={zone.authoritative ? "success" : "gray"} size="sm">
                                {zone.authoritative ? "Yes" : "No"}
                              </Badge>
                            </div>
                            
                            {zone.forward_to && (
                              <div className="flex justify-between">
                                <span className="text-gray-500 dark:text-gray-400">Forward To:</span>
                                <span className="text-gray-900 dark:text-gray-100 font-mono text-xs">{zone.forward_to}</span>
                              </div>
                            )}
                            
                            {zone.delegate_to && (
                              <div className="flex justify-between">
                                <span className="text-gray-500 dark:text-gray-400">Delegate To:</span>
                                <span className="text-gray-900 dark:text-gray-100 font-mono text-xs">{zone.delegate_to}</span>
                              </div>
                            )}
                          </div>

                          {/* Action Buttons */}
                          <div className="pt-3 border-t border-gray-200 dark:border-gray-700">
                            <div className="flex gap-2 mb-2 flex-wrap">
                              <Button
                                size="xs"
                                color="blue"
                                onClick={() => openRecordsView(zone)}
                                className="flex-1 min-w-[80px]"
                              >
                                Records
                              </Button>
                              <Button
                                size="xs"
                                color="gray"
                                onClick={() => openZoneModal(zone)}
                                className="flex-1 min-w-[80px]"
                              >
                                <HiPencil className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="failure"
                                onClick={() => {
                                  setZoneToDelete(zone);
                                  setDeleteZoneModalOpen(true);
                                }}
                                className="flex-1 min-w-[80px]"
                              >
                                <HiTrash className="w-4 h-4" />
                              </Button>
                            </div>
                            <div className="flex gap-2 flex-wrap">
                              <Button
                                size="xs"
                                color="success"
                                onClick={() => handleServiceControl(zone.network, 'start')}
                                disabled={isControlling || serviceStatus.is_active}
                                title="Start Service"
                                className="flex-1 min-w-[70px]"
                              >
                                <HiPlay className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="failure"
                                onClick={() => handleServiceControl(zone.network, 'stop')}
                                disabled={isControlling || !serviceStatus.is_active}
                                title="Stop Service"
                                className="flex-1 min-w-[70px]"
                              >
                                <HiStop className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="warning"
                                onClick={() => handleServiceControl(zone.network, 'reload')}
                                disabled={isControlling || !serviceStatus.is_active}
                                title="Reload Service"
                                className="flex-1 min-w-[70px]"
                              >
                                <HiRefresh className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="purple"
                                onClick={() => handleServiceControl(zone.network, 'restart')}
                                disabled={isControlling}
                                title="Restart Service"
                                className="flex-1 min-w-[70px]"
                              >
                                <HiRefresh className="w-4 h-4" />
                              </Button>
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
            </Card>

            {/* Zone Modal */}
            <Modal show={zoneModalOpen} onClose={closeZoneModal} size="lg">
              <Modal.Header>
                {editingZone ? 'Edit DNS Zone' : 'Create DNS Zone'}
              </Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {zoneError && (
                    <Alert color="failure">
                      {zoneError}
                    </Alert>
                  )}
                  <div>
                    <Label htmlFor="zoneName" value="Zone Name *" />
                    <TextInput
                      id="zoneName"
                      value={zoneName}
                      onChange={(e) => setZoneName(e.target.value)}
                      placeholder="example.com"
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="zoneNetwork" value="Network *" />
                    <Select
                      id="zoneNetwork"
                      value={zoneNetwork}
                      onChange={(e) => setZoneNetwork(e.target.value as 'homelab' | 'lan')}
                      className="mt-1"
                    >
                      <option value="homelab">HOMELAB</option>
                      <option value="lan">LAN</option>
                    </Select>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="zoneAuthoritative"
                      checked={zoneAuthoritative}
                      onChange={(e) => setZoneAuthoritative(e.target.checked)}
                      className="w-4 h-4"
                    />
                    <Label htmlFor="zoneAuthoritative" value="Authoritative (serve locally)" />
                  </div>
                  <div>
                    <Label htmlFor="zoneForwardTo" value="Forward To (optional)" />
                    <TextInput
                      id="zoneForwardTo"
                      value={zoneForwardTo}
                      onChange={(e) => setZoneForwardTo(e.target.value)}
                      placeholder="192.168.1.1"
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="zoneDelegateTo" value="Delegate To (optional)" />
                    <TextInput
                      id="zoneDelegateTo"
                      value={zoneDelegateTo}
                      onChange={(e) => setZoneDelegateTo(e.target.value)}
                      placeholder="ns1.example.com"
                      className="mt-1"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="zoneEnabled"
                      checked={zoneEnabled}
                      onChange={(e) => setZoneEnabled(e.target.checked)}
                      className="w-4 h-4"
                    />
                    <Label htmlFor="zoneEnabled" value="Enabled" />
                  </div>
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button
                  color="blue"
                  onClick={handleSaveZone}
                  disabled={saving || !zoneName.trim()}
                >
                  {saving ? 'Saving...' : 'Save'}
                </Button>
                <Button color="gray" onClick={closeZoneModal}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Records View Modal */}
            <Modal show={recordsViewModalOpen} onClose={closeRecordsView} size="4xl">
              <Modal.Header>
                {selectedZone ? `DNS Records for ${selectedZone.name}` : 'DNS Records'}
              </Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {recordError && (
                    <Alert color="failure">
                      {recordError}
                    </Alert>
                  )}
                  
                  <div className="flex justify-between items-center">
                    <h3 className="text-lg font-semibold">Records</h3>
                    {selectedZone && (
                      <Button
                        size="sm"
                        color="blue"
                        onClick={() => openRecordEditModal(selectedZone)}
                      >
                        <HiPlus className="w-4 h-4 mr-1" />
                        Add Record
                      </Button>
                    )}
                  </div>
                  
                  {records.length === 0 ? (
                    <Alert color="info">
                      No records in this zone. Add a record to get started.
                    </Alert>
                  ) : (
                    <Table>
                      <Table.Head>
                        <Table.HeadCell>Name</Table.HeadCell>
                        <Table.HeadCell>Type</Table.HeadCell>
                        <Table.HeadCell>Value</Table.HeadCell>
                        <Table.HeadCell>Comment</Table.HeadCell>
                        <Table.HeadCell>Status</Table.HeadCell>
                        <Table.HeadCell>Actions</Table.HeadCell>
                      </Table.Head>
                      <Table.Body className="divide-y">
                        {records.map((record) => (
                          <Table.Row key={record.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                            <Table.Cell className="font-medium text-gray-900 dark:text-white">
                              {record.name}
                            </Table.Cell>
                            <Table.Cell>
                              <Badge color={record.type === 'A' ? "blue" : "purple"}>
                                {record.type}
                              </Badge>
                            </Table.Cell>
                            <Table.Cell className="font-mono text-sm text-gray-900 dark:text-white">
                              {record.value}
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {record.comment || '-'}
                            </Table.Cell>
                            <Table.Cell>
                              <Badge color={record.enabled ? "success" : "gray"}>
                                {record.enabled ? "Enabled" : "Disabled"}
                              </Badge>
                            </Table.Cell>
                            <Table.Cell>
                              <div className="flex gap-2">
                                <Button
                                  size="xs"
                                  color="gray"
                                  onClick={() => {
                                    closeRecordsView();
                                    openRecordEditModal(selectedZone!, record);
                                  }}
                                >
                                  <HiPencil className="w-4 h-4" />
                                </Button>
                                <Button
                                  size="xs"
                                  color="failure"
                                  onClick={() => {
                                    setRecordToDelete(record);
                                    setDeleteRecordModalOpen(true);
                                  }}
                                >
                                  <HiTrash className="w-4 h-4" />
                                </Button>
                              </div>
                            </Table.Cell>
                          </Table.Row>
                        ))}
                      </Table.Body>
                    </Table>
                  )}
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button color="gray" onClick={closeRecordsView}>
                  Close
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Record Edit/Create Modal */}
            <Modal show={recordEditModalOpen} onClose={closeRecordEditModal} size="lg">
              <Modal.Header>
                {editingRecord ? 'Edit DNS Record' : 'Create DNS Record'}
              </Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {recordError && (
                    <Alert color="failure">
                      {recordError}
                    </Alert>
                  )}
                  <div>
                    <Label htmlFor="recordName" value="Record Name *" />
                    <TextInput
                      id="recordName"
                      value={recordName}
                      onChange={(e) => setRecordName(e.target.value)}
                      placeholder="hostname.example.com"
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="recordType" value="Record Type *" />
                    <Select
                      id="recordType"
                      value={recordType}
                      onChange={(e) => setRecordType(e.target.value as 'A' | 'CNAME')}
                      className="mt-1"
                    >
                      <option value="A">A (IPv4 Address)</option>
                      <option value="CNAME">CNAME (Alias)</option>
                    </Select>
                  </div>
                  <div>
                    <Label htmlFor="recordValue" value={recordType === 'A' ? 'IP Address *' : 'Target Hostname *'} />
                    <TextInput
                      id="recordValue"
                      value={recordValue}
                      onChange={(e) => setRecordValue(e.target.value)}
                      placeholder={recordType === 'A' ? '192.168.1.1' : 'target.example.com'}
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="recordComment" value="Comment (optional)" />
                    <TextInput
                      id="recordComment"
                      value={recordComment}
                      onChange={(e) => setRecordComment(e.target.value)}
                      className="mt-1"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      id="recordEnabled"
                      checked={recordEnabled}
                      onChange={(e) => setRecordEnabled(e.target.checked)}
                      className="w-4 h-4"
                    />
                    <Label htmlFor="recordEnabled" value="Enabled" />
                  </div>
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button
                  color="blue"
                  onClick={handleSaveRecord}
                  disabled={saving || !recordName.trim() || !recordValue.trim()}
                >
                  {saving ? 'Saving...' : 'Save'}
                </Button>
                <Button color="gray" onClick={closeRecordEditModal}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Delete Zone Confirmation */}
            <Modal show={deleteZoneModalOpen} onClose={() => setDeleteZoneModalOpen(false)} size="md">
              <Modal.Header>Delete Zone</Modal.Header>
              <Modal.Body>
                <p className="text-gray-700 dark:text-gray-300">
                  Are you sure you want to delete zone <strong>{zoneToDelete?.name}</strong>? 
                  This will also delete all records in this zone.
                </p>
              </Modal.Body>
              <Modal.Footer>
                <Button color="failure" onClick={handleDeleteZone}>
                  Delete
                </Button>
                <Button color="gray" onClick={() => setDeleteZoneModalOpen(false)}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Delete Record Confirmation */}
            <Modal show={deleteRecordModalOpen} onClose={() => setDeleteRecordModalOpen(false)} size="md">
              <Modal.Header>Delete Record</Modal.Header>
              <Modal.Body>
                <p className="text-gray-700 dark:text-gray-300">
                  Are you sure you want to delete record <strong>{recordToDelete?.name}</strong>?
                </p>
              </Modal.Body>
              <Modal.Footer>
                <Button color="failure" onClick={handleDeleteRecord}>
                  Delete
                </Button>
                <Button color="gray" onClick={() => setDeleteRecordModalOpen(false)}>
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

