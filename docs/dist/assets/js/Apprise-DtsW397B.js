import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as s}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const r=`# Apprise Configuration

Configure the Apprise notification service for your router.

## Basic Settings

\`\`\`nix
apprise = {
  enable = true;
  port = 8001;  # Internal port (default: 8001)
};
\`\`\`

## Configuration Options

- \`enable\` - Enable/disable the Apprise notification service
- \`port\` - Internal port for apprise-api (default: 8001, separate from webui)

## Service Configuration

Apprise services are configured in \`secrets/secrets.yaml\` using the \`apprise-urls\` secret. This allows you to configure any number of notification services.

### Format

\`\`\`yaml
apprise-urls: |
  Description|apprise-url-here
  Another Service|another-apprise-url
\`\`\`

Each line contains:
- **Description** (optional): A human-readable name for the service, separated by a pipe character (\`|\`)
- **URL**: The Apprise URL for the notification service

If no description is provided, the service name will be automatically extracted from the URL.

### Editing Secrets

To add or modify Apprise services:

\`\`\`bash
sops secrets/secrets.yaml
\`\`\`

Add your Apprise URLs in the format shown above. After editing, rebuild your system:

\`\`\`bash
sudo nixos-rebuild switch
\`\`\`

## Example Configurations

### Email (SMTP)

\`\`\`yaml
apprise-urls: |
  Email Alerts|mailto://user:password@smtp.gmail.com:587?to=alerts@example.com
\`\`\`

### Discord

\`\`\`yaml
apprise-urls: |
  Discord Notifications|discord://webhook-id/webhook-token
\`\`\`

### Telegram

\`\`\`yaml
apprise-urls: |
  Telegram Bot|tgram://bot-token/chat-id
\`\`\`

### Home Assistant

\`\`\`yaml
apprise-urls: |
  Home Assistant|hassio://access-token@homeassistant.local:8123
\`\`\`

### ntfy

\`\`\`yaml
apprise-urls: |
  ntfy Public|ntfy://mytopic
  ntfy Private|ntfy://user:password@ntfy.sh/mytopic
\`\`\`

### Multiple Services

You can configure multiple services on separate lines:

\`\`\`yaml
apprise-urls: |
  Email Alerts|mailto://user:pass@smtp:587?to=alerts@example.com
  Discord|discord://webhook-id/webhook-token
  Telegram|tgram://bot-token/chat-id
  Home Assistant|hassio://token@ha.local:8123
\`\`\`

## URL Generator

The WebUI includes a built-in URL generator that helps you create Apprise URLs for supported services. Access it from the Apprise page in the WebUI.

## Supported Services

Apprise supports 80+ notification services. For a complete list and URL formats, see:

- [Apprise Supported Services](https://github.com/caronc/apprise#supported-notifications)
- [Apprise URL Examples](https://github.com/caronc/apprise/wiki)

## Security

- All Apprise URLs are stored encrypted in \`secrets/secrets.yaml\` using sops-nix
- Never commit unencrypted secrets to version control
- Use strong passwords and tokens for all services
- Regularly rotate credentials for production services

## Troubleshooting

### Service Not Working

1. Verify the Apprise URL format is correct
2. Check service credentials and tokens
3. Review system logs: \`journalctl -u router-webui-backend -f\`

### Service Not Appearing

1. Ensure the service URL is correctly added to \`secrets/secrets.yaml\`
2. Rebuild the system after editing secrets
3. Verify the URL follows the \`description|url\` format
`;function n(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(s,{content:r})})})}export{n as AppriseConfig};
