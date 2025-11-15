# Router WebUI - Quick Start Guide

## 🚀 Get Running in 5 Minutes

### Step 1: Enable WebUI

Add to `configuration.nix`:

```nix
imports = [ ./modules/webui.nix ];

services.router-webui.enable = true;
networking.firewall.allowedTCPPorts = [ 8080 ];
```

### Step 2: Deploy

```bash
sudo nixos-rebuild switch
```

### Step 3: Access

```
http://192.168.2.1:8080
```

Login with your system username/password.

## 📱 What You'll See

### Dashboard
- **CPU Usage:** Real-time percentage with color-coded progress bar
- **Memory Usage:** Current usage with GB breakdown
- **Load Average:** 1min, 5min, 15min system load
- **Uptime:** Days, hours, minutes since last boot
- **Network Interfaces:** Live bandwidth for WAN, HOMELAB, LAN
- **Services Status:** Unbound, Kea DHCP, PPPoE connection

### Network Page
- **Real-time Charts:** Last 2 minutes of bandwidth data
- **Interface Selector:** Switch between WAN/HOMELAB/LAN
- **Upload/Download:** Separate lines showing traffic patterns

### Clients Page
- **DHCP Leases:** All connected devices
- **Search:** Filter by hostname, IP, or MAC
- **Details:** Lease expiration, network assignment, static/dynamic

## 🎨 Key Features

✅ **Updates every 2 seconds**
✅ **No page refresh needed**
✅ **Mobile-responsive**
✅ **Dark mode support**
✅ **Real-time connection status**

## 🔧 Development Mode

### Backend (port 8080):
```bash
cd webui/backend
pip install -r requirements.txt
export DATABASE_URL="postgresql+asyncpg://router_webui@localhost/router_webui"
uvicorn main:app --reload
```

### Frontend (port 3000):
```bash
cd webui/frontend
npm install
npm run dev
```

Visit: `http://localhost:3000`

## 📚 More Info

- **Full Documentation:** See `webui/README.md`
- **Deployment Guide:** See `webui/DEPLOYMENT.md`
- **Implementation Details:** See `webui/IMPLEMENTATION_SUMMARY.md`

## ⚡ Quick Tips

**Connection Lost?**
- WebSocket reconnects automatically
- Check the status badge in top-right

**Slow Performance?**
- Increase collection interval in `configuration.nix`
- Set `services.router-webui.collectionInterval = 5;`

**Need HTTPS?**
- Set up Nginx reverse proxy
- See DEPLOYMENT.md for configuration

## 🆘 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't login | Use system username/password |
| No data showing | Wait 2 seconds for first update |
| WebSocket errors | Check firewall allows port 8080 |
| Service won't start | Check logs: `journalctl -u router-webui-backend` |

## 🎯 What's Next?

**Stage 2 (Coming Soon):**
- Edit DHCP settings via UI
- Modify DNS records
- Manage firewall rules
- Live nixos-rebuild progress

For now, enjoy Stage 1 - **Complete real-time monitoring!** 🎉

