import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as r}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const n=`# Apprise Notifications\r
\r
Apprise integration provides a flexible notification system for your router, allowing you to send alerts and messages to a wide variety of notification services.\r
\r
## Overview\r
\r
The Apprise integration uses the [Apprise library](https://github.com/caronc/apprise) to support 80+ notification services including:\r
\r
- **Email** (SMTP, Gmail, Outlook, etc.)\r
- **Messaging** (Discord, Slack, Telegram, Matrix, etc.)\r
- **Push Notifications** (ntfy, Pushover, Pushbullet, etc.)\r
- **Home Automation** (Home Assistant, IFTTT, etc.)\r
- **Cloud Services** (AWS SNS, Google Chat, Microsoft Teams, etc.)\r
- **And many more...**\r
\r
## Features\r
\r
### WebUI Integration\r
\r
Apprise service management is integrated into the **Notifications** page in the WebUI, which provides:\r
\r
- **Service Management**: View, add, edit, and delete notification services with names and descriptions\r
- **Test Notifications**: Test individual services to verify connectivity\r
- **Send Notifications**: Send custom notifications to all services or specific ones\r
- **URL Generator**: Interactive modal tool to generate Apprise URLs for any supported service\r
- **Service Status**: Real-time status of each configured service\r
\r
### Database-Based Management\r
\r
Apprise services are now stored in a PostgreSQL database, making management easier and more flexible:\r
\r
- **WebUI Management**: Add, edit, and delete services directly from the WebUI\r
- **Automatic Migration**: Existing services from \`secrets/secrets.yaml\` are automatically migrated to the database on first startup\r
- **No Rebuild Required**: Changes take effect immediately without rebuilding the system\r
- **Service Names**: Each service can have a descriptive name and optional description\r
\r
## Configuration\r
\r
### Enable Apprise\r
\r
In your \`router-config.nix\`:\r
\r
\`\`\`nix\r
apprise = {\r
  enable = true;\r
  port = 8001;  # Internal port (default: 8001)\r
};\r
\`\`\`\r
\r
### Managing Services via WebUI\r
\r
1. Navigate to the **Notifications** page in the WebUI sidebar\r
2. Scroll to the **Configured Services** section\r
3. Click **New Service** to add a new Apprise service\r
4. Use the URL Generator modal to create Apprise URLs for supported services\r
5. Enter a name and optional description for the service\r
6. Click **Save Service** to add it to your configuration\r
\r
### Legacy Configuration (Migration)\r
\r
If you have existing Apprise services configured in \`secrets/secrets.yaml\`, they will be automatically migrated to the database on first startup. The format in \`secrets.yaml\` is:\r
\r
\`\`\`yaml\r
apprise-urls: |\r
  Description|apprise-url-here\r
  Another Service|another-apprise-url\r
\`\`\`\r
\r
Each line contains a description (optional) and an Apprise URL, separated by a pipe character (\`|\`). If no description is provided, the service name will be extracted from the URL.\r
\r
**Note**: After migration, services are managed via the WebUI. Changes to \`secrets.yaml\` will not affect the database configuration.\r
\r
## URL Generator\r
\r
The WebUI includes a built-in URL generator modal that helps you create Apprise URLs for supported services. Access it by clicking **New Service** on the Notifications page. The generator provides:\r
\r
- **Service Selection**: Dropdown menu with 30+ popular notification services\r
- **Dynamic Forms**: Service-specific forms that adapt to each service's requirements\r
- **Email Provider Support**: Special handling for major email providers (Gmail, Yahoo, Outlook, etc.) with app password instructions\r
- **URL Preview**: Real-time preview of the generated URL\r
- **Save Service**: Directly save generated URLs with a name and description\r
\r
### Supported Services in Generator\r
\r
The URL generator supports many popular services including:\r
\r
- Email (SMTP with provider-specific configurations)\r
- Home Assistant\r
- Discord\r
- Slack\r
- Telegram\r
- ntfy\r
- Pushover\r
- Pushbullet\r
- Matrix\r
- Rocket.Chat\r
- Microsoft Teams\r
- Google Chat\r
- And many more...\r
\r
For a complete list of all supported Apprise services, see the [Apprise documentation](https://github.com/caronc/apprise#supported-notifications).\r
\r
### Email Provider Notes\r
\r
The URL generator includes special handling for major email providers:\r
\r
- **Google (Gmail)**: Users with 2-Step Verification must generate an [app password](https://myaccount.google.com/apppasswords)\r
- **Yahoo**: Users must generate an [app password](https://login.yahoo.com/account/security)\r
- **Fastmail**: Users must create a custom App password with SMTP permissions\r
\r
## Using the WebUI\r
\r
### Accessing Apprise Services\r
\r
1. Navigate to the **Notifications** page in the WebUI sidebar\r
2. Scroll to the **Configured Services** section\r
3. View all configured services with their names and descriptions\r
\r
### Managing Services\r
\r
**Add New Service:**\r
1. Click **New Service** button\r
2. Use the URL Generator to create an Apprise URL\r
3. Enter a name and optional description\r
4. Click **Save Service**\r
\r
**Edit Service:**\r
1. Click **Edit** next to a service\r
2. Modify the name, description, or URL\r
3. Click **Save**\r
\r
**Delete Service:**\r
1. Click **Delete** next to a service\r
2. Confirm the deletion\r
\r
### Sending Notifications\r
\r
**Send to All Services:**\r
1. Scroll to the **Send Notification** section\r
2. Enter your message in the "Message Body" field\r
3. Optionally add a title and select a notification type\r
4. Click "Send to All Services"\r
\r
**Send to Specific Service:**\r
1. Find the service in the configured services list\r
2. Click "Send" next to that service\r
3. Enter your message and click "Send"\r
\r
### Testing Services\r
\r
To verify a service is working correctly:\r
\r
1. Find the service in the configured services list\r
2. Click "Test" next to that service\r
3. A test notification will be sent to verify connectivity\r
\r
## API Usage\r
\r
You can also manage Apprise services and send notifications programmatically via the REST API:\r
\r
### List Services\r
\r
\`\`\`bash\r
curl -X GET http://router-ip:8080/api/apprise/services \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Create Service\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/apprise/services \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "name": "Email Alerts",\r
    "description": "Primary email notification service",\r
    "url": "mailto://user:password@smtp.gmail.com:587?to=alerts@example.com"\r
  }'\r
\`\`\`\r
\r
### Update Service\r
\r
\`\`\`bash\r
curl -X PUT http://router-ip:8080/api/apprise/services/1 \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "name": "Email Alerts Updated",\r
    "description": "Updated description"\r
  }'\r
\`\`\`\r
\r
### Delete Service\r
\r
\`\`\`bash\r
curl -X DELETE http://router-ip:8080/api/apprise/services/1 \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### Send Notification\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/apprise/notify \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "body": "Your notification message",\r
    "title": "Notification Title",\r
    "notification_type": "info"\r
  }'\r
\`\`\`\r
\r
### Send to Specific Service\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/apprise/services/1/send \\\r
  -H "Authorization: Bearer YOUR_TOKEN" \\\r
  -H "Content-Type: application/json" \\\r
  -d '{\r
    "body": "Your notification message",\r
    "title": "Notification Title",\r
    "notification_type": "info"\r
  }'\r
\`\`\`\r
\r
### Test Service\r
\r
\`\`\`bash\r
curl -X POST http://router-ip:8080/api/apprise/services/1/test \\\r
  -H "Authorization: Bearer YOUR_TOKEN"\r
\`\`\`\r
\r
### API Endpoints\r
\r
- \`GET /api/apprise/status\` - Check if Apprise is enabled\r
- \`GET /api/apprise/services\` - List all configured services\r
- \`POST /api/apprise/services\` - Create a new service\r
- \`GET /api/apprise/services/{service_id}\` - Get service details\r
- \`PUT /api/apprise/services/{service_id}\` - Update a service\r
- \`DELETE /api/apprise/services/{service_id}\` - Delete a service\r
- \`POST /api/apprise/notify\` - Send notification to all services\r
- \`POST /api/apprise/services/{service_id}/send\` - Send notification to specific service\r
- \`POST /api/apprise/services/{service_id}/test\` - Test a specific service\r
\r
## Common Service Examples\r
\r
### Email (SMTP)\r
\r
\`\`\`\r
mailto://username:password@smtp.gmail.com:587?to=recipient@example.com\r
\`\`\`\r
\r
### Discord\r
\r
\`\`\`\r
discord://webhook-id/webhook-token\r
\`\`\`\r
\r
### Telegram\r
\r
\`\`\`\r
tgram://bot-token/chat-id\r
\`\`\`\r
\r
### Home Assistant\r
\r
\`\`\`\r
hassio://access-token@homeassistant.local:8123\r
\`\`\`\r
\r
### ntfy\r
\r
\`\`\`\r
# Public topic\r
ntfy://mytopic\r
\r
# Private topic with authentication\r
ntfy://user:password@ntfy.sh/mytopic\r
\`\`\`\r
\r
### Slack\r
\r
\`\`\`\r
slack://token-a/token-b/token-c/#channel\r
\`\`\`\r
\r
## Troubleshooting\r
\r
### Service Not Working\r
\r
1. **Check URL Format**: Verify the Apprise URL is correctly formatted\r
2. **Test Service**: Use the "Test" button in the WebUI to verify connectivity\r
3. **Check Logs**: Review system logs for error messages:\r
   \`\`\`bash\r
   journalctl -u router-webui-backend -f\r
   \`\`\`\r
\r
### Service Not Appearing\r
\r
1. **Refresh Page**: Services are loaded from the database, try refreshing the page\r
2. **Check Database**: Verify the service was created successfully\r
3. **Check Permissions**: Ensure you have proper authentication\r
\r
### Authentication Errors\r
\r
- **Email**: Verify SMTP credentials and that "Less secure app access" is enabled (for Gmail) or use app passwords\r
- **Discord/Slack**: Verify webhook tokens are correct and not expired\r
- **Telegram**: Ensure bot token and chat ID are correct\r
- **Home Assistant**: Verify access token has proper permissions\r
\r
## Security Notes\r
\r
- Apprise URLs are stored in the PostgreSQL database (encrypted at rest if database encryption is enabled)\r
- Services can be managed directly from the WebUI without editing configuration files\r
- Never commit unencrypted secrets to version control\r
- Use strong passwords and tokens for all services\r
- Regularly rotate credentials for production services\r
\r
## Additional Resources\r
\r
- [Apprise Documentation](https://github.com/caronc/apprise)\r
- [Apprise Supported Services](https://github.com/caronc/apprise#supported-notifications)\r
- [Apprise URL Examples](https://github.com/caronc/apprise/wiki)\r
`;function o(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(r,{content:n})})})}export{o as Apprise};
