import { Link, useLocation } from 'react-router-dom';
import { useState, useEffect } from 'react';
import { FaGithub } from 'react-icons/fa';
import { HiInformationCircle } from 'react-icons/hi';

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ isOpen, onClose }: SidebarProps) {
  const location = useLocation();
  const [githubStats, setGitHubStats] = useState<{ stars: number; forks: number } | null>(null);

  useEffect(() => {
    // Fetch GitHub stats on mount
    const fetchGitHubStats = async () => {
      try {
        const response = await fetch('https://api.github.com/repos/BeardedTek/nixos-router');
        if (response.ok) {
          const data = await response.json();
          setGitHubStats({
            stars: data.stargazers_count || 0,
            forks: data.forks_count || 0,
          });
        } else {
          setGitHubStats({ stars: 0, forks: 0 });
        }
      } catch (error) {
        console.error('Failed to fetch GitHub stats:', error);
        // Set default values if fetch fails
        setGitHubStats({ stars: 0, forks: 0 });
      }
    };
    fetchGitHubStats();
  }, []);

  const menuItems = [
    { path: '/', label: 'Home' },
    { path: '/installation', label: 'Installation' },
    {
      path: '/configuration',
      label: 'Configuration',
      children: [
        { path: '/configuration/system', label: 'System' },
        { path: '/configuration/wan', label: 'WAN' },
        { path: '/configuration/cake', label: 'CAKE' },
        { path: '/configuration/lan-bridges', label: 'LAN Bridges' },
        { path: '/configuration/homelab', label: 'Homelab' },
        { path: '/configuration/lan', label: 'LAN' },
        { path: '/configuration/port-forwarding', label: 'Port Forwarding' },
        { path: '/configuration/dyndns', label: 'Dynamic DNS' },
        { path: '/configuration/global-dns', label: 'Global DNS' },
        { path: '/configuration/webui', label: 'WebUI' },
      ],
    },
    { path: '/upgrading', label: 'Upgrading' },
    { path: '/verification', label: 'Verification' },
    {
      path: '/webui',
      label: 'WebUI',
      children: [
        { path: '/webui', label: 'Overview' },
        { path: '/webui/login', label: 'Login' },
        { path: '/webui/navigation', label: 'Navigation' },
        { path: '/webui/dashboard', label: 'Dashboard' },
        { path: '/webui/network', label: 'Network' },
        { path: '/webui/devices', label: 'Devices' },
        { path: '/webui/device-usage', label: 'Device Usage' },
        { path: '/webui/system', label: 'System' },
        { path: '/webui/speedtest', label: 'Speedtest' },
        { path: '/webui/system-info', label: 'System Info' },
      ],
    },
  ];

  const isActive = (path: string) => location.pathname === path;
  const isParentActive = (path: string, children?: Array<{ path: string }>) => {
    if (isActive(path)) return true;
    if (children) {
      return children.some(child => location.pathname.startsWith(child.path));
    }
    return false;
  };

  return (
    <>
      {/* Overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 bg-gray-900 bg-opacity-50 z-20 lg:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar */}
      <aside
        className={`fixed top-0 left-0 z-30 w-64 h-screen pt-16 transition-transform bg-white border-r border-gray-200 dark:bg-gray-800 dark:border-gray-700 lg:translate-x-0 ${
          isOpen ? 'translate-x-0' : '-translate-x-full'
        } lg:static lg:z-auto`}
      >
        <div className="h-full px-3 py-4 overflow-y-auto">
          <ul className="space-y-2 font-medium">
            {menuItems.map((item) => (
              <li key={item.path}>
                <Link
                  to={item.path}
                  onClick={() => {
                    if (window.innerWidth < 1024) onClose();
                  }}
                  className={`flex items-center p-2 rounded-lg ${
                    isParentActive(item.path, item.children)
                      ? 'text-blue-600 bg-blue-50 dark:text-blue-500 dark:bg-gray-700'
                      : 'text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700'
                  }`}
                >
                  <span className="ml-3">{item.label}</span>
                </Link>
                {item.children && isParentActive(item.path, item.children) && (
                  <ul className="ml-6 mt-2 space-y-1">
                    {item.children.map((child) => (
                      <li key={child.path}>
                        <Link
                          to={child.path}
                          onClick={() => {
                            if (window.innerWidth < 1024) onClose();
                          }}
                          className={`flex items-center p-2 rounded-lg text-sm ${
                            isActive(child.path)
                              ? 'text-blue-600 bg-blue-50 dark:text-blue-500 dark:bg-gray-700'
                              : 'text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700'
                          }`}
                        >
                          {child.label}
                        </Link>
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
          </ul>

          {/* GitHub Links */}
          <div className="pt-4 mt-4 border-t border-gray-200 dark:border-gray-700">
            <ul className="space-y-2 font-medium">
              <li>
                <a
                  href="https://github.com/BeardedTek/nixos-router"
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => {
                    if (window.innerWidth < 1024) onClose();
                  }}
                  className="flex items-center justify-between p-2 rounded-lg text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700"
                >
                  <div className="flex items-center">
                    <FaGithub className="w-5 h-5 mr-3" />
                    <span>GitHub</span>
                  </div>
                  {githubStats !== null && (
                    <span className="ml-2 text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
                      ⭐ {githubStats.stars} 🍴 {githubStats.forks}
                    </span>
                  )}
                </a>
              </li>
              <li>
                <a
                  href="https://github.com/BeardedTek/nixos-router/issues"
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => {
                    if (window.innerWidth < 1024) onClose();
                  }}
                  className="flex items-center p-2 rounded-lg text-gray-900 hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700"
                >
                  <HiInformationCircle className="w-5 h-5 mr-3" />
                  <span>Issues</span>
                </a>
              </li>
            </ul>
          </div>
        </div>
      </aside>
    </>
  );
}

