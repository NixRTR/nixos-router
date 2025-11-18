# System Configuration

System configuration covers basic settings for your router.

## Hostname

Set the hostname of your router:

\`\`\`nix
hostname = "nixos-router";
\`\`\`

## Domain

Set the domain for DNS search:

\`\`\`nix
domain = "example.com";
\`\`\`

## Timezone

Configure the timezone:

\`\`\`nix
timezone = "America/Anchorage";
\`\`\`

## Username

Set the admin username:

\`\`\`nix
username = "routeradmin";
\`\`\`

## Nameservers

Configure nameservers for the router itself (used in /etc/resolv.conf):

\`\`\`nix
nameservers = [ "1.1.1.1" "9.9.9.9" "192.168.3.33" ];
\`\`\`

## SSH Keys

Add SSH authorized keys for the router admin user:

\`\`\`nix
sshKeys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbG... user@hostname"
];
\`\`\`

