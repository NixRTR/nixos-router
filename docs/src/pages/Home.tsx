import { Link } from 'react-router-dom';
import { Carousel } from 'flowbite-react';
import { MarkdownContent } from '../components/MarkdownContent';

const homeContent = `# NixOS Router Documentation

Welcome to the NixOS Router documentation. This guide will help you install, configure, and maintain your NixOS-based router.

## Quick Links

- [Installation Guide](/installation) - Get started with installing the router
- [Upgrading Guide](/upgrading) - Learn how to upgrade your router
- [Verification](/verification) - Verify your router is working correctly
- [Configuration](/configuration) - Configure all aspects of your router

## Features

- Multi-network support (isolated LAN segments)
- DHCP server (Kea)
- DNS server (Unbound with ad-blocking)
- Web dashboard for monitoring
- Dynamic DNS updates (Linode)
- Firewall and NAT
- Secrets management via sops-nix

## Getting Started

1. Follow the [Installation Guide](/installation) to set up your router
2. Verify your installation using the [Verification Guide](/verification)
3. Customize your configuration using the [Configuration Guide](/configuration)

## Need Help?

- Check the [GitHub Issues](https://github.com/BeardedTek/nixos-router/issues)
- Review the [GitHub Repository](https://github.com/BeardedTek/nixos-router)
`;

// Screenshot images - add your screenshot files to docs/public/screenshots/
// Vite serves public files from the root, so use root-relative paths
const screenshots = [
  { src: '/screenshots/screenshot1.png', alt: 'Dashboard Overview' },
  { src: '/screenshots/screenshot2.png', alt: 'Network Monitoring' },
  { src: '/screenshots/screenshot3.png', alt: 'Device Management' },
  { src: '/screenshots/screenshot4.png', alt: 'System Metrics' },
];

export function Home() {
  // Filter out screenshots that don't exist (for development)
  // In production, you can remove this check
  const availableScreenshots = screenshots.filter((img) => {
    // For now, we'll show placeholder if images don't exist
    // You can add actual image files to docs/public/screenshots/ later
    return true;
  });

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      {/* Screenshot Carousel */}
      {availableScreenshots.length > 0 && (
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm overflow-hidden">
          <div className="h-64 sm:h-80 xl:h-96">
            <Carousel slideInterval={5000} indicators pauseOnHover>
              {availableScreenshots.map((screenshot, index) => (
                <img
                  key={index}
                  src={screenshot.src}
                  alt={screenshot.alt}
                  className="w-full h-full object-contain"
                  onError={(e) => {
                    // Hide image if it fails to load
                    (e.target as HTMLImageElement).style.display = 'none';
                  }}
                />
              ))}
            </Carousel>
          </div>
        </div>
      )}

      {/* Documentation Content */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={homeContent} />
      </div>
    </div>
  );
}

