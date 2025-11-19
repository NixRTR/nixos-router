import { Navbar as FlowbiteNavbar, Tooltip } from 'flowbite-react';
import { HiMenu, HiMoon, HiSun } from 'react-icons/hi';
import { Link } from 'react-router-dom';

interface NavbarProps {
  onMenuClick: () => void;
}

export function Navbar({ onMenuClick }: NavbarProps) {
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

  return (
    <FlowbiteNavbar fluid className="border-b">
      <div className="flex items-center gap-3 flex-1">
        {/* Hamburger Menu Button - Only visible when sidebar is hidden (below lg breakpoint) */}
        <button
          onClick={onMenuClick}
          className="p-2 text-gray-500 rounded-lg lg:hidden hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600"
          aria-label="Toggle menu"
        >
          <HiMenu className="w-6 h-6" />
        </button>

        <FlowbiteNavbar.Brand>
          <Link to="/" className="flex items-center gap-2 self-center whitespace-nowrap text-xl font-semibold text-gray-900 dark:text-white">
            {/* NixOS Logo */}
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 128 128"
              className="w-6 h-6 dark:opacity-90 flex-shrink-0"
              preserveAspectRatio="xMidYMid meet"
            >
              <path fill="#7EBAE4" d="M50.732 43.771L20.525 96.428l-7.052-12.033 8.14-14.103-16.167-.042L2 64.237l3.519-6.15 23.013.073 8.27-14.352 13.93-.037zm2.318 42.094l60.409.003-6.827 12.164-16.205-.045 8.047 14.115-3.45 6.01-7.05.008-11.445-20.097-16.483-.034-6.996-12.124zm35.16-23.074l-30.202-52.66L71.888 10l8.063 14.148 8.12-14.072 6.897.002 3.532 6.143-11.57 20.024 8.213 14.386-6.933 12.16z" clipRule="evenodd" fillRule="evenodd" />
              <path fill="#5277C3" d="M39.831 65.463l30.202 52.66-13.88.131-8.063-14.148-8.12 14.072-6.897-.002-3.532-6.143 11.57-20.024-8.213-14.386 6.933-12.16zm35.08-23.207l-60.409-.003L21.33 30.09l16.204.045-8.047-14.115 3.45-6.01 7.051-.01 11.444 20.097 16.484.034 6.996 12.124zm2.357 42.216l30.207-52.658 7.052 12.034-8.141 14.102 16.168.043L126 64.006l-3.519 6.15-23.013-.073-8.27 14.352-13.93.037z" clipRule="evenodd" fillRule="evenodd" />
            </svg>
            <span>NixOS Router</span>
          </Link>
        </FlowbiteNavbar.Brand>

        {/* Tagline - Centered between brand and theme toggle */}
        <div className="hidden md:flex flex-1 justify-center items-center">
          <p className="text-sm md:text-base lg:text-lg text-gray-900 dark:text-white font-medium">
            A deterministic NixOS-based homelab router solution
          </p>
        </div>
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
      </div>
    </FlowbiteNavbar>
  );
}
