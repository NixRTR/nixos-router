/**
 * Network Devices page - Shows all devices (DHCP and static)
 */
import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Table, Badge, TextInput, Select, Button } from 'flowbite-react';
import { HiSearch } from 'react-icons/hi';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

interface NetworkDevice {
  network: string;
  ip_address: string;
  mac_address: string;
  hostname: string;
  nickname?: string | null;
  favorite?: boolean;
  vendor: string | null;
  is_dhcp: boolean;
  is_static: boolean;
  is_online: boolean;
  last_seen: string;
}

export function Clients() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('all'); // all, online, offline
  const [filterType, setFilterType] = useState('all'); // all, dhcp, static
  const [filterNetwork, setFilterNetwork] = useState('all'); // all, homelab, lan
  const [devices, setDevices] = useState<NetworkDevice[]>([]);
  const [blockedV4, setBlockedV4] = useState<string[]>([]);
  const [blockedMacs, setBlockedMacs] = useState<string[]>([]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  
  const { connectionStatus } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  // Fetch devices every 10 seconds
  useEffect(() => {
    const fetchDevices = async () => {
      if (!token) return;
      
      try {
        const response = await fetch('/api/devices/all', {
          headers: {
            'Authorization': `Bearer ${token}`,
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          setDevices(data);
        }
      } catch (error) {
        console.error('Failed to fetch devices:', error);
      }
    };
    
    fetchDevices();
    const interval = setInterval(fetchDevices, 10000);
    return () => clearInterval(interval);
  }, [token]);

  // Fetch blocked list every 10 seconds
  useEffect(() => {
    const fetchBlocked = async () => {
      if (!token) return;
      try {
        const response = await fetch('/api/devices/blocked', {
          headers: { 'Authorization': `Bearer ${token}` },
        });
        if (response.ok) {
          const data = await response.json();
          setBlockedV4(data.ipv4 || []);
          setBlockedMacs((data.macs || []).map((m: string) => m.toLowerCase()));
        }
      } catch (e) {
        // ignore
      }
    };
    fetchBlocked();
    const interval = setInterval(fetchBlocked, 10000);
    return () => clearInterval(interval);
  }, [token]);

  const isDeviceBlocked = (device: NetworkDevice) => {
    if (device.mac_address && blockedMacs.includes(device.mac_address.toLowerCase())) return true;
    return (device.ip_address && blockedV4.includes(device.ip_address));
  };

  const toggleFavorite = async (device: NetworkDevice) => {
    if (!token) return;
    const newFav = !device.favorite;
    // optimistic update
    setDevices(prev => prev.map(d => d.mac_address === device.mac_address ? { ...d, favorite: newFav } : d));
    try {
      await fetch('/api/devices/override', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ mac_address: device.mac_address, favorite: newFav }),
      });
      // Re-fetch to apply backend sorting (favorites first)
      const resp = await fetch('/api/devices/all', { headers: { 'Authorization': `Bearer ${token}` } });
      if (resp.ok) setDevices(await resp.json());
    } catch {
      // revert
      setDevices(prev => prev.map(d => d.mac_address === device.mac_address ? { ...d, favorite: !newFav } : d));
    }
  };

  const editNickname = async (device: NetworkDevice) => {
    if (!token) return;
    const currentName = device.nickname || '';
    const value = window.prompt('Set nickname for this device:', currentName);
    if (value === null) return;
    // optimistic
    setDevices(prev => prev.map(d => d.mac_address === device.mac_address ? { ...d, nickname: value } : d));
    try {
      await fetch('/api/devices/override', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ mac_address: device.mac_address, nickname: value }),
      });
      const resp = await fetch('/api/devices/all', { headers: { 'Authorization': `Bearer ${token}` } });
      if (resp.ok) setDevices(await resp.json());
    } catch {
      // ignore
    }
  };

  const handleBlockToggle = async (device: NetworkDevice) => {
    if (!token) return;
    const blocked = isDeviceBlocked(device);
    const url = blocked ? '/api/devices/unblock' : '/api/devices/block';
    const body: any = { mac_address: device.mac_address };
    if (device.ip_address && device.ip_address.includes('.')) body.ip_address = device.ip_address;
    // Optimistic UI
    if (blocked) {
      setBlockedV4(prev => prev.filter(ip => ip !== device.ip_address));
      setBlockedMacs(prev => prev.filter(m => m !== device.mac_address.toLowerCase()));
    } else if (body.ip_address) {
      setBlockedV4(prev => Array.from(new Set([...prev, body.ip_address])));
      setBlockedMacs(prev => Array.from(new Set([...prev, device.mac_address.toLowerCase()])));
    }
    try {
      await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      // revert on error
      if (blocked) {
        setBlockedV4(prev => Array.from(new Set([...prev, device.ip_address])));
      } else {
        setBlockedV4(prev => prev.filter(ip => ip !== device.ip_address));
      }
    }
  };

  const filteredDevices = devices.filter((device) => {
    // Search filter
    const matchesSearch = !search || (
      device.hostname?.toLowerCase().includes(search.toLowerCase()) ||
      device.ip_address.includes(search) ||
      device.mac_address.includes(search) ||
      device.vendor?.toLowerCase().includes(search.toLowerCase())
    );
    
    // Status filter
    const matchesStatus = filterStatus === 'all' || 
      (filterStatus === 'online' && device.is_online) ||
      (filterStatus === 'offline' && !device.is_online);
    
    // Type filter
    const matchesType = filterType === 'all' ||
      (filterType === 'dhcp' && device.is_dhcp) ||
      (filterType === 'static' && !device.is_dhcp);
    
    // Network filter
    const matchesNetwork = filterNetwork === 'all' || device.network === filterNetwork;
    
    return matchesSearch && matchesStatus && matchesType && matchesNetwork;
  });

  const onlineCount = devices.filter(d => d.is_online).length;
  const offlineCount = devices.filter(d => !d.is_online).length;

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
        
        <main className="flex-1 overflow-y-auto p-4 md:p-6 bg-gray-50 dark:bg-gray-900">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-4 md:mb-6 gap-3">
            <h1 className="text-2xl md:text-3xl font-bold">Devices</h1>
            <div className="flex gap-2 md:gap-4">
              <Badge color="success" size="sm" className="md:text-base">{onlineCount} Online</Badge>
              <Badge color="gray" size="sm" className="md:text-base">{offlineCount} Offline</Badge>
              <Badge color="info" size="sm" className="md:text-base">{devices.length} Total</Badge>
            </div>
          </div>
          
          <Card>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
              <div>
                <TextInput
                  icon={HiSearch}
                  placeholder="Search..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
              
              <div>
                <Select
                  value={filterStatus}
                  onChange={(e) => setFilterStatus(e.target.value)}
                >
                  <option value="all">All Status</option>
                  <option value="online">Online Only</option>
                  <option value="offline">Offline Only</option>
                </Select>
              </div>
              
              <div>
                <Select
                  value={filterType}
                  onChange={(e) => setFilterType(e.target.value)}
                >
                  <option value="all">All Types</option>
                  <option value="dhcp">DHCP Only</option>
                  <option value="static">Static Only</option>
                </Select>
              </div>
              
              <div>
                <Select
                  value={filterNetwork}
                  onChange={(e) => setFilterNetwork(e.target.value)}
                >
                  <option value="all">All Networks</option>
                  <option value="homelab">HOMELAB</option>
                  <option value="lan">LAN</option>
                </Select>
              </div>
            </div>

            {/* Desktop Table View */}
            <div className="hidden md:block">
              <Table>
                <Table.Head>
                  <Table.HeadCell>Status</Table.HeadCell>
                  <Table.HeadCell>Device</Table.HeadCell>
                  <Table.HeadCell>IP Address</Table.HeadCell>
                  <Table.HeadCell>MAC Address</Table.HeadCell>
                  <Table.HeadCell>Vendor</Table.HeadCell>
                  <Table.HeadCell>Network</Table.HeadCell>
                  <Table.HeadCell>Type</Table.HeadCell>
                  <Table.HeadCell>Last Seen</Table.HeadCell>
                  <Table.HeadCell>Actions</Table.HeadCell>
                </Table.Head>
                <Table.Body className="divide-y">
                  {filteredDevices.map((device) => (
                    <Table.Row key={device.mac_address} className={!device.is_online ? 'opacity-50' : ''}>
                      <Table.Cell>
                        <Badge color={device.is_online ? 'success' : 'gray'} size="sm">
                          {device.is_online ? 'Online' : 'Offline'}
                        </Badge>
                      </Table.Cell>
                      <Table.Cell className="font-medium">
                        <div className="flex items-center gap-2">
                          <button
                            className="text-yellow-500 hover:text-yellow-400"
                            title={device.favorite ? 'Unfavorite' : 'Favorite'}
                            onClick={() => toggleFavorite(device)}
                          >
                            {device.favorite ? '★' : '☆'}
                          </button>
                          <span>{device.nickname || device.hostname || 'Unknown'}</span>
                          <Button size="xs" color="light" onClick={() => editNickname(device)}>Edit</Button>
                        </div>
                      </Table.Cell>
                      <Table.Cell>{device.ip_address}</Table.Cell>
                      <Table.Cell className="font-mono text-sm">
                        {device.mac_address}
                      </Table.Cell>
                      <Table.Cell className="text-sm text-gray-600">
                        {device.vendor || '—'}
                      </Table.Cell>
                      <Table.Cell>
                        <Badge color={device.network === 'homelab' ? 'info' : 'purple'}>
                          {device.network.toUpperCase()}
                        </Badge>
                      </Table.Cell>
                      <Table.Cell>
                        <Badge color={device.is_dhcp ? (device.is_static ? 'success' : 'warning') : 'gray'}>
                          {device.is_static ? 'Static DHCP' : (device.is_dhcp ? 'Dynamic DHCP' : 'Static IP')}
                        </Badge>
                      </Table.Cell>
                      <Table.Cell className="text-sm">
                        {new Date(device.last_seen).toLocaleString()}
                      </Table.Cell>
                      <Table.Cell>
                        <Button
                          size="xs"
                          color={isDeviceBlocked(device) ? 'success' : 'failure'}
                          onClick={() => handleBlockToggle(device)}
                        >
                          {isDeviceBlocked(device) ? 'Enable' : 'Disable'}
                        </Button>
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </Table>
            </div>

            {/* Mobile Card View */}
            <div className="md:hidden space-y-3">
              {filteredDevices.map((device) => (
                <div
                  key={device.mac_address}
                  className={`p-4 rounded-lg border ${
                    device.is_online 
                      ? 'bg-white border-gray-200 dark:bg-gray-800 dark:border-gray-700' 
                      : 'bg-gray-50 border-gray-200 dark:bg-gray-900 dark:border-gray-700 opacity-60'
                  }`}
                >
                  {/* Header Row */}
                  <div className="flex justify-between items-start mb-2">
                    <div className="flex-1">
                      <div className="font-semibold text-lg mb-1">
                        {device.hostname || 'Unknown'}
                      </div>
                      <div className="text-sm text-gray-600 dark:text-gray-400">
                        {device.ip_address}
                      </div>
                    </div>
                    <Badge color={device.is_online ? 'success' : 'gray'} size="sm">
                      {device.is_online ? '● Online' : '○ Offline'}
                    </Badge>
                  </div>

                  {/* Details Grid */}
                  <div className="space-y-2 text-sm">
                    <div className="flex justify-between">
                      <span className="text-gray-500">MAC:</span>
                      <span className="font-mono">{device.mac_address}</span>
                    </div>
                    
                    {device.vendor && (
                      <div className="flex justify-between">
                        <span className="text-gray-500">Vendor:</span>
                        <span className="text-gray-900 dark:text-gray-100">{device.vendor}</span>
                      </div>
                    )}
                    
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">Network:</span>
                      <Badge color={device.network === 'homelab' ? 'info' : 'purple'} size="sm">
                        {device.network.toUpperCase()}
                      </Badge>
                    </div>
                    
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">Nickname:</span>
                      <span className="text-gray-900 dark:text-gray-100">{device.nickname || '—'}</span>
                    </div>
                    
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">Type:</span>
                      <Badge color={device.is_dhcp ? (device.is_static ? 'success' : 'warning') : 'gray'} size="sm">
                        {device.is_static ? 'Static DHCP' : (device.is_dhcp ? 'Dynamic' : 'Static IP')}
                      </Badge>
                    </div>
                    
                    <div className="flex justify-between text-xs text-gray-500 pt-1 border-t border-gray-200 dark:border-gray-700">
                      <span>Last seen:</span>
                      <span>{new Date(device.last_seen).toLocaleString()}</span>
                    </div>
                    <div className="pt-3">
                      <Button
                        size="xs"
                        color={isDeviceBlocked(device) ? 'success' : 'failure'}
                        onClick={() => handleBlockToggle(device)}
                        className="w-full"
                      >
                        {isDeviceBlocked(device) ? 'Enable' : 'Disable'}
                      </Button>
                      <div className="mt-2 flex gap-2">
                        <Button size="xs" color="light" className="flex-1" onClick={() => editNickname(device)}>Edit Nickname</Button>
                        <Button size="xs" color={device.favorite ? 'warning' : 'light'} onClick={() => toggleFavorite(device)}>
                          {device.favorite ? '★ Favorite' : '☆ Favorite'}
                        </Button>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {filteredDevices.length === 0 && (
              <div className="text-center py-8 text-gray-500">
                No devices found matching your filters
              </div>
            )}
            
            <div className="mt-4 text-xs md:text-sm text-gray-500 text-center md:text-left">
              <p>
                Showing {filteredDevices.length} of {devices.length} devices
                <span className="hidden sm:inline">{' • '}Auto-refreshing every 10 seconds</span>
              </p>
            </div>
          </Card>
        </main>
      </div>
    </div>
  );
}

