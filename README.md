# NixOS Router

A production-grade, declarative NixOS router configuration with enterprise-level features and optimizations.

## ✨ Highlights

- **🌐 Multi-Network Support** - Isolated LAN segments with selective access control
- **🚀 Performance Optimized** - BBR congestion control, MSS clamping, hardware offloading
- **📊 Full Monitoring** - Grafana dashboard with real-time metrics
- **🔒 Security Hardened** - Encrypted secrets, SYN flood protection, reverse path filtering
- **🔧 Easy Management** - One-command install and updates
- **☁️ Dynamic DNS** - Automatic Linode DNS updates for changing WAN IPs

## 🚀 Quick Start

Boot from NixOS installer ISO and run:

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

The installer will guide you through:
- **Simple mode**: Single network for most users
- **Advanced mode**: Multiple isolated networks (HOMELAB + LAN)

## 📚 Documentation

Complete documentation is available in the [`docs/`](docs/) directory:

- **[Installation Guide](docs/installation.md)** - Install and initial setup
- **[Configuration Guide](docs/configuration.md)** - Configure networks, DHCP, and services
- **[PowerDNS Guide](docs/powerdns.md)** - DNS management and PowerDNS Admin interface
- **[Network Isolation](docs/isolation.md)** - Multi-LAN setup and access control
- **[Monitoring](docs/monitoring.md)** - Grafana dashboard and metrics
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
- **PowerDNS** - Caching resolver + authoritative server with web admin interface
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
