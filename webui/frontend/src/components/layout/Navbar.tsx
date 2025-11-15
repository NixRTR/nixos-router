/**
 * Top navbar with Flowbite
 */
import { Navbar as FlowbiteNavbar, Badge } from 'flowbite-react';
import type { ConnectionStatus } from '../../types/metrics';

interface NavbarProps {
  hostname: string;
  username: string;
  connectionStatus: ConnectionStatus;
}

export function Navbar({ hostname, username, connectionStatus }: NavbarProps) {
  const getStatusColor = () => {
    switch (connectionStatus) {
      case 'connected':
        return 'success';
      case 'connecting':
        return 'warning';
      case 'error':
        return 'failure';
      default:
        return 'gray';
    }
  };

  return (
    <FlowbiteNavbar fluid className="border-b">
      <FlowbiteNavbar.Brand>
        <span className="self-center whitespace-nowrap text-xl font-semibold">
          {hostname}
        </span>
      </FlowbiteNavbar.Brand>

      <div className="flex items-center gap-4">
        <Badge color={getStatusColor()}>
          {connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1)}
        </Badge>
        <span className="text-sm">
          Logged in as: <strong>{username}</strong>
        </span>
      </div>
    </FlowbiteNavbar>
  );
}

