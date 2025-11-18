# WebUI Configuration

Configure the web dashboard for monitoring your router.

## Basic Settings

\`\`\`nix
webui = {
  enable = true;
  port = 8080;
  collectionInterval = 2;  # seconds
  retentionDays = 30;
};
\`\`\`

## Configuration Options

- \`enable\` - Enable/disable the WebUI
- \`port\` - Port to serve the WebUI on (default: 8080)
- \`collectionInterval\` - How often to collect metrics (in seconds)
- \`retentionDays\` - How many days of historical data to keep

## Access

Access the WebUI at:

\`\`\`
http://router-ip:8080
\`\`\`

## Features

The WebUI provides:

- Real-time system metrics (CPU, memory, load)
- Network interface statistics
- Device usage and bandwidth tracking
- Service status monitoring
- Historical data visualization

## Authentication

The WebUI uses system user authentication (PAM). Log in with your router admin credentials.

