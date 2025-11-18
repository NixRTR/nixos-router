# LAN Network Configuration

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

