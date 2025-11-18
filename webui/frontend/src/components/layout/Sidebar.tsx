/**
 * Sidebar navigation with Flowbite - Mobile responsive with hamburger menu
 */
import { useState } from 'react';
import { Sidebar as FlowbiteSidebar } from 'flowbite-react';
import { Link, useLocation } from 'react-router-dom';
import {
  HiChartPie,
  HiViewBoards,
  HiUsers,
  HiClock,
  HiLogout,
  HiInformationCircle,
} from 'react-icons/hi';
import { SystemInfoModal } from '../SystemInfoModal';

interface SidebarProps {
  onLogout: () => void;
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ onLogout, isOpen, onClose }: SidebarProps) {
  const location = useLocation();
  const [systemInfoModalOpen, setSystemInfoModalOpen] = useState(false);

  const handleItemClick = () => {
    // Close sidebar when screen is below 1650px when item is clicked
    if (window.innerWidth < 1650) {
      onClose();
    }
  };

  return (
    <>
      {/* Overlay - visible below 1650px */}
      {isOpen && (
        <div
          className="fixed inset-0 bg-black bg-opacity-50 z-40 xl-custom:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar */}
      <div
        className={`
          fixed xl-custom:static inset-y-0 left-0 z-50
          transform transition-transform duration-300 ease-in-out
          xl-custom:transform-none
          ${isOpen ? 'translate-x-0' : '-translate-x-full xl-custom:translate-x-0'}
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
                to="/devices"
                icon={HiUsers}
                active={location.pathname === '/devices'}
                onClick={handleItemClick}
              >
                Devices
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/device-usage"
                icon={HiViewBoards}
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
                icon={HiInformationCircle} 
                className="cursor-pointer"
                onClick={() => {
                  handleItemClick();
                  setSystemInfoModalOpen(true);
                }}
              >
                System Info
              </FlowbiteSidebar.Item>
              <FlowbiteSidebar.Item 
                icon={HiLogout} 
                className="cursor-pointer"
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
      
      {/* System Info Modal */}
      <SystemInfoModal 
        show={systemInfoModalOpen} 
        onClose={() => setSystemInfoModalOpen(false)} 
      />
    </>
  );
}

