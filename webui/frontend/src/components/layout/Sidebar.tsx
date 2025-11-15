/**
 * Sidebar navigation with Flowbite
 */
import { Sidebar as FlowbiteSidebar } from 'flowbite-react';
import { Link, useLocation } from 'react-router-dom';
import {
  HiChartPie,
  HiViewBoards,
  HiUsers,
  HiClock,
  HiLogout,
} from 'react-icons/hi';

interface SidebarProps {
  onLogout: () => void;
}

export function Sidebar({ onLogout }: SidebarProps) {
  const location = useLocation();

  return (
    <FlowbiteSidebar aria-label="Sidebar with navigation">
      <FlowbiteSidebar.Items>
        <FlowbiteSidebar.ItemGroup>
          <FlowbiteSidebar.Item
            as={Link}
            to="/dashboard"
            icon={HiChartPie}
            active={location.pathname === '/dashboard'}
          >
            Dashboard
          </FlowbiteSidebar.Item>

          <FlowbiteSidebar.Item
            as={Link}
            to="/network"
            icon={HiViewBoards}
            active={location.pathname === '/network'}
          >
            Network
          </FlowbiteSidebar.Item>

          <FlowbiteSidebar.Item
            as={Link}
            to="/clients"
            icon={HiUsers}
            active={location.pathname === '/clients'}
          >
            DHCP Clients
          </FlowbiteSidebar.Item>

          <FlowbiteSidebar.Item
            as={Link}
            to="/history"
            icon={HiClock}
            active={location.pathname === '/history'}
          >
            History
          </FlowbiteSidebar.Item>
        </FlowbiteSidebar.ItemGroup>

        <FlowbiteSidebar.ItemGroup>
          <FlowbiteSidebar.Item icon={HiLogout} onClick={onLogout}>
            Logout
          </FlowbiteSidebar.Item>
        </FlowbiteSidebar.ItemGroup>
      </FlowbiteSidebar.Items>
    </FlowbiteSidebar>
  );
}

