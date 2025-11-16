/**
 * Top navbar with Flowbite - Includes hamburger menu for mobile
 */
import { Navbar as FlowbiteNavbar, Badge, Tooltip } from 'flowbite-react';
import { HiMenu, HiMoon, HiSun } from 'react-icons/hi';
import type { ConnectionStatus } from '../../types/metrics';

interface NavbarProps {
  hostname: string;
  username: string;
  connectionStatus: ConnectionStatus;
  onMenuClick?: () => void;
}

export function Navbar({ hostname, username, connectionStatus, onMenuClick }: NavbarProps) {
  const toggleTheme = () => {
    const root = document.documentElement;
    const isDark = root.classList.contains('dark');
    if (isDark) {
      root.classList.remove('dark');
      try { localStorage.setItem('theme', 'light'); } catch {}
    } else {
      root.classList.add('dark');
      try { localStorage.setItem('theme', 'dark'); } catch {}
    }
  };

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
      <div className="flex items-center gap-3">
        {/* Hamburger Menu Button - Only visible on mobile */}
        <button
          onClick={onMenuClick}
          className="p-2 text-gray-500 rounded-lg md:hidden hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600"
          aria-label="Toggle menu"
        >
          <HiMenu className="w-6 h-6" />
        </button>

        <FlowbiteNavbar.Brand>
          <span className="self-center whitespace-nowrap text-xl font-semibold">
            {hostname}
          </span>
        </FlowbiteNavbar.Brand>
      </div>

      <div className="flex items-center gap-2 md:gap-4">
        {/* Theme toggle */}
        <Tooltip content="Toggle theme" placement="bottom">
          <button
            type="button"
            onClick={toggleTheme}
            className="p-2 rounded-lg text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:focus:ring-gray-600"
            aria-label="Toggle theme"
            title="Toggle theme"
          >
            {/* Show sun in dark mode, moon in light mode */}
            <span className="hidden dark:inline-block"><HiSun className="w-5 h-5" /></span>
            <span className="inline-block dark:hidden"><HiMoon className="w-5 h-5" /></span>
          </button>
        </Tooltip>

        <Badge color={getStatusColor()} size="sm" className="md:text-base">
          <span className="hidden sm:inline">{connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1)}</span>
          <span className="sm:hidden">●</span>
        </Badge>
        <span className="text-xs md:text-sm">
          <span className="hidden sm:inline">Logged in as: </span>
          <strong>{username}</strong>
        </span>
      </div>
    </FlowbiteNavbar>
  );
}

