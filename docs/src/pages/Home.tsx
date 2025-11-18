import { Link } from 'react-router-dom';
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

export function Home() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={homeContent} />
      </div>
    </div>
  );
}

