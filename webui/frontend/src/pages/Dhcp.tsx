/**
 * DHCP Management Page
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Button, TextInput, Label, Select, Badge, Alert, Modal, Table, Checkbox } from 'flowbite-react';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';
import { HiServer, HiPencil, HiTrash, HiPlus, HiInformationCircle, HiPlay, HiStop, HiRefresh } from 'react-icons/hi';
import type { DhcpNetwork, DhcpNetworkCreate, DhcpNetworkUpdate, DhcpReservation, DhcpReservationCreate, DhcpReservationUpdate } from '../types/dhcp';

export function Dhcp() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [networks, setNetworks] = useState<DhcpNetwork[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [networkFilter, setNetworkFilter] = useState<'all' | 'homelab' | 'lan'>('all');
  const [dhcpServiceStatus, setDhcpServiceStatus] = useState<{ is_active: boolean; is_enabled: boolean; exists: boolean } | null>(null);
  const [controllingDhcpService, setControllingDhcpService] = useState(false);
  
  // Network modal state
  const [networkModalOpen, setNetworkModalOpen] = useState(false);
  const [editingNetwork, setEditingNetwork] = useState<DhcpNetwork | null>(null);
  const [networkNetwork, setNetworkNetwork] = useState<'homelab' | 'lan'>('homelab');
  const [networkEnabled, setNetworkEnabled] = useState(true);
  const [networkStart, setNetworkStart] = useState('');
  const [networkEnd, setNetworkEnd] = useState('');
  const [networkLeaseTime, setNetworkLeaseTime] = useState('1h');
  const [networkDnsServers, setNetworkDnsServers] = useState('');
  const [networkDynamicDomain, setNetworkDynamicDomain] = useState('');
  const [saving, setSaving] = useState(false);
  const [networkError, setNetworkError] = useState<string | null>(null);
  
  // Reservation modal state
  const [reservationsViewModalOpen, setReservationsViewModalOpen] = useState(false);
  const [reservationEditModalOpen, setReservationEditModalOpen] = useState(false);
  const [selectedNetwork, setSelectedNetwork] = useState<DhcpNetwork | null>(null);
  const [reservations, setReservations] = useState<DhcpReservation[]>([]);
  const [editingReservation, setEditingReservation] = useState<DhcpReservation | null>(null);
  const [reservationHostname, setReservationHostname] = useState('');
  const [reservationHwAddress, setReservationHwAddress] = useState('');
  const [reservationIpAddress, setReservationIpAddress] = useState('');
  const [reservationComment, setReservationComment] = useState('');
  const [reservationEnabled, setReservationEnabled] = useState(true);
  const [reservationError, setReservationError] = useState<string | null>(null);
  
  // Delete confirmation
  const [deleteNetworkModalOpen, setDeleteNetworkModalOpen] = useState(false);
  const [deleteReservationModalOpen, setDeleteReservationModalOpen] = useState(false);
  const [networkToDelete, setNetworkToDelete] = useState<DhcpNetwork | null>(null);
  const [reservationToDelete, setReservationToDelete] = useState<DhcpReservation | null>(null);
  
  const { connectionStatus } = useMetrics(token);

  useEffect(() => {
    if (!token) {
      navigate('/login');
      return;
    }
    fetchNetworks();
    fetchDhcpServiceStatus();
  }, [token, networkFilter]);

  const fetchDhcpServiceStatus = async () => {
    try {
      const status = await apiClient.getDhcpServiceStatus();
      setDhcpServiceStatus(status);
    } catch (err: any) {
      console.error('Failed to fetch DHCP service status:', err);
    }
  };

  const handleDhcpServiceControl = async (action: 'start' | 'stop' | 'restart' | 'reload') => {
    setControllingDhcpService(true);
    try {
      await apiClient.controlDhcpService(action);
      // Refresh service status after a short delay
      setTimeout(() => {
        fetchDhcpServiceStatus();
      }, 1000);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || `Failed to ${action} DHCP service`);
    } finally {
      setControllingDhcpService(false);
    }
  };

  const fetchNetworks = async () => {
    setLoading(true);
    setError(null);
    try {
      const network = networkFilter === 'all' ? undefined : networkFilter;
      const data = await apiClient.getDhcpNetworks(network);
      setNetworks(data);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to load DHCP networks');
    } finally {
      setLoading(false);
    }
  };

  const fetchReservations = async (networkId: number) => {
    try {
      const data = await apiClient.getDhcpReservations(networkId);
      setReservations(data);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to load DHCP reservations');
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('access_token');
    localStorage.removeItem('username');
    navigate('/login');
  };

  const openNetworkModal = (network?: DhcpNetwork) => {
    if (network) {
      setEditingNetwork(network);
      setNetworkNetwork(network.network);
      setNetworkEnabled(network.enabled);
      setNetworkStart(network.start);
      setNetworkEnd(network.end);
      setNetworkLeaseTime(network.lease_time);
      setNetworkDnsServers(network.dns_servers?.join(', ') || '');
      setNetworkDynamicDomain(network.dynamic_domain || '');
    } else {
      setEditingNetwork(null);
      setNetworkNetwork('homelab');
      setNetworkEnabled(true);
      setNetworkStart('');
      setNetworkEnd('');
      setNetworkLeaseTime('1h');
      setNetworkDnsServers('');
      setNetworkDynamicDomain('');
    }
    setNetworkError(null);
    setNetworkModalOpen(true);
  };

  const closeNetworkModal = () => {
    setNetworkModalOpen(false);
    setEditingNetwork(null);
    setNetworkError(null);
  };

  const handleSaveNetwork = async () => {
    setNetworkError(null);
    setSaving(true);
    
    try {
      if (!networkStart.trim() || !networkEnd.trim()) {
        setNetworkError('Start and end IP addresses are required');
        setSaving(false);
        return;
      }
      
      const dnsServersList = networkDnsServers.trim()
        ? networkDnsServers.split(',').map(s => s.trim()).filter(s => s)
        : null;
      
      if (editingNetwork) {
        const update: DhcpNetworkUpdate = {
          enabled: networkEnabled,
          start: networkStart.trim(),
          end: networkEnd.trim(),
          lease_time: networkLeaseTime.trim(),
          dns_servers: dnsServersList,
          dynamic_domain: networkDynamicDomain.trim() || null,
        };
        await apiClient.updateDhcpNetwork(editingNetwork.id, update);
      } else {
        const create: DhcpNetworkCreate = {
          network: networkNetwork,
          enabled: networkEnabled,
          start: networkStart.trim(),
          end: networkEnd.trim(),
          lease_time: networkLeaseTime.trim(),
          dns_servers: dnsServersList,
          dynamic_domain: networkDynamicDomain.trim() || null,
        };
        await apiClient.createDhcpNetwork(create);
      }
      
      await fetchNetworks();
      closeNetworkModal();
    } catch (err: any) {
      setNetworkError(err?.response?.data?.detail || err.message || 'Failed to save network');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteNetwork = async () => {
    if (!networkToDelete) return;
    
    try {
      await apiClient.deleteDhcpNetwork(networkToDelete.id);
      await fetchNetworks();
      setDeleteNetworkModalOpen(false);
      setNetworkToDelete(null);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to delete network');
    }
  };

  const openReservationsView = async (network: DhcpNetwork) => {
    setSelectedNetwork(network);
    await fetchReservations(network.id);
    setReservationsViewModalOpen(true);
  };

  const closeReservationsView = () => {
    setReservationsViewModalOpen(false);
    setSelectedNetwork(null);
    setReservations([]);
  };

  const openReservationEditModal = (reservation?: DhcpReservation) => {
    if (reservation) {
      setEditingReservation(reservation);
      setReservationHostname(reservation.hostname);
      setReservationHwAddress(reservation.hw_address);
      setReservationIpAddress(reservation.ip_address);
      setReservationComment(reservation.comment || '');
      setReservationEnabled(reservation.enabled);
    } else {
      setEditingReservation(null);
      setReservationHostname('');
      setReservationHwAddress('');
      setReservationIpAddress('');
      setReservationComment('');
      setReservationEnabled(true);
    }
    setReservationError(null);
    setReservationEditModalOpen(true);
  };

  const closeReservationEditModal = () => {
    setReservationEditModalOpen(false);
    setEditingReservation(null);
    setReservationError(null);
    if (selectedNetwork) {
      fetchReservations(selectedNetwork.id);
    }
  };

  const handleSaveReservation = async () => {
    if (!selectedNetwork) return;
    
    setReservationError(null);
    setSaving(true);
    
    try {
      if (!reservationHostname.trim()) {
        setReservationError('Hostname is required');
        setSaving(false);
        return;
      }
      
      if (!reservationHwAddress.trim()) {
        setReservationError('MAC address is required');
        setSaving(false);
        return;
      }
      
      if (!reservationIpAddress.trim()) {
        setReservationError('IP address is required');
        setSaving(false);
        return;
      }
      
      if (editingReservation) {
        const update: DhcpReservationUpdate = {
          hostname: reservationHostname.trim(),
          hw_address: reservationHwAddress.trim(),
          ip_address: reservationIpAddress.trim(),
          comment: reservationComment.trim() || null,
          enabled: reservationEnabled,
        };
        await apiClient.updateDhcpReservation(editingReservation.id, update);
      } else {
        const create: DhcpReservationCreate = {
          network_id: selectedNetwork.id,
          hostname: reservationHostname.trim(),
          hw_address: reservationHwAddress.trim(),
          ip_address: reservationIpAddress.trim(),
          comment: reservationComment.trim() || null,
          enabled: reservationEnabled,
        };
        await apiClient.createDhcpReservation(selectedNetwork.id, create);
      }
      
      await fetchReservations(selectedNetwork.id);
      closeReservationEditModal();
    } catch (err: any) {
      setReservationError(err?.response?.data?.detail || err.message || 'Failed to save reservation');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteReservation = async () => {
    if (!reservationToDelete) return;
    
    try {
      await apiClient.deleteDhcpReservation(reservationToDelete.id);
      if (selectedNetwork) {
        await fetchReservations(selectedNetwork.id);
      }
      setDeleteReservationModalOpen(false);
      setReservationToDelete(null);
    } catch (err: any) {
      setError(err?.response?.data?.detail || err.message || 'Failed to delete reservation');
    }
  };

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600 dark:text-gray-400">Loading DHCP networks...</p>
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
                <HiServer className="w-8 h-8 text-gray-900 dark:text-white" />
                <h1 className="text-3xl font-bold text-gray-900 dark:text-white">DHCP Management</h1>
              </div>
              <Button
                color="blue"
                onClick={() => openNetworkModal()}
              >
                New Network
              </Button>
            </div>

            {error && (
              <Alert color="failure" className="mb-6" onDismiss={() => setError(null)}>
                {error}
              </Alert>
            )}

            {/* Network Filter and DHCP Service Controls */}
            <div className="mb-4 flex flex-col md:flex-row justify-between items-start md:items-end gap-4">
              <div>
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
              
              {/* DHCP Service Controls */}
              <div className="flex flex-col gap-2">
                <Label value="DHCP Service" />
                <div className="flex gap-2 items-center flex-wrap">
                  {dhcpServiceStatus && (
                    <Badge color={dhcpServiceStatus.is_active ? "success" : "gray"} size="sm">
                      {dhcpServiceStatus.is_active ? "Running" : dhcpServiceStatus.is_enabled ? "Stopped" : "Disabled"}
                    </Badge>
                  )}
                  <Button
                    size="xs"
                    color="success"
                    onClick={() => handleDhcpServiceControl('start')}
                    disabled={controllingDhcpService || (dhcpServiceStatus?.is_active ?? false)}
                    title="Start Service"
                  >
                    <HiPlay className="w-4 h-4" />
                  </Button>
                  <Button
                    size="xs"
                    color="failure"
                    onClick={() => handleDhcpServiceControl('stop')}
                    disabled={controllingDhcpService || !(dhcpServiceStatus?.is_active ?? false)}
                    title="Stop Service"
                  >
                    <HiStop className="w-4 h-4" />
                  </Button>
                  <Button
                    size="xs"
                    color="warning"
                    onClick={() => handleDhcpServiceControl('reload')}
                    disabled={controllingDhcpService || !(dhcpServiceStatus?.is_active ?? false)}
                    title="Reload Service"
                  >
                    <HiRefresh className="w-4 h-4" />
                  </Button>
                  <Button
                    size="xs"
                    color="purple"
                    onClick={() => handleDhcpServiceControl('restart')}
                    disabled={controllingDhcpService}
                    title="Restart Service"
                  >
                    <HiRefresh className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            </div>

            {/* Networks Cards */}
            <Card>
              <h2 className="text-xl font-semibold text-gray-900 dark:text-white mb-4">
                DHCP Networks ({networks.length})
              </h2>
              
              {networks.length === 0 ? (
                <Alert color="info" icon={HiInformationCircle}>
                  No DHCP networks configured. Create a network to get started.
                </Alert>
              ) : (
                <>
                  {/* Desktop Table View */}
                  <div className="hidden min-[1000px]:block overflow-x-auto">
                    <Table>
                      <Table.Head>
                        <Table.HeadCell>Network</Table.HeadCell>
                        <Table.HeadCell>IP Range</Table.HeadCell>
                        <Table.HeadCell>Lease Time</Table.HeadCell>
                        <Table.HeadCell>DNS Servers</Table.HeadCell>
                        <Table.HeadCell>Dynamic Domain</Table.HeadCell>
                        <Table.HeadCell>Status</Table.HeadCell>
                        <Table.HeadCell>Actions</Table.HeadCell>
                      </Table.Head>
                      <Table.Body className="divide-y">
                        {networks.map((network) => (
                          <Table.Row key={network.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                            <Table.Cell>
                              <Badge color="blue">{network.network}</Badge>
                            </Table.Cell>
                            <Table.Cell className="font-mono text-sm text-gray-900 dark:text-white">
                              {network.start} - {network.end}
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {network.lease_time}
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {network.dns_servers?.join(', ') || '-'}
                            </Table.Cell>
                            <Table.Cell className="text-gray-500 dark:text-gray-400">
                              {network.dynamic_domain || '-'}
                            </Table.Cell>
                            <Table.Cell>
                              <Badge color={network.enabled ? "success" : "gray"}>
                                {network.enabled ? "Enabled" : "Disabled"}
                              </Badge>
                            </Table.Cell>
                            <Table.Cell>
                              <div className="flex gap-2 flex-wrap">
                                <Button
                                  size="xs"
                                  color="blue"
                                  onClick={() => openReservationsView(network)}
                                >
                                  Reservations
                                </Button>
                                <Button
                                  size="xs"
                                  color="gray"
                                  onClick={() => openNetworkModal(network)}
                                >
                                  <HiPencil className="w-4 h-4" />
                                </Button>
                                <Button
                                  size="xs"
                                  color="failure"
                                  onClick={() => {
                                    setNetworkToDelete(network);
                                    setDeleteNetworkModalOpen(true);
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
                  <div className="min-[1000px]:hidden space-y-3">
                    {networks.map((network) => (
                      <div
                        key={network.id}
                        className="p-4 rounded-lg border bg-white border-gray-200 dark:bg-gray-800 dark:border-gray-700"
                      >
                        {/* Header Row */}
                        <div className="flex justify-between items-start mb-3">
                          <div className="flex-1">
                            <Badge color="blue" size="sm" className="mb-2">
                              {network.network}
                            </Badge>
                            <div className="font-mono text-sm text-gray-900 dark:text-white">
                              {network.start} - {network.end}
                            </div>
                          </div>
                          <Badge color={network.enabled ? "success" : "gray"} size="sm">
                            {network.enabled ? "Enabled" : "Disabled"}
                          </Badge>
                        </div>

                        {/* Details Grid */}
                        <div className="space-y-2 text-sm mb-4">
                          <div className="flex justify-between">
                            <span className="text-gray-500 dark:text-gray-400">Lease Time:</span>
                            <span className="text-gray-900 dark:text-gray-100">{network.lease_time}</span>
                          </div>
                          
                          {network.dns_servers && network.dns_servers.length > 0 && (
                            <div className="flex justify-between">
                              <span className="text-gray-500 dark:text-gray-400">DNS Servers:</span>
                              <span className="text-gray-900 dark:text-gray-100 font-mono text-xs">{network.dns_servers.join(', ')}</span>
                            </div>
                          )}
                          
                          {network.dynamic_domain && (
                            <div className="flex justify-between">
                              <span className="text-gray-500 dark:text-gray-400">Dynamic Domain:</span>
                              <span className="text-gray-900 dark:text-gray-100">{network.dynamic_domain}</span>
                            </div>
                          )}
                        </div>

                        {/* Action Buttons */}
                        <div className="pt-3 border-t border-gray-200 dark:border-gray-700">
                          <div className="flex gap-2 flex-wrap">
                            <Button
                              size="xs"
                              color="blue"
                              onClick={() => openReservationsView(network)}
                              className="flex-1 min-w-[100px]"
                            >
                              Reservations
                            </Button>
                            <Button
                              size="xs"
                              color="gray"
                              onClick={() => openNetworkModal(network)}
                              className="flex-1 min-w-[80px]"
                            >
                              <HiPencil className="w-4 h-4" />
                            </Button>
                            <Button
                              size="xs"
                              color="failure"
                              onClick={() => {
                                setNetworkToDelete(network);
                                setDeleteNetworkModalOpen(true);
                              }}
                              className="flex-1 min-w-[80px]"
                            >
                              <HiTrash className="w-4 h-4" />
                            </Button>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </>
              )}
            </Card>

            {/* Network Modal */}
            <Modal show={networkModalOpen} onClose={closeNetworkModal} size="lg">
              <Modal.Header>
                {editingNetwork ? 'Edit DHCP Network' : 'Create DHCP Network'}
              </Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {networkError && (
                    <Alert color="failure">
                      {networkError}
                    </Alert>
                  )}
                  {!editingNetwork && (
                    <div>
                      <Label htmlFor="networkNetwork" value="Network *" />
                      <Select
                        id="networkNetwork"
                        value={networkNetwork}
                        onChange={(e) => setNetworkNetwork(e.target.value as 'homelab' | 'lan')}
                        className="mt-1"
                        required
                      >
                        <option value="homelab">HOMELAB</option>
                        <option value="lan">LAN</option>
                      </Select>
                    </div>
                  )}
                  <div className="flex items-center gap-2">
                    <Checkbox
                      id="networkEnabled"
                      checked={networkEnabled}
                      onChange={(e) => setNetworkEnabled(e.target.checked)}
                    />
                    <Label htmlFor="networkEnabled" value="Enabled" />
                  </div>
                  <div>
                    <Label htmlFor="networkStart" value="IP Range Start *" />
                    <TextInput
                      id="networkStart"
                      value={networkStart}
                      onChange={(e) => setNetworkStart(e.target.value)}
                      placeholder="192.168.2.100"
                      required
                      className="mt-1 font-mono"
                    />
                  </div>
                  <div>
                    <Label htmlFor="networkEnd" value="IP Range End *" />
                    <TextInput
                      id="networkEnd"
                      value={networkEnd}
                      onChange={(e) => setNetworkEnd(e.target.value)}
                      placeholder="192.168.2.200"
                      required
                      className="mt-1 font-mono"
                    />
                  </div>
                  <div>
                    <Label htmlFor="networkLeaseTime" value="Lease Time *" />
                    <TextInput
                      id="networkLeaseTime"
                      value={networkLeaseTime}
                      onChange={(e) => setNetworkLeaseTime(e.target.value)}
                      placeholder="1h, 1d, or 86400"
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="networkDnsServers" value="DNS Servers (comma-separated)" />
                    <TextInput
                      id="networkDnsServers"
                      value={networkDnsServers}
                      onChange={(e) => setNetworkDnsServers(e.target.value)}
                      placeholder="192.168.2.1, 8.8.8.8"
                      className="mt-1 font-mono"
                    />
                  </div>
                  <div>
                    <Label htmlFor="networkDynamicDomain" value="Dynamic DNS Domain (optional)" />
                    <TextInput
                      id="networkDynamicDomain"
                      value={networkDynamicDomain}
                      onChange={(e) => setNetworkDynamicDomain(e.target.value)}
                      placeholder="dhcp.homelab.local"
                      className="mt-1"
                    />
                  </div>
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button
                  color="blue"
                  onClick={handleSaveNetwork}
                  disabled={saving || !networkStart.trim() || !networkEnd.trim()}
                >
                  {saving ? 'Saving...' : editingNetwork ? 'Update' : 'Create'}
                </Button>
                <Button color="gray" onClick={closeNetworkModal}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Reservations View Modal */}
            <Modal show={reservationsViewModalOpen} onClose={closeReservationsView} size="6xl">
              <Modal.Header>
                Reservations - {selectedNetwork?.network.toUpperCase()}
              </Modal.Header>
              <Modal.Body>
                <div className="flex justify-between items-center mb-4">
                  <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                    Static IP Reservations ({reservations.length})
                  </h3>
                  <Button
                    size="sm"
                    color="blue"
                    onClick={() => openReservationEditModal()}
                  >
                    <HiPlus className="w-4 h-4 mr-1" />
                    New Reservation
                  </Button>
                </div>
                
                {reservations.length === 0 ? (
                  <Alert color="info" icon={HiInformationCircle}>
                    No reservations configured for this network.
                  </Alert>
                ) : (
                  <Table>
                    <Table.Head>
                      <Table.HeadCell>Hostname</Table.HeadCell>
                      <Table.HeadCell>MAC Address</Table.HeadCell>
                      <Table.HeadCell>IP Address</Table.HeadCell>
                      <Table.HeadCell>Comment</Table.HeadCell>
                      <Table.HeadCell>Status</Table.HeadCell>
                      <Table.HeadCell>Actions</Table.HeadCell>
                    </Table.Head>
                    <Table.Body className="divide-y">
                      {reservations.map((reservation) => (
                        <Table.Row key={reservation.id} className="bg-white dark:border-gray-700 dark:bg-gray-800">
                          <Table.Cell className="font-medium text-gray-900 dark:text-white">
                            {reservation.hostname}
                          </Table.Cell>
                          <Table.Cell className="font-mono text-sm text-gray-500 dark:text-gray-400">
                            {reservation.hw_address}
                          </Table.Cell>
                          <Table.Cell className="font-mono text-sm text-gray-900 dark:text-white">
                            {reservation.ip_address}
                          </Table.Cell>
                          <Table.Cell className="text-gray-500 dark:text-gray-400">
                            {reservation.comment || '-'}
                          </Table.Cell>
                          <Table.Cell>
                            <Badge color={reservation.enabled ? "success" : "gray"}>
                              {reservation.enabled ? "Enabled" : "Disabled"}
                            </Badge>
                          </Table.Cell>
                          <Table.Cell>
                            <div className="flex gap-2">
                              <Button
                                size="xs"
                                color="gray"
                                onClick={() => openReservationEditModal(reservation)}
                              >
                                <HiPencil className="w-4 h-4" />
                              </Button>
                              <Button
                                size="xs"
                                color="failure"
                                onClick={() => {
                                  setReservationToDelete(reservation);
                                  setDeleteReservationModalOpen(true);
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
              </Modal.Body>
              <Modal.Footer>
                <Button color="gray" onClick={closeReservationsView}>
                  Close
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Reservation Edit Modal */}
            <Modal show={reservationEditModalOpen} onClose={closeReservationEditModal} size="lg">
              <Modal.Header>
                {editingReservation ? 'Edit Reservation' : 'Create Reservation'}
              </Modal.Header>
              <Modal.Body>
                <div className="space-y-4">
                  {reservationError && (
                    <Alert color="failure">
                      {reservationError}
                    </Alert>
                  )}
                  <div>
                    <Label htmlFor="reservationHostname" value="Hostname *" />
                    <TextInput
                      id="reservationHostname"
                      value={reservationHostname}
                      onChange={(e) => setReservationHostname(e.target.value)}
                      placeholder="desktop"
                      required
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="reservationHwAddress" value="MAC Address *" />
                    <TextInput
                      id="reservationHwAddress"
                      value={reservationHwAddress}
                      onChange={(e) => setReservationHwAddress(e.target.value)}
                      placeholder="11:22:33:44:55:66"
                      required
                      className="mt-1 font-mono"
                    />
                  </div>
                  <div>
                    <Label htmlFor="reservationIpAddress" value="IP Address *" />
                    <TextInput
                      id="reservationIpAddress"
                      value={reservationIpAddress}
                      onChange={(e) => setReservationIpAddress(e.target.value)}
                      placeholder="192.168.2.50"
                      required
                      className="mt-1 font-mono"
                    />
                  </div>
                  <div>
                    <Label htmlFor="reservationComment" value="Comment (optional)" />
                    <TextInput
                      id="reservationComment"
                      value={reservationComment}
                      onChange={(e) => setReservationComment(e.target.value)}
                      className="mt-1"
                    />
                  </div>
                  <div className="flex items-center gap-2">
                    <Checkbox
                      id="reservationEnabled"
                      checked={reservationEnabled}
                      onChange={(e) => setReservationEnabled(e.target.checked)}
                    />
                    <Label htmlFor="reservationEnabled" value="Enabled" />
                  </div>
                </div>
              </Modal.Body>
              <Modal.Footer>
                <Button
                  color="blue"
                  onClick={handleSaveReservation}
                  disabled={saving || !reservationHostname.trim() || !reservationHwAddress.trim() || !reservationIpAddress.trim()}
                >
                  {saving ? 'Saving...' : editingReservation ? 'Update' : 'Create'}
                </Button>
                <Button color="gray" onClick={closeReservationEditModal}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Delete Network Confirmation */}
            <Modal show={deleteNetworkModalOpen} onClose={() => setDeleteNetworkModalOpen(false)} size="md">
              <Modal.Header>Delete DHCP Network</Modal.Header>
              <Modal.Body>
                <p className="text-gray-700 dark:text-gray-300">
                  Are you sure you want to delete the DHCP network for <strong>{networkToDelete?.network}</strong>?
                  This will also delete all reservations for this network.
                </p>
              </Modal.Body>
              <Modal.Footer>
                <Button color="failure" onClick={handleDeleteNetwork}>
                  Delete
                </Button>
                <Button color="gray" onClick={() => setDeleteNetworkModalOpen(false)}>
                  Cancel
                </Button>
              </Modal.Footer>
            </Modal>

            {/* Delete Reservation Confirmation */}
            <Modal show={deleteReservationModalOpen} onClose={() => setDeleteReservationModalOpen(false)} size="md">
              <Modal.Header>Delete Reservation</Modal.Header>
              <Modal.Body>
                <p className="text-gray-700 dark:text-gray-300">
                  Are you sure you want to delete the reservation for <strong>{reservationToDelete?.hostname}</strong>?
                </p>
              </Modal.Body>
              <Modal.Footer>
                <Button color="failure" onClick={handleDeleteReservation}>
                  Delete
                </Button>
                <Button color="gray" onClick={() => setDeleteReservationModalOpen(false)}>
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

