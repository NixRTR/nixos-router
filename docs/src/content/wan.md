# WAN Configuration

Configure your WAN (Wide Area Network) interface and connection type.

## Connection Type

The router supports two WAN connection types:

### DHCP

For most home internet connections:

\`\`\`nix
wan = {
  type = "dhcp";
  interface = "eno1";
};
\`\`\`

### PPPoE

For DSL or fiber connections that require PPPoE authentication:

\`\`\`nix
wan = {
  type = "pppoe";
  interface = "eno1";
};
\`\`\`

When using PPPoE, you'll also need to configure credentials in your secrets file (see secrets management).

## Interface Selection

Choose the network interface connected to your internet connection. Common interface names:

- \`eno1\`, \`eno2\` - Onboard Ethernet
- \`enp4s0\`, \`enp5s0\` - PCIe Ethernet cards
- \`eth0\`, \`eth1\` - Legacy naming

Use \`ip link show\` to list available interfaces.

