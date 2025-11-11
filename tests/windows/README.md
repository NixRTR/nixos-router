# Windows Testing with Hyper-V

Native Windows testing for the NixOS router using Hyper-V virtualization.

## Prerequisites

- **Windows 10/11 Pro, Enterprise, or Education** (Hyper-V not available on Home editions)
- **Hyper-V** feature enabled
- **PowerShell 5.1** or later (included in Windows)
- **At least 8GB RAM** available for VMs
- **Administrator privileges** for Hyper-V management

## Quick Start

### 1. Enable Hyper-V and Setup Environment

Open PowerShell as Administrator:

```powershell
cd tests\windows
.\Setup-HyperV.ps1
```

This script will:
- Check and enable Hyper-V (requires reboot if not already enabled)
- Create virtual switches for testing
- Create directories for ISOs and VMs
- Offer to download NixOS ISO automatically

**If Hyper-V was just enabled, reboot and run the script again.**

### 2. Download NixOS ISO (Optional - Auto-downloads if needed)

The scripts will automatically offer to download the NixOS ISO when needed. Alternatively, you can download it manually:
- URL: https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso
- Save to: `tests\windows\ISOs\nixos-minimal.iso`

### 3. Create Router VM

```powershell
.\Test-RouterVM.ps1 -Action Create
```

This creates a VM with:
- **Memory**: 4GB
- **Processors**: 4 cores
- **Disk**: 20GB (dynamic)
- **Network**: 1 WAN + 4 LAN adapters

### 4. Start Router VM

```powershell
.\Test-RouterVM.ps1 -Action Start
```

### 5. Install Router in VM

Connect to the VM console:

```powershell
.\Test-RouterVM.ps1 -Action Connect
```

Or open **Hyper-V Manager** and connect to `NixOS-Router-Test`.

In the VM console:

```bash
# Download and run installer
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

**Recommended test configuration:**
- **Disk**: `/dev/sda` (or `/dev/vda`)
- **WAN interface**: First detected interface (auto-configured via DHCP)
- **Simple Mode**: Bridge remaining interfaces → `br0` (192.168.1.1)
- **Advanced Mode**: 
  - HOMELAB: 2 interfaces → `br0` (192.168.2.1)
  - LAN: 2 interfaces → `br1` (192.168.3.1)

After installation, reboot the VM.

### 6. Test Router

```powershell
.\Test-Router.ps1
```

This runs automated tests:
- Network connectivity
- SSH access
- System services (DNS, DHCP, Grafana, etc.)
- Network interfaces
- Internet connectivity
- Firewall/NAT configuration
- Performance optimizations
- Network isolation (if enabled)

### 7. Create Test Client VMs (Optional)

Test DHCP and network connectivity with client VMs:

**Simple Mode:**
```powershell
.\Test-ClientVM.ps1 -Name "Client1" -LANSwitch "NixOS-Router-LAN1" -Action Create
.\Test-ClientVM.ps1 -Name "Client1" -Action Start
.\Test-ClientVM.ps1 -Name "Client1" -Action Connect
```

**Advanced Mode:**
```powershell
# HOMELAB clients (br0)
.\Test-ClientVM.ps1 -Name "Homelab1" -LANSwitch "NixOS-Router-LAN1" -Action Create
.\Test-ClientVM.ps1 -Name "Homelab2" -LANSwitch "NixOS-Router-LAN2" -Action Create

# LAN clients (br1)
.\Test-ClientVM.ps1 -Name "LAN1" -LANSwitch "NixOS-Router-LAN3" -Action Create
.\Test-ClientVM.ps1 -Name "LAN2" -LANSwitch "NixOS-Router-LAN4" -Action Create

# Start all clients
.\Test-ClientVM.ps1 -Name "Homelab1" -Action Start
.\Test-ClientVM.ps1 -Name "Homelab2" -Action Start
.\Test-ClientVM.ps1 -Name "LAN1" -Action Start
.\Test-ClientVM.ps1 -Name "LAN2" -Action Start
```

**Note**: Client VMs require Alpine Linux ISO. The script will offer to download it automatically, or you can download manually:
- URL: https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso
- Save to: `tests\windows\ISOs\alpine-virt.iso`

---

## PowerShell Scripts

### Setup-HyperV.ps1

**Purpose**: Initial setup and environment check

**Usage**:
```powershell
.\Setup-HyperV.ps1
```

**What it does**:
- Checks Windows version
- Enables Hyper-V (if not already enabled)
- Creates virtual switches:
  - WAN: Uses Default Switch or external switch
  - LAN1-4: Internal switches for testing
- Creates directories for ISOs and VMs
- Checks for required ISOs

### Test-RouterVM.ps1

**Purpose**: Manage router VM lifecycle

**Usage**:
```powershell
.\Test-RouterVM.ps1 -Action <Create|Start|Stop|Delete|Status|Connect>
```

**Actions**:
- **Create**: Create new router VM
- **Start**: Start the VM
- **Stop**: Stop the VM
- **Delete**: Delete VM and disk (asks for confirmation)
- **Status**: Show VM status and configuration
- **Connect**: Open VM console

**Examples**:
```powershell
# Create VM
.\Test-RouterVM.ps1 -Action Create

# Start VM
.\Test-RouterVM.ps1 -Action Start

# Check status
.\Test-RouterVM.ps1 -Action Status

# Connect to console
.\Test-RouterVM.ps1 -Action Connect

# Stop VM
.\Test-RouterVM.ps1 -Action Stop

# Delete VM
.\Test-RouterVM.ps1 -Action Delete
```

### Test-ClientVM.ps1

**Purpose**: Create and manage test client VMs

**Usage**:
```powershell
.\Test-ClientVM.ps1 -Name <name> -LANSwitch <switch> -Action <action>
```

**Parameters**:
- `-Name`: Client VM name (e.g., "Client1", "Homelab1")
- `-LANSwitch`: LAN switch to connect to:
  - `NixOS-Router-LAN1`
  - `NixOS-Router-LAN2`
  - `NixOS-Router-LAN3`
  - `NixOS-Router-LAN4`
- `-Action`: `Create`, `Start`, `Stop`, `Delete`, `Status`, `Connect`

**Examples**:
```powershell
# Create client on LAN1
.\Test-ClientVM.ps1 -Name "Client1" -LANSwitch "NixOS-Router-LAN1" -Action Create

# Start client
.\Test-ClientVM.ps1 -Name "Client1" -Action Start

# Connect to client console
.\Test-ClientVM.ps1 -Name "Client1" -Action Connect

# Delete client
.\Test-ClientVM.ps1 -Name "Client1" -Action Delete
```

**In the client VM** (Alpine Linux):
```bash
# Login as root (no password)

# Configure network (DHCP)
setup-interfaces
# Select eth0, choose DHCP

# Start networking
rc-service networking start

# Check IP address
ip addr show eth0

# Test connectivity
ping 192.168.1.1  # Router IP
ping google.com   # Internet via router
```

### Test-Router.ps1

**Purpose**: Automated testing of router functionality

**Usage**:
```powershell
.\Test-Router.ps1 [-RouterIP <ip>] [-SSHPort <port>] [-Username <user>]
```

**Parameters** (all optional):
- `-RouterIP`: Router IP address (auto-detected from VM if not specified)
- `-SSHPort`: SSH port (default: 22)
- `-Username`: SSH username (default: routeradmin)

**Examples**:
```powershell
# Auto-detect router IP
.\Test-Router.ps1

# Specify router IP
.\Test-Router.ps1 -RouterIP "192.168.1.1"

# Custom SSH port
.\Test-Router.ps1 -RouterIP "192.168.1.1" -SSHPort 2222
```

**Tests performed**:
1. Network connectivity (ping)
2. SSH connectivity
3. System services status
4. Network interfaces
5. DNS resolution
6. Internet connectivity
7. Firewall/NAT configuration
8. DHCP server
9. Performance optimizations
10. Network isolation (if multi-LAN)

---

## Network Configuration

### Virtual Switches

The setup creates the following switches:

| Switch Name | Type | Purpose |
|-------------|------|---------|
| Default Switch (or External) | NAT/External | WAN - Internet access |
| NixOS-Router-LAN1 | Internal | LAN port 1 |
| NixOS-Router-LAN2 | Internal | LAN port 2 |
| NixOS-Router-LAN3 | Internal | LAN port 3 |
| NixOS-Router-LAN4 | Internal | LAN port 4 |

### Router VM Network Adapters

The router VM has 5 network adapters:

| Adapter | Switch | Purpose | Router Interface |
|---------|--------|---------|-----------------|
| WAN | Default Switch | Internet | eth0/ens3 |
| LAN1 | NixOS-Router-LAN1 | First LAN port | eth1/ens4 |
| LAN2 | NixOS-Router-LAN2 | Second LAN port | eth2/ens5 |
| LAN3 | NixOS-Router-LAN3 | Third LAN port | eth3/ens6 |
| LAN4 | NixOS-Router-LAN4 | Fourth LAN port | eth4/ens7 |

### Test Configurations

**Simple Mode (Single LAN):**
- Bridge all 4 LAN ports → `br0`
- Example: 192.168.1.1/24
- All clients on same network

**Advanced Mode (Multi-LAN with Isolation):**
- Bridge LAN1+LAN2 → `br0` (HOMELAB)
  - Example: 192.168.2.1/24
- Bridge LAN3+LAN4 → `br1` (LAN)
  - Example: 192.168.3.1/24
- Networks isolated from each other
- Both have internet access

---

## Testing Workflows

### Basic Connectivity Test

```powershell
# Start router
.\Test-RouterVM.ps1 -Action Start

# Wait for boot (check console)
.\Test-RouterVM.ps1 -Action Connect

# Run tests
.\Test-Router.ps1
```

### DHCP and Client Test

```powershell
# Create and start client
.\Test-ClientVM.ps1 -Name "Client1" -LANSwitch "NixOS-Router-LAN1" -Action Create
.\Test-ClientVM.ps1 -Name "Client1" -Action Start

# Connect to client
.\Test-ClientVM.ps1 -Name "Client1" -Action Connect

# In client VM (Alpine Linux):
# setup-interfaces  # Choose eth0, DHCP
# rc-service networking start
# ip addr show
# ping 192.168.1.1
# ping google.com
```

### Network Isolation Test (Advanced Mode)

```powershell
# Create HOMELAB client (br0)
.\Test-ClientVM.ps1 -Name "Homelab1" -LANSwitch "NixOS-Router-LAN1" -Action Create
.\Test-ClientVM.ps1 -Name "Homelab1" -Action Start

# Create LAN client (br1)
.\Test-ClientVM.ps1 -Name "LAN1" -LANSwitch "NixOS-Router-LAN3" -Action Create
.\Test-ClientVM.ps1 -Name "LAN1" -Action Start

# In Homelab1 (should get 192.168.2.x):
# ping 192.168.2.1  # ✓ HOMELAB gateway
# ping 192.168.3.1  # ✗ Should FAIL (isolated)
# ping google.com   # ✓ Internet works

# In LAN1 (should get 192.168.3.x):
# ping 192.168.3.1  # ✓ LAN gateway
# ping 192.168.2.1  # ✗ Should FAIL (isolated)
# ping google.com   # ✓ Internet works
```

---

## Troubleshooting

### Hyper-V Not Available

**Error**: "Hyper-V feature not found"

**Solution**:
- You need Windows 10/11 **Pro**, **Enterprise**, or **Education**
- Home edition does not support Hyper-V
- Alternative: Use WSL2 + QEMU (see `tests/linux/`)

### VM Won't Start

**Error**: VM fails to start

**Check**:
```powershell
# Check VM status
.\Test-RouterVM.ps1 -Action Status

# Check Hyper-V service
Get-Service vmms
```

**Solution**:
```powershell
# Restart Hyper-V service
Restart-Service vmms
```

### Cannot Auto-Detect Router IP

**Error**: "Could not auto-detect router IP"

**Solution**:
1. Connect to VM console: `.\Test-RouterVM.ps1 -Action Connect`
2. Login and check IP: `ip addr show`
3. Specify IP manually: `.\Test-Router.ps1 -RouterIP <ip>`

### No Internet in Router VM

**Error**: Router can't reach internet

**Check**:
1. WAN adapter is connected to Default Switch or external switch
2. WAN interface got DHCP address
3. Host has internet connectivity

**Solution**:
```powershell
# Check VM network adapters
Get-VMNetworkAdapter -VMName "NixOS-Router-Test"

# In VM console, check WAN interface
ip addr show eth0
ping 1.1.1.1
```

### Client Can't Get DHCP

**Error**: Client VM doesn't get IP address

**Check**:
1. Router DHCP service is running
2. Client is connected to correct LAN switch
3. Client network interface is up

**Solution**:
```powershell
# Check router DHCP
.\Test-Router.ps1

# Check client switch connection
Get-VMNetworkAdapter -VMName "NixOS-Router-Client1"

# In client VM
ip link show eth0  # Should be UP
```

### SSH Tests Fail

**Error**: "SSH client not found"

**Solution**:
1. Go to **Settings** > **Apps** > **Optional Features**
2. Click **Add a feature**
3. Find and install **OpenSSH Client**
4. Restart PowerShell

### Permission Denied

**Error**: "Access is denied" or "Administrator privileges required"

**Solution**:
- Run PowerShell as **Administrator**
- Right-click PowerShell → "Run as administrator"

---

## Cleanup

### Stop All VMs

```powershell
# Stop router
.\Test-RouterVM.ps1 -Action Stop

# Stop clients
.\Test-ClientVM.ps1 -Name "Client1" -Action Stop
.\Test-ClientVM.ps1 -Name "Homelab1" -Action Stop
# ... etc
```

### Delete VMs

```powershell
# Delete router (asks for confirmation)
.\Test-RouterVM.ps1 -Action Delete

# Delete clients
.\Test-ClientVM.ps1 -Name "Client1" -Action Delete
.\Test-ClientVM.ps1 -Name "Homelab1" -Action Delete
# ... etc
```

### Remove Virtual Switches

```powershell
# List switches
Get-VMSwitch | Where-Object { $_.Name -like "NixOS-Router-*" }

# Remove switches (optional - can keep for future tests)
Remove-VMSwitch -Name "NixOS-Router-LAN1"
Remove-VMSwitch -Name "NixOS-Router-LAN2"
Remove-VMSwitch -Name "NixOS-Router-LAN3"
Remove-VMSwitch -Name "NixOS-Router-LAN4"
Remove-VMSwitch -Name "NixOS-Router-WAN" -ErrorAction SilentlyContinue
```

### Clean Up Files

```powershell
# Remove VMs directory (deletes all VM disks)
Remove-Item VMs\ -Recurse -Force

# Keep ISOs for next test (or delete to save space)
# Remove-Item ISOs\*.iso
```

---

## Tips

1. **Use snapshots**: Take snapshots before major changes
   ```powershell
   # Create snapshot
   Checkpoint-VM -Name "NixOS-Router-Test" -SnapshotName "After Install"
   
   # Restore snapshot
   Restore-VMSnapshot -VMName "NixOS-Router-Test" -Name "After Install" -Confirm:$false
   ```

2. **Monitor performance**: Open **Task Manager** > **Performance** to monitor VM resource usage

3. **Access from host**: If you configure router with known IP (e.g., 192.168.1.1), you can access it directly from Windows

4. **Multiple test environments**: Create different router VMs for different configurations

5. **Parallel testing**: Run multiple client VMs simultaneously to test load

---

## Advantages of Windows/Hyper-V Testing

✓ **Native Windows integration** - No WSL2 required  
✓ **Better performance** - Hyper-V uses hardware virtualization  
✓ **GUI management** - Hyper-V Manager for easy VM access  
✓ **Snapshots** - Easy rollback for testing  
✓ **Network flexibility** - Easy switch configuration  
✓ **PowerShell automation** - Native Windows scripting  

## When to Use Linux/QEMU Instead

- You have Windows Home edition (no Hyper-V)
- You prefer command-line tools
- You're already using WSL2 for development
- You need QEMU-specific features

See `tests/linux/README.md` for Linux/QEMU testing.

---

## Next Steps

After successful testing:

1. Document your configuration
2. Commit `router-config.nix` to repository
3. Deploy to physical hardware
4. Enjoy your production router!

---

## Additional Resources

- **Hyper-V Documentation**: https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/
- **PowerShell Hyper-V Module**: https://docs.microsoft.com/en-us/powershell/module/hyper-v/
- **NixOS Manual**: https://nixos.org/manual/nixos/stable/

