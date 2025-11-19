import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as o}from"./MarkdownContent-CHjPgFnl.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const r=`# Homelab Network Configuration

Configure the homelab network (typically br0, 192.168.2.x).

## DHCP Configuration

Configure DHCP for the homelab network:

\`\`\`nix
homelab = {
  dhcp = {
    enable = true;
    rangeStart = "192.168.2.100";
    rangeEnd = "192.168.2.200";
    leaseTime = 86400;  # 24 hours
  };
};
\`\`\`

## DNS Configuration

Configure DNS for the homelab network:

\`\`\`nix
homelab = {
  dns = {
    enable = true;
    domain = "homelab.local";
    blockAds = true;
  };
};
\`\`\`

## IP Address

Set the router's IP address on this network:

\`\`\`nix
homelab = {
  ipAddress = "192.168.2.1";
};
\`\`\`
`;function s(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(o,{content:r})})})}export{s as HomelabConfig};
