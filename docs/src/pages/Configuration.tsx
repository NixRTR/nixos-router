import { MarkdownContent } from '../components/MarkdownContent';

const configContent = `# Configuration

This section covers all configuration options for the NixOS Router.

## Configuration Sections

- [System Configuration](/configuration/system) - Basic system settings
- [WAN Configuration](/configuration/wan) - WAN interface and connection settings
- [LAN Bridges](/configuration/lan-bridges) - LAN bridge configuration
- [Homelab Network](/configuration/homelab) - Homelab network settings
- [LAN Network](/configuration/lan) - LAN network settings
- [Port Forwarding](/configuration/port-forwarding) - Port forwarding rules
- [Dynamic DNS](/configuration/dyndns) - Dynamic DNS configuration
- [Global DNS](/configuration/global-dns) - Global DNS settings
- [WebUI](/configuration/webui) - Web dashboard configuration
`;

export function Configuration() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={configContent} />
      </div>
    </div>
  );
}

