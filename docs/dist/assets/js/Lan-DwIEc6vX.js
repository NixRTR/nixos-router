import{j as n}from"./ui-vendor-CtbJYEGA.js";import{M as r}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const e=`# LAN Network Configuration

Configure the LAN network (typically br1, 192.168.3.x).

## DHCP Configuration

Configure DHCP for the LAN network:

\`\`\`nix
lan = {
  dhcp = {
    enable = true;
    rangeStart = "192.168.3.100";
    rangeEnd = "192.168.3.200";
    leaseTime = 86400;  # 24 hours
  };
};
\`\`\`

## DNS Configuration

Configure DNS for the LAN network:

\`\`\`nix
lan = {
  dns = {
    enable = true;
    domain = "lan.local";
    blockAds = true;
  };
};
\`\`\`

## IP Address

Set the router's IP address on this network:

\`\`\`nix
lan = {
  ipAddress = "192.168.3.1";
};
\`\`\`
`;function s(){return n.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:n.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:n.jsx(r,{content:e})})})}export{s as LanConfig};
