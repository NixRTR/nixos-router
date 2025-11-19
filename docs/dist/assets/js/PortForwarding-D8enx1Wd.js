import{j as r}from"./ui-vendor-CtbJYEGA.js";import{M as e}from"./MarkdownContent-CHjPgFnl.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const o=`# Port Forwarding Configuration

Configure port forwarding rules to expose internal services to the internet.

## Port Forward Rules

Add port forwarding rules:

\`\`\`nix
portForwards = [
  {
    name = "web-server";
    protocol = "tcp";
    externalPort = 443;
    internalIP = "192.168.2.10";
    internalPort = 443;
  }
  {
    name = "ssh-server";
    protocol = "tcp";
    externalPort = 2222;
    internalIP = "192.168.2.20";
    internalPort = 22;
  }
];
\`\`\`

## Rule Format

Each port forward rule requires:

- \`name\` - Descriptive name for the rule
- \`protocol\` - "tcp" or "udp"
- \`externalPort\` - Port on the WAN interface
- \`internalIP\` - IP address of the internal service
- \`internalPort\` - Port of the internal service

## Security Considerations

- Only forward ports that are necessary
- Use non-standard external ports when possible
- Ensure internal services are properly secured
- Consider using a VPN instead of port forwarding for remote access
`;function i(){return r.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:r.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:r.jsx(e,{content:o})})})}export{i as PortForwardingConfig};
