import { MarkdownContent } from '../../components/MarkdownContent';

const appriseContent = `# Apprise Notifications

Apprise integration provides a flexible notification system for your router, allowing you to send alerts and messages to a wide variety of notification services.

## Overview

The Apprise integration uses the [Apprise library](https://github.com/caronc/apprise) to support 80+ notification services including:

- **Email** (SMTP, Gmail, Outlook, etc.)
- **Messaging** (Discord, Slack, Telegram, Matrix, etc.)
- **Push Notifications** (ntfy, Pushover, Pushbullet, etc.)
- **Home Automation** (Home Assistant, IFTTT, etc.)
- **Cloud Services** (AWS SNS, Google Chat, Microsoft Teams, etc.)
- **And many more...**

## Features

### WebUI Integration

The Apprise page in the WebUI provides:

- **Service Management**: View all configured notification services with descriptions
- **Test Notifications**: Test individual services to verify connectivity
- **Send Notifications**: Send custom notifications to all services or specific ones
- **URL Generator**: Interactive tool to generate Apprise URLs for any supported service
- **Service Status**: Real-time status of each configured service

### Flexible Configuration

- **Multiple Services**: Configure as many notification services as you need
- **Custom Descriptions**: Add descriptive names for each service to easily identify them
- **Service-Specific Sending**: Send notifications to individual services or all at once
- **Notification Types**: Support for info, success, warning, and failure notification types

## Configuration

### Enable Apprise

In your \`router-config.nix\`:

\`\`\`nix
apprise = {
  enable = true;
  port = 8001;  # Internal port (default: 8001)
};
\`\`\`

### Configure Services

Apprise services are configured in \`secrets/secrets.yaml\` using the \`apprise-urls\` secret. The format is:

\`\`\`yaml
apprise-urls: |
  Description|apprise-url-here
  Another Service|another-apprise-url
\`\`\`

Each line contains a description (optional) and an Apprise URL, separated by a pipe character (\`|\`). If no description is provided, the service name will be extracted from the URL.

### Editing Secrets

To edit your secrets file:

\`\`\`bash
sops secrets/secrets.yaml
\`\`\`

Add your Apprise URLs in the format shown above. For example:

\`\`\`yaml
apprise-urls: |
  Email Alerts|mailto://user:password@smtp.gmail.com:587?to=alerts@example.com
  Discord Notifications|discord://webhook-id/webhook-token
  Home Assistant|hassio://access-token@homeassistant.local:8123
  Telegram Bot|tgram://bot-token/chat-id
  ntfy Public|ntfy://mytopic
  ntfy Private|ntfy://user:password@ntfy.sh/mytopic
\`\`\`

After editing, rebuild your system:

\`\`\`bash
sudo nixos-rebuild switch
\`\`\`

## URL Generator

The WebUI includes a built-in URL generator that helps you create Apprise URLs for supported services. The generator provides:

- **Service Selection**: Dropdown menu with 30+ popular notification services
- **Dynamic Forms**: Service-specific forms that adapt to each service's requirements
- **URL Preview**: Real-time preview of the generated URL
- **Copy to Clipboard**: Easy copying of generated URLs

### Supported Services in Generator

The URL generator supports many popular services including:

- Email (SMTP)
- Home Assistant
- Discord
- Slack
- Telegram
- ntfy
- Pushover
- Pushbullet
- Matrix
- Rocket.Chat
- Microsoft Teams
- Google Chat
- And many more...

For a complete list of all supported Apprise services, see the [Apprise documentation](https://github.com/caronc/apprise#supported-notifications).

## Using the WebUI

### Accessing Apprise

1. Navigate to the **Apprise** page in the WebUI sidebar
2. View all configured services with their descriptions
3. Use the URL generator to create new service URLs

### Sending Notifications

**Send to All Services:**

1. Enter your message in the "Message Body" field
2. Optionally add a title and select a notification type
3. Click "Send to All Services"

**Send to Specific Service:**

1. Enter your message
2. Find the service in the list
3. Click "Send" next to that service

### Testing Services

To verify a service is working correctly:

1. Find the service in the configured services list
2. Click "Test" next to that service
3. A test notification will be sent to verify connectivity

## API Usage

You can also send notifications programmatically via the REST API:

\`\`\`bash
curl -X POST http://router-ip:8080/api/apprise/notify \\
  -H "Authorization: Bearer YOUR_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "body": "Your notification message",
    "title": "Notification Title",
    "notification_type": "info"
  }'
\`\`\`

### API Endpoints

- \`GET /api/apprise/status\` - Check if Apprise is enabled
- \`GET /api/apprise/services\` - List all configured services
- \`POST /api/apprise/notify\` - Send notification to all services
- \`POST /api/apprise/notify/{service_index}\` - Send notification to specific service
- \`POST /api/apprise/test/{service_index}\` - Test a specific service

## Common Service Examples

### Email (SMTP)

\`\`\`
mailto://username:password@smtp.gmail.com:587?to=recipient@example.com
\`\`\`

### Discord

\`\`\`
discord://webhook-id/webhook-token
\`\`\`

### Telegram

\`\`\`
tgram://bot-token/chat-id
\`\`\`

### Home Assistant

\`\`\`
hassio://access-token@homeassistant.local:8123
\`\`\`

### ntfy

\`\`\`
# Public topic
ntfy://mytopic

# Private topic with authentication
ntfy://user:password@ntfy.sh/mytopic
\`\`\`

### Slack

\`\`\`
slack://token-a/token-b/token-c/#channel
\`\`\`

## Troubleshooting

### Service Not Working

1. **Check URL Format**: Verify the Apprise URL is correctly formatted
2. **Test Service**: Use the "Test" button in the WebUI to verify connectivity
3. **Check Logs**: Review system logs for error messages:
   \`\`\`bash
   journalctl -u router-webui-backend -f
   \`\`\`

### Service Not Appearing

1. **Verify Secret**: Ensure the service URL is correctly added to \`secrets/secrets.yaml\`
2. **Rebuild System**: After editing secrets, rebuild with \`sudo nixos-rebuild switch\`
3. **Check Format**: Ensure the URL follows the \`description|url\` format

### Authentication Errors

- **Email**: Verify SMTP credentials and that "Less secure app access" is enabled (for Gmail)
- **Discord/Slack**: Verify webhook tokens are correct and not expired
- **Telegram**: Ensure bot token and chat ID are correct
- **Home Assistant**: Verify access token has proper permissions

## Security Notes

- All Apprise URLs are stored encrypted in \`secrets/secrets.yaml\` using sops-nix
- Never commit unencrypted secrets to version control
- Use strong passwords and tokens for all services
- Regularly rotate credentials for production services

## Additional Resources

- [Apprise Documentation](https://github.com/caronc/apprise)
- [Apprise Supported Services](https://github.com/caronc/apprise#supported-notifications)
- [Apprise URL Examples](https://github.com/caronc/apprise/wiki)
`;

export function Apprise() {
  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6">
        <MarkdownContent content={appriseContent} />
      </div>
    </div>
  );
}

