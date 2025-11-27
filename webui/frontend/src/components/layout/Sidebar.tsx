/**
 * Sidebar navigation with Flowbite - Mobile responsive with hamburger menu
 */
import { useState, useEffect } from 'react';
import { Sidebar as FlowbiteSidebar } from 'flowbite-react';
import { Link, useLocation } from 'react-router-dom';
import {
  HiChartPie,
  HiViewBoards,
  HiUsers,
  HiClock,
  HiLogout,
  HiInformationCircle,
  HiBookOpen,
  HiLightningBolt,
  HiTrendingUp,
  HiBell,
  HiGlobe,
  HiServer,
} from 'react-icons/hi';
import { FaGithub } from 'react-icons/fa';
import { apiClient } from '../../api/client';

interface SidebarProps {
  onLogout: () => void;
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ onLogout, isOpen, onClose }: SidebarProps) {
  const location = useLocation();
  const [githubStats, setGitHubStats] = useState<{ stars: number; forks: number } | null>(null);
  const [cakeEnabled, setCakeEnabled] = useState(false);
  const [appriseEnabled, setAppriseEnabled] = useState(false);

  useEffect(() => {
    // Fetch GitHub stats on mount
    const fetchGitHubStats = async () => {
      try {
        const stats = await apiClient.getGitHubStats();
        setGitHubStats(stats);
      } catch (error) {
        console.error('Failed to fetch GitHub stats:', error);
        // Set default values if fetch fails
        setGitHubStats({ stars: 0, forks: 0 });
      }
    };
    fetchGitHubStats();
  }, []);

  useEffect(() => {
    // Check CAKE status on mount
    const checkCakeStatus = async () => {
      try {
        console.log('Checking CAKE status...');
        const status = await apiClient.getCakeStatus();
        console.log('CAKE status response:', status);
        setCakeEnabled(status.enabled);
      } catch (error) {
        console.error('Failed to check CAKE status:', error);
        console.error('Error details:', error);
        setCakeEnabled(false);
      }
    };
    checkCakeStatus();
    // Re-check every minute
    const interval = setInterval(checkCakeStatus, 60000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    // Check Apprise status on mount
    const checkAppriseStatus = async () => {
      try {
        console.log('Checking Apprise status...');
        const status = await apiClient.getAppriseStatus();
        console.log('Apprise status response:', status);
        setAppriseEnabled(status.enabled);
      } catch (error) {
        console.error('Failed to check Apprise status:', error);
        console.error('Error details:', error);
        setAppriseEnabled(false);
      }
    };
    checkAppriseStatus();
    // Re-check every minute
    const interval = setInterval(checkAppriseStatus, 60000);
    return () => clearInterval(interval);
  }, []);

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

              <FlowbiteSidebar.Item
                as={Link}
                to="/speedtest"
                icon={HiLightningBolt}
                active={location.pathname === '/speedtest'}
                onClick={handleItemClick}
              >
                Speedtest
              </FlowbiteSidebar.Item>

              {appriseEnabled && (
                <FlowbiteSidebar.Item
                  as={Link}
                  to="/notifications"
                  icon={HiBell}
                  active={location.pathname === '/notifications'}
                  onClick={handleItemClick}
                >
                  Notifications
                </FlowbiteSidebar.Item>
              )}

              <FlowbiteSidebar.Item
                as={Link}
                to="/dns"
                icon={HiGlobe}
                active={location.pathname === '/dns'}
                onClick={handleItemClick}
              >
                DNS
              </FlowbiteSidebar.Item>

              <FlowbiteSidebar.Item
                as={Link}
                to="/dhcp"
                icon={HiServer}
                active={location.pathname === '/dhcp'}
                onClick={handleItemClick}
              >
                DHCP
              </FlowbiteSidebar.Item>

              {cakeEnabled && (
                <FlowbiteSidebar.Item
                  as={Link}
                  to="/traffic-shaping"
                  icon={HiTrendingUp}
                  active={location.pathname === '/traffic-shaping'}
                  onClick={handleItemClick}
                >
                  Traffic Shaping
                </FlowbiteSidebar.Item>
              )}
            </FlowbiteSidebar.ItemGroup>

            <FlowbiteSidebar.ItemGroup>
              <FlowbiteSidebar.Item
                as={Link}
                to="/system-info"
                icon={HiInformationCircle}
                active={location.pathname === '/system-info'}
                onClick={handleItemClick}
              >
                System Info
              </FlowbiteSidebar.Item>
              <FlowbiteSidebar.Item 
                icon={HiLogout} 
                style={{ cursor: 'pointer' }}
                onClick={() => {
                  handleItemClick();
                  onLogout();
                }}
              >
                Logout
              </FlowbiteSidebar.Item>
            </FlowbiteSidebar.ItemGroup>

            <FlowbiteSidebar.ItemGroup>
              {/* Documentation */}
              <FlowbiteSidebar.Item
                href="/docs"
                target="_blank"
                rel="noopener noreferrer"
                icon={HiBookOpen}
                as="a"
                onClick={handleItemClick}
              >
                Documentation
              </FlowbiteSidebar.Item>
              {/* GitHub Links */}
              <FlowbiteSidebar.Item
                href="https://github.com/BeardedTek/nixos-router"
                target="_blank"
                rel="noopener noreferrer"
                icon={FaGithub}
                as="a"
              >
                <div className="flex items-center justify-between w-full">
                  <span>GitHub</span>
                  {githubStats !== null && (
                    <span className="ml-2 text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      ⭐ {githubStats.stars} 🍴 {githubStats.forks}
                    </span>
                  )}
                </div>
              </FlowbiteSidebar.Item>
              <FlowbiteSidebar.Item
                href="https://github.com/BeardedTek/nixos-router/issues"
                target="_blank"
                rel="noopener noreferrer"
                icon={HiInformationCircle}
                as="a"
              >
                Issues
              </FlowbiteSidebar.Item>
            </FlowbiteSidebar.ItemGroup>
          </FlowbiteSidebar.Items>
        </FlowbiteSidebar>
      </div>
    </>
  );
}

