# Testing Scripts

Quick reference for testing the NixOS router in a VM.

## Testing Approaches

This repository supports two testing approaches:

1. **Linux Testing** (`tests/linux/`) - Uses QEMU in WSL2 or native Linux
2. **Windows Testing** (`tests/windows/`) - Uses Hyper-V on Windows natively

Choose the approach that best fits your development environment.

---

## Linux Testing (WSL2/QEMU)

### Prerequisites

- WSL2 on Windows (or native Linux)
- QEMU installed (`sudo apt install qemu-system-x86`)
- VNC viewer on Windows (optional but recommended)
- `wget` for automatic ISO downloads (usually pre-installed)

### Directory Structure

```
tests/linux/
├── files/                      # Downloaded ISOs (gitignored)
│   ├── nixos-minimal.iso
│   └── alpine-virt-*.iso
├── *.qcow2                     # VM disks (gitignored)
├── test-vm-qemu.sh             # Main router VM manager
├── test-client-vm.sh           # Test client VMs
├── test-router.sh              # Automated tests
├── quick-test.sh               # One-command setup
└── README.md                   # This file
```

## Quick Start

### 1. Make Scripts Executable

```bash
cd /mnt/c/Users/YourName/github/nixos-router/tests/linux
chmod +x test-vm-qemu.sh test-client-vm.sh test-router.sh quick-test.sh
```

### 2. Setup and Start Router VM

```bash
./test-vm-qemu.sh
```

Follow the menu:
1. Setup (installs QEMU, automatically downloads NixOS ISO)
2. Create VM disk
3. Start VM (installer)

**Note**: The scripts will automatically download required ISOs when needed.

### 3. Install Router

Connect to VM via VNC (`localhost:5900`) or use the serial console.

In the VM:

```bash
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

**Recommended test config:**
- WAN: `ens3` (DHCP)
- Simple Mode: Bridge `ens4 ens5 ens6 ens7` → `br0` (192.168.1.1)
- Advanced Mode: 
  - HOMELAB: `ens4 ens5` → `br0` (192.168.2.1)
  - LAN: `ens6 ens7` → `br1` (192.168.3.1)

Reboot after installation, then select option 4 (Boot from disk).

### 4. Test Router

```bash
./test-router.sh
```

This runs automated tests:
- SSH connectivity
- Service status (DNS, DHCP, Grafana, etc.)
- Network interfaces
- Internet connectivity
- Firewall/NAT
- Performance optimizations
- Network isolation (if enabled)

### 5. Test with Client VMs

**Simple Mode:**
```bash
# Start client on LAN
./test-client-vm.sh client1 8001
```

**Advanced Mode:**
```bash
# HOMELAB clients
./test-client-vm.sh homelab1 8001  # br0
./test-client-vm.sh homelab2 8002  # br0

# LAN clients  
./test-client-vm.sh lan1 8003      # br1
./test-client-vm.sh lan2 8004      # br1
```

Access clients via VNC:
- client1/homelab1: `localhost:5901`
- homelab2/lan1: `localhost:5902`
- lan2: `localhost:5903`

In each client VM:
```bash
# Login as 'root' (no password)
setup-interfaces
# Choose eth0, DHCP
rc-service networking start
ip addr show eth0
ping <router-ip>
```

## Access Router

- **SSH**: `ssh -p 2222 routeradmin@localhost`
- **Grafana**: `http://localhost:3000` (admin/admin)
- **Serial console**: Available in terminal where VM is running

## Scripts

### test-vm-qemu.sh

Interactive menu for managing router VM:
- Setup dependencies
- Create/delete VM disk
- Start VM (installer or boot from disk)

**Router VM has 5 NICs:**
- `ens3` = WAN (internet via NAT)
- `ens4-ens7` = LAN ports (socket networking on ports 8001-8004)

**Port forwards to Windows/WSL2:**
- SSH: `localhost:2222` → VM:22
- Grafana: `localhost:3000` → VM:3000

### test-client-vm.sh

Creates Alpine Linux test client VM.

**Usage:**
```bash
./test-client-vm.sh <name> <lan-port>
```

**Examples:**
```bash
./test-client-vm.sh client1 8001    # Connect to router port 8001
./test-client-vm.sh homelab1 8002   # Connect to router port 8002
```

### test-router.sh

Automated testing script. Runs 10 tests on the router:

1. SSH connectivity
2. System services
3. Network interfaces
4. DNS resolution
5. Internet connectivity
6. Grafana dashboard
7. Firewall/NAT
8. DHCP configuration
9. Performance optimizations
10. Network isolation (multi-LAN only)

**Usage:**
```bash
./test-router.sh [ssh-port]

# Default: SSH on port 2222
./test-router.sh

# Custom SSH port
./test-router.sh 2223
```

## Troubleshooting

### Can't connect to VNC

- Install VNC viewer on Windows (TightVNC, RealVNC, etc.)
- Connect to `localhost:5900` (or `127.0.0.1:5900`)
- Make sure VM is running

### VM is slow

- Normal in WSL2 without KVM acceleration
- Reduce memory/CPUs in `test-vm-qemu.sh`
- Use serial console instead of VNC

### Port forwarding doesn't work

- Check VM is running: `ps aux | grep qemu`
- Verify port forwards in QEMU command
- Check WSL2 port forwarding to Windows

### Client can't connect

- Start router VM first
- Verify LAN port number (8001-8004)
- Check router bridges are up: `ssh -p 2222 routeradmin@localhost ip link show br0`

## Cleanup

Stop all VMs:
```bash
pkill qemu-system-x86_64
```

Remove test disks:
```bash
rm *.qcow2
```

Keep ISOs for next test (or delete to save space):
```bash
rm files/nixos-minimal.iso files/alpine-virt-*.iso
```

## Full Documentation

See [docs/testing.md](../docs/testing.md) for complete Linux testing guide.

---

## Windows Testing (Hyper-V)

### Prerequisites

- Windows 10/11 Pro, Enterprise, or Education
- Hyper-V enabled
- PowerShell 5.1 or later
- At least 8GB RAM available for VMs

### Directory Structure

```
tests/windows/
├── ISOs/                       # Downloaded ISOs (gitignored)
│   └── nixos-minimal.iso
├── VMs/                        # VM storage (gitignored)
├── Setup-HyperV.ps1            # Initial setup
├── Test-RouterVM.ps1           # Main router VM manager
├── Test-ClientVM.ps1           # Test client VMs
├── Test-Router.ps1             # Automated tests
├── Cleanup-TestEnvironment.ps1 # Cleanup script
└── README.md                   # Windows testing guide
```

### Quick Start

1. **Enable Hyper-V and Setup** (run as Administrator):
   ```powershell
   cd tests\windows
   .\Setup-HyperV.ps1
   ```
   
   This will enable Hyper-V, create virtual switches, and offer to download the NixOS ISO automatically.

2. **Create Router VM**:
   ```powershell
   .\Test-RouterVM.ps1 -Action Create
   ```
   
   If the ISO wasn't downloaded yet, the script will offer to download it.

3. **Start Router VM**:
   ```powershell
   .\Test-RouterVM.ps1 -Action Start
   ```

4. **Run Automated Tests**:
   ```powershell
   .\Test-Router.ps1
   ```

See `tests/windows/README.md` for detailed Windows testing instructions.

## Full Documentation

See [docs/testing.md](../docs/testing.md) for complete testing guide.

