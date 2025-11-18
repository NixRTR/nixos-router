import { MarkdownContent } from '../../components/MarkdownContent';

const lanBridgesContent = `# LAN Bridges Configuration

Configure LAN (Local Area Network) bridges for your internal networks.

## Bridge Configuration

Bridges allow you to combine multiple physical interfaces into a single logical network:

\`\`\`nix
lan = {
  bridges = [
    {
      name = "br0";
      interfaces = [ "enp4s0" "enp5s0" ];
      ipv4 = {
        address = "192.168.2.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
    {
      name = "br1";
      interfaces = [ "enp6s0" "enp7s0" ];
      ipv4 = {
        address = "192.168.3.1";
        prefixLength = 24;
      };
      ipv6.enable = false;
    }
  ];
};
\`\`\`

## Network Isolation

Enable isolation to block traffic between bridges:

\`\`\`nix
lan = {
  isolation = true;
};
\`\`\`

## Isolation Exceptions

Allow specific devices to access other networks:

\`\`\`nix
isolationExceptions = [
  {
    source = "192.168.3.10";
    sourceBridge = "br1";
    destBridge = "br0";
  }
];
\`\`\`
`;

export function LanBridgesConfig() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={lanBridgesContent} />
      </div>
    </div>
  );
}
