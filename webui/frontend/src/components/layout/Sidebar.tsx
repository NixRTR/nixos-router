/**
 * Sidebar navigation with Flowbite - Mobile responsive with hamburger menu
 */
import { Sidebar as FlowbiteSidebar } from 'flowbite-react';
import { Link, useLocation } from 'react-router-dom';
import {
  HiChartPie,
  HiViewBoards,
  HiUsers,
  HiClock,
  HiChartBar,
  HiLogout,
} from 'react-icons/hi';

interface SidebarProps {
  onLogout: () => void;
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ onLogout, isOpen, onClose }: SidebarProps) {
  const location = useLocation();

  const handleItemClick = () => {
    // Close sidebar on mobile when item is clicked
    if (window.innerWidth < 768) {
      onClose();
    }
  };

  return (
    <>
      {/* Mobile Overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar */}
      <div
        className={`
          fixed md:static inset-y-0 left-0 z-50
          transform transition-transform duration-300 ease-in-out
          md:transform-none
          ${isOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'}
        `}
      >
        <FlowbiteSidebar aria-label="Sidebar with navigation" className="h-full">
          <FlowbiteSidebar.Items>
            <FlowbiteSidebar.ItemGroup>
              <FlowbiteSidebar.Item
                as={Link}
                to="/dashboard"
                icon={HiChartPie}
                active={location.pathname === '/dashboard'}
                onClick={handleItemClick}
              >
                Dashboard
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/network"
                icon={HiViewBoards}
                active={location.pathname === '/network'}
                onClick={handleItemClick}
              >
                Network
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/clients"
                icon={HiUsers}
                active={location.pathname === '/clients'}
                onClick={handleItemClick}
              >
                Devices
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/device-usage"
                icon={HiChartBar}
                active={location.pathname === '/device-usage'}
                onClick={handleItemClick}
              >
                Device Usage
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/system"
                icon={HiClock}
                active={location.pathname === '/system'}
                onClick={handleItemClick}
              >
                System
              </FlowbiteSidebar.Item>
            </FlowbiteSidebar.ItemGroup>

            <FlowbiteSidebar.ItemGroup>
              <FlowbiteSidebar.Item 
                icon={HiLogout} 
                onClick={() => {
                  handleItemClick();
                  onLogout();
                }}
              >
                Logout
              </FlowbiteSidebar.Item>
            </FlowbiteSidebar.ItemGroup>
          </FlowbiteSidebar.Items>
        </FlowbiteSidebar>
      </div>
    </>
  );
}

