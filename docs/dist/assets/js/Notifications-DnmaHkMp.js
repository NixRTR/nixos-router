import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const r=`# Notifications

The Notifications page allows you to create automated alert rules based on monitored system parameters. When thresholds are exceeded for a specified duration, notifications are automatically sent to your configured Apprise services.

## Overview

The notification system provides:

- **Automated Monitoring**: Continuously monitor system metrics, network interfaces, temperatures, services, and disk usage
- **Configurable Thresholds**: Set INFO, WARNING, and FAILURE thresholds for each parameter
- **Duration-Based Alerts**: Only trigger notifications when thresholds are exceeded for a specified duration
- **Cooldown Periods**: Prevent notification spam with configurable cooldown periods
- **Jinja2 Templates**: Customize notification messages with template variables
- **Multiple Services**: Send notifications to multiple Apprise services simultaneously
- **Notification History**: View history of all sent notifications

## Accessing Notifications

1. Navigate to the **Notifications** page in the WebUI sidebar
2. View all configured notification rules
3. Create, edit, or delete rules as needed

## Creating a Notification Rule

### Step 1: Basic Information

- **Name**: Give your rule a descriptive name (e.g., "High CPU Alert")
- **Enabled**: Toggle to enable/disable the rule

### Step 2: Select Parameter

Choose the parameter you want to monitor:

#### System Parameters
- **CPU Usage**: Monitor CPU utilization percentage
- **Memory Usage**: Monitor memory utilization percentage
- **Load Average (1m, 5m, 15m)**: Monitor system load averages

#### Network Parameters
- **Interface RX Throughput**: Monitor inbound bandwidth for a specific interface
- **Interface TX Throughput**: Monitor outbound bandwidth for a specific interface
- **Interface RX Errors**: Monitor receive errors per second
- **Interface TX Errors**: Monitor transmit errors per second

*Note: Network parameters require selecting an interface name (e.g., eth0, eno1)*

#### Temperature Parameters
- **Temperature Sensor**: Monitor temperature for a specific sensor

*Note: Temperature parameters require selecting a sensor name (e.g., cpu_thermal, nvme0)*

#### Service Parameters
- **Service Active State**: Monitor if a systemd service is active (1 = active, 0 = inactive)
- **Service Enabled State**: Monitor if a systemd service is enabled (1 = enabled, 0 = disabled)

*Note: Service parameters require selecting a service name (e.g., router-webui-backend, nginx)*

#### Disk Parameters
- **Disk Usage**: Monitor disk usage percentage for a mountpoint

*Note: Disk parameters require selecting a mountpoint (e.g., /, /var)*

### Step 3: Configure Thresholds

Set thresholds for three severity levels:

- **INFO**: Lowest severity threshold (optional)
- **WARNING**: Medium severity threshold (optional)
- **FAILURE**: Highest severity threshold (optional)

**Comparison Operator**:
- **Greater than (>=)**: Trigger when value is greater than or equal to threshold
- **Less than (<=)**: Trigger when value is less than or equal to threshold

*Note: At least one threshold must be set*

### Step 4: Timing Configuration

- **Duration**: How long the threshold must be exceeded before triggering (in seconds)
  - Example: If set to 60 seconds, the value must exceed the threshold for 60 seconds continuously before a notification is sent
- **Cooldown**: Minimum time between notifications for this rule (in seconds)
  - Example: If set to 300 seconds (5 minutes), notifications will only be sent once every 5 minutes even if the threshold continues to be exceeded

### Step 5: Select Apprise Services

Choose which Apprise services should receive notifications for this rule:

- Check the boxes next to the services you want to use
- You can select multiple services
- Services must be configured in your Apprise configuration first

### Step 6: Message Template

Create a custom notification message using Jinja2 templating:

**Default Template**:
\`\`\`
{{ parameter_name }} is {{ current_value }} ({{ current_level | upper }})
\`\`\`

**Available Variables**:

All templates include these base variables:
- \`parameter_name\` - Name of the parameter being monitored
- \`current_value\` - Current metric value
- \`threshold_info\` - INFO threshold value
- \`threshold_warning\` - WARNING threshold value
- \`threshold_failure\` - FAILURE threshold value
- \`current_level\` - Current alert level (info, warning, failure)
- \`timestamp\` - When the check occurred

**Parameter-Specific Variables**:

- **Interface parameters**: \`interface\`, \`rx_rate_mbps\` (or \`tx_rate_mbps\`), \`rx_errors_per_sec\` (or \`tx_errors_per_sec\`)
- **Temperature parameters**: \`sensor_name\`, \`temperature_c\`
- **Service parameters**: \`service_name\`, \`service_active\` (or \`service_enabled\`)
- **Disk parameters**: \`mountpoint\`, \`disk_usage_percent\`

**Example Templates**:

\`\`\`
CPU usage is {{ current_value }}% ({{ current_level | upper }})
Threshold: {{ threshold_warning }}%
\`\`\`

\`\`\`
⚠️ High CPU Alert
CPU: {{ current_value }}%
Level: {{ current_level | upper }}
Time: {{ timestamp.strftime('%Y-%m-%d %H:%M:%S') }}
\`\`\`

\`\`\`
Interface {{ interface }} has high RX throughput: {{ rx_rate_mbps }} Mbps
Threshold: {{ threshold_warning }} Mbps
\`\`\`

\`\`\`
🌡️ Temperature Alert
Sensor: {{ sensor_name }}
Temperature: {{ temperature_c }}°C
Level: {{ current_level | upper }}
\`\`\`

## Managing Rules

### Viewing Rules

The notifications page displays all rules in a table showing:
- Rule name
- Parameter being monitored
- Current status (normal, info, warning, failure)
- Last notification time
- Enabled/disabled status

### Editing Rules

1. Click **Edit** next to a rule
2. Modify any settings as needed
3. Click **Save** to update the rule

### Testing Rules

1. Click **Test** next to a rule
2. The system will immediately evaluate the rule and send a test notification
3. Check your configured Apprise services to verify the notification was received

### Viewing History

1. Click **History** next to a rule
2. View all past notifications sent for that rule
3. See the level, value, message, and success status for each notification

### Enabling/Disabling Rules

- Toggle the **Enabled** switch in the rules table to enable or disable a rule
- Disabled rules are not evaluated by the background worker

### Deleting Rules

1. Click **Delete** next to a rule
2. Confirm the deletion
3. The rule and all its history will be permanently removed

## How It Works

### Background Evaluation

A background worker task runs continuously (default: every 30 seconds) to:

1. Load all enabled notification rules from the database
2. Fetch current metric values for each rule's parameter
3. Evaluate thresholds to determine the current alert level
4. Check if the threshold has been exceeded for the required duration
5. Verify that the cooldown period has elapsed since the last notification
6. Render the Jinja2 template with current values
7. Send notifications to selected Apprise services
8. Record the notification in history

### State Tracking

The system tracks state for each rule:

- **Current Level**: The highest threshold level currently exceeded
- **Threshold Exceeded At**: When the threshold was first exceeded
- **Last Notification At**: When the last notification was sent
- **Last Notification Level**: The level of the last notification sent

### Notification Flow

1. **Normal State**: Value is below all thresholds → No action
2. **Threshold Exceeded**: Value exceeds a threshold → Start duration timer
3. **Duration Met**: Threshold exceeded for required duration → Check cooldown
4. **Cooldown Elapsed**: Enough time has passed since last notification → Send notification
5. **Notification Sent**: Record in history and update state

## Best Practices

### Threshold Configuration

- **Start Conservative**: Set thresholds higher initially and adjust based on your system's normal behavior
- **Use Multiple Levels**: Configure INFO, WARNING, and FAILURE to get early warnings before critical issues
- **Consider Normal Variations**: Account for normal spikes (e.g., backup jobs, updates)

### Duration Settings

- **Short Durations (30-60s)**: For critical alerts that need immediate attention
- **Medium Durations (2-5 min)**: For warnings that should persist before alerting
- **Long Durations (10+ min)**: For trends that need to be sustained before alerting

### Cooldown Settings

- **Short Cooldowns (1-5 min)**: For critical alerts where you want frequent updates
- **Medium Cooldowns (15-30 min)**: For warnings where periodic updates are sufficient
- **Long Cooldowns (1+ hour)**: For informational alerts that don't need frequent updates

### Message Templates

- **Be Descriptive**: Include enough context to understand the alert without checking the WebUI
- **Include Values**: Show the current value and threshold for quick reference
- **Use Formatting**: Use emojis or formatting to make alerts more readable
- **Add Timestamps**: Include timestamps for better context

### Service Selection

- **Critical Alerts**: Send to multiple services (e.g., email + Discord) for redundancy
- **Warning Alerts**: Send to a single primary service
- **Info Alerts**: Send to a less intrusive service (e.g., a dedicated channel)

## Troubleshooting

### Notifications Not Sending

1. **Check Rule Status**: Verify the rule is enabled
2. **Verify Thresholds**: Ensure at least one threshold is set
3. **Check Duration**: The threshold must be exceeded for the full duration
4. **Verify Cooldown**: Ensure enough time has passed since the last notification
5. **Check Apprise Services**: Verify Apprise services are configured and working
6. **Review Logs**: Check system logs for errors:
   \`\`\`bash
   journalctl -u router-webui-backend -f
   \`\`\`

### Incorrect Values

1. **Check Parameter Config**: Verify interface names, sensor names, service names, or mountpoints are correct
2. **Verify Parameter Type**: Ensure the parameter type matches what you want to monitor
3. **Check Data Collection**: Verify the metric is being collected (check the relevant WebUI page)

### Template Errors

1. **Check Syntax**: Verify Jinja2 template syntax is correct
2. **Verify Variables**: Ensure you're using variables available for the parameter type
3. **Test Template**: Use the test button to verify template rendering

### Too Many Notifications

1. **Increase Cooldown**: Set a longer cooldown period
2. **Adjust Thresholds**: Raise thresholds to reduce false positives
3. **Increase Duration**: Require thresholds to be exceeded longer before alerting

## API Usage

You can also manage notification rules programmatically via the REST API:

### List Rules

\`\`\`bash
curl -X GET http://router-ip:8080/api/notifications/rules \\
  -H "Authorization: Bearer YOUR_TOKEN"
\`\`\`

### Create Rule

\`\`\`bash
curl -X POST http://router-ip:8080/api/notifications/rules \\
  -H "Authorization: Bearer YOUR_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "High CPU Alert",
    "enabled": true,
    "parameter_type": "cpu_percent",
    "parameter_config": {},
    "threshold_info": 50.0,
    "threshold_warning": 75.0,
    "threshold_failure": 90.0,
    "comparison_operator": "gt",
    "duration_seconds": 60,
    "cooldown_seconds": 300,
    "apprise_service_indices": [0, 1],
    "message_template": "CPU usage is {{ current_value }}% ({{ current_level | upper }})"
  }'
\`\`\`

### Test Rule

\`\`\`bash
curl -X POST http://router-ip:8080/api/notifications/rules/1/test \\
  -H "Authorization: Bearer YOUR_TOKEN"
\`\`\`

### Get History

\`\`\`bash
curl -X GET http://router-ip:8080/api/notifications/rules/1/history?limit=50 \\
  -H "Authorization: Bearer YOUR_TOKEN"
\`\`\`

## Additional Resources

- [Apprise Documentation](/webui/apprise) - Learn about configuring Apprise services
- [Jinja2 Template Documentation](https://jinja.palletsprojects.com/) - Learn about Jinja2 templating syntax
`;function n(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:r})})})}export{n as Notifications};
