# Apprise Notifications

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

Apprise service management is integrated into the **Notifications** page in the WebUI, which provides:

- **Service Management**: View, add, edit, and delete notification services with names and descriptions
- **Test Notifications**: Test individual services to verify connectivity
- **Send Notifications**: Send custom notifications to all services or specific ones
- **URL Generator**: Interactive modal tool to generate Apprise URLs for any supported service
- **Service Status**: Real-time status of each configured service

### Database-Based Management

Apprise services are now stored in a PostgreSQL database, making management easier and more flexible:

- **WebUI Management**: Add, edit, and delete services directly from the WebUI
- **Automatic Migration**: Existing services from `secrets/secrets.yaml` are automatically migrated to the database on first startup
- **No Rebuild Required**: Changes take effect immediately without rebuilding the system
- **Service Names**: Each service can have a descriptive name and optional description

## Configuration

### Enable Apprise

In your `router-config.nix`:

```nix
apprise = {
  enable = true;
  port = 8001;  # Internal port (default: 8001)
};
```

### Managing Services via WebUI

1. Navigate to the **Notifications** page in the WebUI sidebar
2. Scroll to the **Configured Services** section
3. Click **New Service** to add a new Apprise service
4. Use the URL Generator modal to create Apprise URLs for supported services
5. Enter a name and optional description for the service
6. Click **Save Service** to add it to your configuration

### Legacy Configuration (Migration)

If you have existing Apprise services configured in `secrets/secrets.yaml`, they will be automatically migrated to the database on first startup. The format in `secrets.yaml` is:

```yaml
apprise-urls: |
  Description|apprise-url-here
  Another Service|another-apprise-url
```

Each line contains a description (optional) and an Apprise URL, separated by a pipe character (`|`). If no description is provided, the service name will be extracted from the URL.

**Note**: After migration, services are managed via the WebUI. Changes to `secrets.yaml` will not affect the database configuration.

## URL Generator

The WebUI includes a built-in URL generator modal that helps you create Apprise URLs for supported services. Access it by clicking **New Service** on the Notifications page. The generator provides:

- **Service Selection**: Dropdown menu with 30+ popular notification services
- **Dynamic Forms**: Service-specific forms that adapt to each service's requirements
- **Email Provider Support**: Special handling for major email providers (Gmail, Yahoo, Outlook, etc.) with app password instructions
- **URL Preview**: Real-time preview of the generated URL
- **Save Service**: Directly save generated URLs with a name and description

### Supported Services in Generator

The URL generator supports many popular services including:

- Email (SMTP with provider-specific configurations)
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

### Email Provider Notes

The URL generator includes special handling for major email providers:

- **Google (Gmail)**: Users with 2-Step Verification must generate an [app password](https://myaccount.google.com/apppasswords)
- **Yahoo**: Users must generate an [app password](https://login.yahoo.com/account/security)
- **Fastmail**: Users must create a custom App password with SMTP permissions

## Using the WebUI

### Accessing Apprise Services

1. Navigate to the **Notifications** page in the WebUI sidebar
2. Scroll to the **Configured Services** section
3. View all configured services with their names and descriptions

### Managing Services

**Add New Service:**
1. Click **New Service** button
2. Use the URL Generator to create an Apprise URL
3. Enter a name and optional description
4. Click **Save Service**

**Edit Service:**
1. Click **Edit** next to a service
2. Modify the name, description, or URL
3. Click **Save**

**Delete Service:**
1. Click **Delete** next to a service
2. Confirm the deletion

### Sending Notifications

**Send to All Services:**
1. Scroll to the **Send Notification** section
2. Enter your message in the "Message Body" field
3. Optionally add a title and select a notification type
4. Click "Send to All Services"

**Send to Specific Service:**
1. Find the service in the configured services list
2. Click "Send" next to that service
3. Enter your message and click "Send"

### Testing Services

To verify a service is working correctly:

1. Find the service in the configured services list
2. Click "Test" next to that service
3. A test notification will be sent to verify connectivity

## API Usage

You can also manage Apprise services and send notifications programmatically via the REST API:

### List Services

```bash
curl -X GET http://router-ip:8080/api/apprise/services \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Create Service

```bash
curl -X POST http://router-ip:8080/api/apprise/services \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Email Alerts",
    "description": "Primary email notification service",
    "url": "mailto://user:password@smtp.gmail.com:587?to=alerts@example.com"
  }'
```

### Update Service

```bash
curl -X PUT http://router-ip:8080/api/apprise/services/1 \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Email Alerts Updated",
    "description": "Updated description"
  }'
```

### Delete Service

```bash
curl -X DELETE http://router-ip:8080/api/apprise/services/1 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Send Notification

```bash
curl -X POST http://router-ip:8080/api/apprise/notify \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Your notification message",
    "title": "Notification Title",
    "notification_type": "info"
  }'
```

### Send to Specific Service

```bash
curl -X POST http://router-ip:8080/api/apprise/services/1/send \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "body": "Your notification message",
    "title": "Notification Title",
    "notification_type": "info"
  }'
```

### Test Service

```bash
curl -X POST http://router-ip:8080/api/apprise/services/1/test \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### API Endpoints

- `GET /api/apprise/status` - Check if Apprise is enabled
- `GET /api/apprise/services` - List all configured services
- `POST /api/apprise/services` - Create a new service
- `GET /api/apprise/services/{service_id}` - Get service details
- `PUT /api/apprise/services/{service_id}` - Update a service
- `DELETE /api/apprise/services/{service_id}` - Delete a service
- `POST /api/apprise/notify` - Send notification to all services
- `POST /api/apprise/services/{service_id}/send` - Send notification to specific service
- `POST /api/apprise/services/{service_id}/test` - Test a specific service

## Common Service Examples

### Email (SMTP)

```
mailto://username:password@smtp.gmail.com:587?to=recipient@example.com
```

### Discord

```
discord://webhook-id/webhook-token
```

### Telegram

```
tgram://bot-token/chat-id
```

### Home Assistant

```
hassio://access-token@homeassistant.local:8123
```

### ntfy

```
# Public topic
ntfy://mytopic

# Private topic with authentication
ntfy://user:password@ntfy.sh/mytopic
```

### Slack

```
slack://token-a/token-b/token-c/#channel
```

## Troubleshooting

### Service Not Working

1. **Check URL Format**: Verify the Apprise URL is correctly formatted
2. **Test Service**: Use the "Test" button in the WebUI to verify connectivity
3. **Check Logs**: Review system logs for error messages:
   ```bash
   journalctl -u router-webui-backend -f
   ```

### Service Not Appearing

1. **Refresh Page**: Services are loaded from the database, try refreshing the page
2. **Check Database**: Verify the service was created successfully
3. **Check Permissions**: Ensure you have proper authentication

### Authentication Errors

- **Email**: Verify SMTP credentials and that "Less secure app access" is enabled (for Gmail) or use app passwords
- **Discord/Slack**: Verify webhook tokens are correct and not expired
- **Telegram**: Ensure bot token and chat ID are correct
- **Home Assistant**: Verify access token has proper permissions

## Security Notes

- Apprise URLs are stored in the PostgreSQL database (encrypted at rest if database encryption is enabled)
- Services can be managed directly from the WebUI without editing configuration files
- Never commit unencrypted secrets to version control
- Use strong passwords and tokens for all services
- Regularly rotate credentials for production services

## Additional Resources

- [Apprise Documentation](https://github.com/caronc/apprise)
- [Apprise Supported Services](https://github.com/caronc/apprise#supported-notifications)
- [Apprise URL Examples](https://github.com/caronc/apprise/wiki)
