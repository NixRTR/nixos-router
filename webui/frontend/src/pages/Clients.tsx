/**
 * DHCP Clients page
 */
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, Table, Badge, TextInput } from 'flowbite-react';
import { HiSearch } from 'react-icons/hi';
import { Sidebar } from '../components/layout/Sidebar';
import { Navbar } from '../components/layout/Navbar';
import { useMetrics } from '../hooks/useMetrics';
import { apiClient } from '../api/client';

export function Clients() {
  const token = localStorage.getItem('access_token');
  const username = localStorage.getItem('username') || 'Unknown';
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  
  const { connectionStatus, dhcpClients } = useMetrics(token);
  
  const handleLogout = async () => {
    await apiClient.logout();
    navigate('/login');
  };

  const filteredClients = dhcpClients.filter((client) =>
    client.hostname?.toLowerCase().includes(search.toLowerCase()) ||
    client.ip_address.includes(search) ||
    client.mac_address.includes(search)
  );

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
          <h1 className="text-3xl font-bold mb-6">DHCP Clients</h1>
          
          <Card>
            <div className="mb-4">
              <TextInput
                icon={HiSearch}
                placeholder="Search by hostname, IP, or MAC..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>

            <Table>
              <Table.Head>
                <Table.HeadCell>Hostname</Table.HeadCell>
                <Table.HeadCell>IP Address</Table.HeadCell>
                <Table.HeadCell>MAC Address</Table.HeadCell>
                <Table.HeadCell>Network</Table.HeadCell>
                <Table.HeadCell>Type</Table.HeadCell>
                <Table.HeadCell>Lease Expires</Table.HeadCell>
              </Table.Head>
              <Table.Body className="divide-y">
                {filteredClients.map((client) => (
                  <Table.Row key={client.ip_address}>
                    <Table.Cell className="font-medium">
                      {client.hostname || 'Unknown'}
                    </Table.Cell>
                    <Table.Cell>{client.ip_address}</Table.Cell>
                    <Table.Cell className="font-mono text-sm">
                      {client.mac_address}
                    </Table.Cell>
                    <Table.Cell>
                      <Badge color={client.network === 'homelab' ? 'info' : 'purple'}>
                        {client.network.toUpperCase()}
                      </Badge>
                    </Table.Cell>
                    <Table.Cell>
                      <Badge color={client.is_static ? 'success' : 'gray'}>
                        {client.is_static ? 'Static' : 'Dynamic'}
                      </Badge>
                    </Table.Cell>
                    <Table.Cell>
                      {client.lease_end
                        ? new Date(client.lease_end).toLocaleString()
                        : 'N/A'}
                    </Table.Cell>
                  </Table.Row>
                ))}
              </Table.Body>
            </Table>

            {filteredClients.length === 0 && (
              <div className="text-center py-8 text-gray-500">
                No clients found
              </div>
            )}
          </Card>
        </main>
      </div>
    </div>
  );
}

