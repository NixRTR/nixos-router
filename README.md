# NixOS Router

A production-grade, declarative NixOS router configuration with enterprise-level features and optimizations.

## ✨ Highlights

- **🌐 Multi-Network Support** - Isolated LAN segments with selective access control
- **🚀 Performance Optimized** - BBR congestion control, MSS clamping, hardware offloading
- **📊 Modern Web Dashboard** - Real-time monitoring with React + FastAPI (NEW!)
- **📈 Historical Metrics** - 30 days of bandwidth and system data in PostgreSQL
- **🔒 Security Hardened** - Encrypted secrets, SYN flood protection, reverse path filtering
- **🔧 Easy Management** - One-command install and updates
- **☁️ Dynamic DNS** - Automatic Linode DNS updates for changing WAN IPs

## 🚀 Quick Start

### Option 1: Custom ISO (Recommended)

Build and use our custom installation ISO with automated menu system:

1. **Build the ISO** (from NixOS/NixOS WSL):
   ```bash
   cd iso
   ./build-iso.sh
   ```

2. **Write to USB** and boot from it
3. **(Optional)** Add your `router-config.nix` to the USB's `/config/` directory for automated installation
4. **Select installation option** from the automated menu

The custom ISO includes everything needed for installation (no internet required during install) and supports automated installation with pre-configured `router-config.nix` on the **same USB drive**!

👉 **See [iso/README.md](iso/README.md)** for detailed build and usage instructions  
👉 **On Windows/WSL?** See [iso/BUILD-ON-WSL.md](iso/BUILD-ON-WSL.md) for step-by-step guide

### Option 2: Online Installer

Boot from standard NixOS installer ISO and run:

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

The installer will guide you through:
- **Simple mode**: Single network for most users
- **Advanced mode**: Multiple isolated networks (HOMELAB + LAN)

## 🧩 Modular Architecture

This router is built with a clean modular design. All functionality is organized into focused modules:

- **`router.nix`** - Core networking (WAN, LAN bridges, firewall, NAT)
- **`dns.nix`** - DNS services (Unbound with ad-blocking)
- **`dhcp.nix`** - DHCP server (ISC Kea)
- **`webui.nix`** - **NEW!** Modern web dashboard (FastAPI + React)
- **`dashboard.nix`** - Legacy monitoring (Grafana, Prometheus)
- **`users.nix`** - User account management
- **`secrets.nix`** - Encrypted secrets (sops-nix)
- **`linode-dyndns.nix`** - Dynamic DNS updates

See [`modules/README.md`](modules/README.md) for detailed information about each module.

### Web Dashboard

Access real-time router metrics via beautiful web interface:

```
http://router-ip:8080
```

Features:
- Real-time system metrics (CPU, memory, load, uptime)
- Live bandwidth monitoring per interface
- Service status (Unbound, Kea DHCP, PPPoE)
- DHCP client list with search
- 30 days of historical data and charts
- Mobile-responsive design with dark mode

See [`webui/README.md`](webui/README.md) for full documentation.

## 📚 Documentation

Complete documentation is available in the [`docs/`](docs/) directory:

- **[Installation Guide](docs/installation.md)** - Install and initial setup
- **[Configuration Guide](docs/configuration.md)** - Configure networks, DHCP, and services
- **[DNS Configuration](docs/configuration.md#dns-configuration)** - DNS, local domains, and ad-blocking
- **[Network Isolation](docs/isolation.md)** - Multi-LAN setup and access control
- **[Web Dashboard](docs/configuration.md#web-ui-dashboard)** - Modern React-based monitoring interface
- **[Monitoring](docs/monitoring.md)** - Legacy Grafana dashboard and metrics
- **[Optional Features](docs/optional-features.md)** - Dynamic DNS, VPN, and more
- **[Performance](docs/performance.md)** - Optimization details and tuning
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions
- **[Updating](docs/updating.md)** - Keep your router up to date
- **[Testing in VM](docs/testing.md)** - Test in QEMU before deploying to hardware

## 🏗️ Architecture

```
Internet ──▶ [WAN] ──▶ [Router/Firewall] ──┬──▶ [br0] HOMELAB (192.168.2.0/24)
                                            └──▶ [br1] LAN (192.168.3.0/24)
```

- **Isolated networks** with firewall protection between segments
- **Dual DHCP servers** for automatic IP assignment
- **Unbound DNS** - Recursive resolver with ad-blocking, DNSSEC, and DNS-over-TLS
- **Local domain support** - Wildcard DNS for local services (*.homelab.local)
- **NAT and port forwarding** for external access
- **Real-time monitoring** via Grafana + Prometheus

## 🔒 Security

- Secrets encrypted at rest with Age public-key cryptography
- SYN flood protection and connection rate limiting
- Reverse path filtering (anti-spoofing)
- Automated security updates via declarative configuration

## 📄 License

MIT License - See [LICENSE](LICENSE) for details

## 🤝 Contributing

This is a personal router configuration, but feel free to fork and adapt for your needs!
