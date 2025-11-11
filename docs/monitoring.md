# Monitoring

Your router includes a built-in Grafana dashboard with real-time metrics powered by Prometheus.

## Accessing the Dashboard

### URL

```
http://192.168.2.1:3000
```

Replace `192.168.2.1` with your router's IP address (works from any LAN network).

### First Login

**Default credentials**:
- Username: `admin`
- Password: `admin`

⚠️ **IMPORTANT**: Change the password immediately after first login!

### Changing Password

1. Log in with default credentials
2. Click user icon (bottom left)
3. Select "Profile"
4. Click "Change Password"
5. Save new password

---

## Dashboard Overview

The router dashboard displays real-time metrics in organized panels.

### System Overview Panel

- **CPU Usage**: Current CPU utilization (%)
- **Memory Usage**: RAM consumption
- **System Load**: 1/5/15 minute load averages
- **Uptime**: How long the router has been running
- **Disk Usage**: Storage space on router

### WAN Interface Panel

- **WAN Status**: Interface up/down
- **WAN IP**: Current external IP address
- **WAN Bandwidth**: Upload/download rates
- **WAN Traffic**: Total bytes transferred
- **Connection Status**: Internet connectivity indicator

### LAN Interface Panels

#### HOMELAB (br0)

- **Interface Status**: Bridge up/down
- **IP Address**: Bridge gateway IP
- **Bandwidth**: Real-time traffic graph
- **Connected Devices**: DHCP lease count
- **Traffic Totals**: Bytes in/out

#### LAN (br1)

Same metrics as HOMELAB panel but for the LAN network.

### Network Performance Panel

- **DNS Queries**: Blocky query rate and cache hits
- **DHCP Leases**: Active leases per network
- **Firewall Drops**: Blocked packets (isolation, malicious)
- **NAT Connections**: Active connection count
- **Port Forwards**: Traffic through port forwarding rules

### Service Status Panel

- **Blocky DNS**: Running/stopped
- **Kea DHCP**: Running/stopped
- **Prometheus**: Metrics collection status
- **Grafana**: Dashboard status

---

## Key Metrics Explained

### CPU Usage

- **Normal**: 5-20% average
- **High**: >50% sustained
- **Critical**: >80% sustained

High CPU may indicate:
- High network throughput (normal under load)
- Firewall processing lots of connections
- System updates running
- Attack/DDoS (check firewall drops)

### Memory Usage

- **Normal**: 30-60% used
- **High**: >80% used
- **Critical**: >95% used

Routers rarely use much RAM. High usage may indicate:
- Memory leak in service
- DNS cache very large
- Connection tracking table full

### System Load

Rule of thumb: **load average should be < CPU core count**

If you have 4 cores:
- **Good**: 0.5 - 2.0
- **Moderate**: 2.0 - 4.0
- **High**: > 4.0

### WAN Bandwidth

Real-time upload/download speed in Mbps or Gbps.

**Tips**:
- Peaks indicate large transfers
- Sustained at ISP limit is normal during backups/streaming
- Unexpected high usage may indicate:
  - Background updates
  - Compromised device
  - P2P traffic

### DNS Queries

- **Normal**: 50-500 queries/min (small home network)
- **High**: 1000+ queries/min
- **Cache Hit Rate**: 70-90% is excellent

High queries with low cache hit rate:
- Many unique domains (news aggregator, social media)
- DNS tunneling (potential security issue)

### DHCP Leases

Shows how many devices are currently on each network.

- **HOMELAB**: Servers + IoT devices
- **LAN**: Workstations + mobile devices

Unexpected changes:
- New device connected
- DHCP lease expired and renewed
- Rogue DHCP client

### Firewall Drops

Packets blocked by firewall rules.

- **Low**: 0-100/min (port scans, isolation)
- **Moderate**: 100-1000/min
- **High**: >1000/min (attack or misconfiguration)

Check what's being dropped:

```bash
# On router
sudo dmesg | grep DROP
```

### NAT Connections

Active connections through NAT.

- **Normal**: 100-1000 connections
- **High**: 5000+ connections

Each TCP connection counts:
- Web page load: 10-50 connections
- Video stream: 5-10 connections
- Game: 1-10 connections

High connection count:
- P2P/torrenting (normal)
- DDoS (malicious)
- Misconfigured device (retry storm)

---

## Alerts and Notifications

### Built-in Alerts

Grafana can alert on:
- High CPU usage (>80% for 5min)
- Memory exhaustion (>95%)
- Interface down (WAN or LAN)
- Service failures

### Configuring Alerts

1. Open Grafana dashboard
2. Click panel title → "Edit"
3. Go to "Alert" tab
4. Configure threshold and notification channel

### Notification Channels

Grafana supports:
- **Email**: SMTP server required
- **Slack**: Webhook URL
- **Discord**: Webhook URL
- **Telegram**: Bot token + chat ID
- **Webhook**: Generic HTTP POST

Example (Email):

1. Go to "Alerting" → "Contact points"
2. Add new contact point
3. Select "Email"
4. Configure SMTP server
5. Test notification

---

## Custom Metrics

### Available Metrics

Prometheus scrapes metrics from:
- **Node Exporter**: System metrics (CPU, RAM, disk, network)
- **Blocky**: DNS query metrics
- **Kea Exporter**: DHCP lease metrics

### Querying Metrics

Use Prometheus query language (PromQL).

Examples:

#### Network Bandwidth (br0)

```promql
rate(node_network_receive_bytes_total{device="br0"}[5m])
```

#### DNS Cache Hit Rate

```promql
rate(blocky_cache_hit_count[5m]) / rate(blocky_total_queries[5m])
```

#### Active DHCP Leases

```promql
kea_dhcp4_leases_total{subnet="192.168.2.0/24"}
```

### Creating Custom Panels

1. Click "+" → "Add Panel"
2. Enter PromQL query
3. Customize visualization
4. Set panel title
5. Save dashboard

---

## Performance Analysis

### Identifying Bottlenecks

#### CPU Bottleneck

**Symptoms**:
- CPU usage >80%
- WAN bandwidth below ISP limit
- High system load

**Solutions**:
- Enable hardware offloading (check [Performance](performance.md))
- Reduce firewall rule complexity
- Disable unnecessary services

#### Memory Bottleneck

**Symptoms**:
- Memory usage >90%
- Slow response times
- OOM killer messages in logs

**Solutions**:
- Add more RAM
- Reduce DNS cache size
- Reduce connection tracking table size

#### Network Bottleneck

**Symptoms**:
- WAN bandwidth maxed out
- High latency during transfers
- Packet loss

**Solutions**:
- Enable BBR congestion control (already enabled)
- Check MSS clamping (already enabled)
- Upgrade ISP plan

### Bandwidth Analysis

To see which devices are using bandwidth:

```bash
# On router
sudo iftop -i br0  # HOMELAB traffic
sudo iftop -i br1  # LAN traffic
```

Press `T` to show cumulative totals.

---

## Log Viewing

### System Logs

```bash
# All logs
journalctl -xe

# Follow new logs
journalctl -f

# Service-specific logs
journalctl -u blocky
journalctl -u kea-dhcp4-server
journalctl -u grafana
```

### Service Logs

#### Blocky (DNS)

```bash
journalctl -u blocky -f
```

Watch for:
- Query patterns
- Upstream failures
- Cache performance

#### Kea (DHCP)

```bash
journalctl -u kea-dhcp4-server -f
```

Watch for:
- Lease assignments
- DHCP DISCOVER/OFFER/REQUEST/ACK
- Declined leases (IP conflict)

#### Firewall

```bash
# Blocked packets
sudo dmesg | grep DROP

# Connection tracking
sudo conntrack -L | wc -l  # Connection count
```

---

## Dashboard Customization

### Adding Panels

You can add custom panels for specific use cases.

#### Example: Temperature Monitoring

If your router has temperature sensors:

1. Add panel
2. Query: `node_hwmon_temp_celsius`
3. Set alert at 80°C
4. Visualization: Gauge

#### Example: Specific Device Monitoring

Track bandwidth for a specific IP:

1. Add panel
2. Query:
   ```promql
   rate(node_network_receive_bytes_total{device="br0"}[5m])
   ```
3. Filter by source IP (requires netflow, not included)

### Organizing Panels

- Drag panels to rearrange
- Resize panels by dragging corners
- Create rows to group related panels
- Collapse rows when not needed

### Dashboard Variables

Create template variables for dynamic dashboards:

1. Settings (gear icon) → "Variables"
2. Add variable (e.g., `network` = `br0, br1`)
3. Use in queries: `device="$network"`

---

## Backup and Restore

### Export Dashboard

1. Settings (gear icon) → "JSON Model"
2. Copy JSON or save to file
3. Store safely

### Import Dashboard

1. "+" → "Import"
2. Paste JSON or upload file
3. Select data source (Prometheus)
4. Import

**Tip**: Dashboard is stored in NixOS configuration and persists across rebuilds.

---

## Prometheus Configuration

### Retention

By default, Prometheus keeps metrics for **15 days**.

To change retention:

Edit `/etc/nixos/configuration.nix`:

```nix
services.prometheus = {
  # ...
  retentionTime = "30d";  # Keep 30 days
};
```

Apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

### Scrape Interval

Default: **15 seconds**

For less frequent updates (reduce CPU):

```nix
services.prometheus = {
  # ...
  globalConfig.scrape_interval = "60s";
};
```

---

## External Access (Optional)

⚠️ **Security Warning**: Exposing Grafana to the Internet is risky!

### Port Forward (Not Recommended)

If you must:

1. Change admin password to strong passphrase
2. Add port forward in `router-config.nix`:
   ```nix
   portForwards = [
     {
       proto = "tcp";
       externalPort = 3000;
       destination = "192.168.2.1";  # Router IP
       destinationPort = 3000;
     }
   ];
   ```
3. Apply configuration

### VPN Access (Recommended)

Instead of exposing Grafana:

1. Set up VPN (see [Optional Features](optional-features.md))
2. Connect via VPN
3. Access dashboard on LAN IP

---

## Troubleshooting

### Can't Access Dashboard

1. **Check Grafana service**:
   ```bash
   systemctl status grafana
   ```

2. **Check firewall**:
   ```bash
   sudo iptables -L INPUT -v -n | grep 3000
   ```

3. **Check port binding**:
   ```bash
   sudo ss -tlnp | grep 3000
   ```

4. **Restart Grafana**:
   ```bash
   sudo systemctl restart grafana
   ```

### No Data in Panels

1. **Check Prometheus**:
   ```bash
   systemctl status prometheus
   ```

2. **Check data source** (Grafana UI):
   - Settings → Data Sources → Prometheus
   - Click "Test" button

3. **Check node exporter**:
   ```bash
   curl http://localhost:9100/metrics
   ```

### Dashboard Shows Errors

1. **Reload page** (Ctrl+Shift+R)
2. **Check browser console** (F12)
3. **Check Grafana logs**:
   ```bash
   journalctl -u grafana -n 50
   ```

---

## Best Practices

1. **Check daily**: Glance at dashboard once a day
2. **Set up alerts**: Get notified of issues automatically
3. **Baseline metrics**: Know what's "normal" for your network
4. **Investigate spikes**: Don't ignore unusual patterns
5. **Regular backups**: Export dashboard configuration monthly

---

## Next Steps

- **[Performance](performance.md)** - Optimize router performance
- **[Troubleshooting](troubleshooting.md)** - Fix common issues
- **[Optional Features](optional-features.md)** - Add more monitoring


