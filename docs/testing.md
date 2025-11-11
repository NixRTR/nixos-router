# Testing the Router in a VM

This guide covers testing the NixOS router in a QEMU virtual machine before deploying to physical hardware.

## Prerequisites

- **WSL2** on Windows (or native Linux)
- **QEMU** installed in WSL2
- **VNC viewer** (e.g., TightVNC, RealVNC) on Windows to access VM console

## Quick Start

### 1. Setup Test Environment

From WSL2:

```bash
cd /mnt/c/Users/YourName/github/nixos-router/tests
chmod +x test-vm-qemu.sh test-client-vm.sh test-router.sh
./test-vm-qemu.sh
```

Select option **1** (Setup) to install dependencies and download NixOS ISO.

**Note**: ISOs are downloaded to the `files/` subdirectory, and VM disks are created in the `tests/` directory.

### 2. Create VM Disk

Select option **2** to create a virtual disk for the router.

### 3. Start Router VM

Select option **3** to start the VM with the NixOS installer.

## VM Network Configuration

The test VM has **5 network interfaces**:

| Interface | Name in VM | Purpose | Connection |
|-----------|------------|---------|------------|
| 1st NIC | `ens3` | WAN | Internet via NAT |
| 2nd NIC | `ens4` | LAN1 | Test network (port 8001) |
| 3rd NIC | `ens5` | LAN2 | Test network (port 8002) |
| 4th NIC | `ens6` | LAN3 | Test network (port 8003) |
| 5th NIC | `ens7` | LAN4 | Test network (port 8004) |

**Port Forwarding** (from Windows/WSL2 to VM):
- SSH: `localhost:2222` → VM port 22
- Grafana: `localhost:3000` → VM port 3000

## Installation in VM

### Access the VM Console

**Option A: VNC** (Recommended for Windows)

1. Install a VNC viewer on Windows (e.g., TightVNC)
2. Connect to `localhost:5900`
3. You'll see the NixOS installer

**Option B: Serial Console**

The VM console is available in the terminal where you ran the script.

### Run the Installer

Once in the NixOS installer:

```bash
# Download and run installer
curl -fsSL https://beard.click/nixos-router > install.sh
chmod +x install.sh
sudo ./install.sh
```

**Test Configuration Recommendations:**

- **Hostname**: `nixos-router-test`
- **Disk**: `/dev/vda` (virtual disk)
- **WAN interface**: `ens3`
- **WAN type**: DHCP

**Simple Mode Test:**
- LAN IP: `192.168.1.1`
- Bridge interfaces: `ens4 ens5 ens6 ens7`

**Advanced Mode Test:**
- HOMELAB: `192.168.2.1`, interfaces: `ens4 ens5`
- LAN: `192.168.3.1`, interfaces: `ens6 ens7`

### Complete Installation

After installation:

```bash
umount -R /mnt
reboot
```

### Boot Installed System

Back in the test menu, select option **4** (Boot from disk).

---

## Testing Router Functionality

### Test 1: Access Router via SSH

From WSL2 or Windows:

```bash
# SSH to router
ssh -p 2222 routeradmin@localhost
```

Password: whatever you set during installation

### Test 2: Check Services

On the router:

```bash
# Check all services
systemctl status systemd-networkd blocky kea-dhcp4-server grafana prometheus

# Check network interfaces
ip addr show

# Check bridges
ip link show br0
ip link show br1  # If using advanced mode

# Check internet connectivity
ping -c 3 1.1.1.1

# Check DNS
dig google.com @127.0.0.1
```

### Test 3: Access Grafana Dashboard

From Windows, open browser:

```
http://localhost:3000
```

Default login: `admin` / `admin`

You should see the router dashboard with metrics.

### Test 4: Test DHCP and Client Connectivity

Create test client VMs to connect to the router's LAN ports.

#### Start Test Client (Simple Mode)

In a **new WSL2 terminal**:

```bash
cd /mnt/c/Users/YourName/github/nixos-router/tests
./test-client-vm.sh client1 8001
```

This creates a small Alpine Linux VM connected to LAN port 1 (br0).

#### Configure Client to Get DHCP

In the client VM (access via VNC on `localhost:5901`):

1. Login as `root` (no password)
2. Configure networking:
   ```bash
   setup-interfaces
   # Select eth0
   # Choose DHCP
   # Press Enter for defaults
   
   # Start networking
   rc-service networking start
   ```

3. Check IP address:
   ```bash
   ip addr show eth0
   # Should show 192.168.1.x (simple mode) or 192.168.2.x (HOMELAB)
   ```

4. Test connectivity:
   ```bash
   # Ping router
   ping 192.168.1.1  # Or 192.168.2.1 for HOMELAB
   
   # Test DNS
   ping google.com
   
   # Test internet
   wget -O- http://icanhazip.com
   ```

#### Start Multiple Clients (Advanced Mode)

To test network isolation:

**Terminal 1** (HOMELAB client):
```bash
./test-client-vm.sh homelab1 8001  # Connects to br0
```

**Terminal 2** (Another HOMELAB client):
```bash
./test-client-vm.sh homelab2 8002  # Connects to br0
```

**Terminal 3** (LAN client):
```bash
./test-client-vm.sh lan1 8003  # Connects to br1
```

**Terminal 4** (Another LAN client):
```bash
./test-client-vm.sh lan2 8004  # Connects to br1
```

VNC ports:
- homelab1: `localhost:5901`
- homelab2: `localhost:5902`
- lan1: `localhost:5903`
- lan2: `localhost:5904`

### Test 5: Verify Network Isolation (Advanced Mode)

From `lan1` VM (192.168.3.x):

```bash
# Can ping LAN gateway
ping 192.168.3.1  # ✅ Should work

# Can ping another LAN device
ping 192.168.3.x  # ✅ Should work (if lan2 is up)

# CANNOT ping HOMELAB gateway
ping 192.168.2.1  # ❌ Should FAIL (isolation)

# CANNOT ping HOMELAB devices
ping 192.168.2.x  # ❌ Should FAIL (isolation)

# CAN access internet
ping 1.1.1.1  # ✅ Should work
```

From `homelab1` VM (192.168.2.x):

```bash
# Can ping HOMELAB gateway
ping 192.168.2.1  # ✅ Should work

# Can ping another HOMELAB device
ping 192.168.2.x  # ✅ Should work (if homelab2 is up)

# CANNOT ping LAN gateway
ping 192.168.3.1  # ❌ Should FAIL (isolation)

# CAN access internet
ping 1.1.1.1  # ✅ Should work
```

### Test 6: Test Isolation Exception

SSH to router:

```bash
ssh -p 2222 routeradmin@localhost
```

Edit configuration:

```bash
sudo nano /etc/nixos/router-config.nix
```

Add an exception (assuming lan1 got 192.168.3.100):

```nix
isolationExceptions = [
  {
    source = "192.168.3.100";
    sourceBridge = "br1";
    destBridge = "br0";
    description = "Test exception for lan1";
  }
];
```

Apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

Now from `lan1` (192.168.3.100):

```bash
# Should NOW work
ping 192.168.2.1  # ✅ Exception allows it
ping 192.168.2.x  # ✅ Can reach HOMELAB devices
```

But from `lan2` (192.168.3.101):

```bash
# Still blocked
ping 192.168.2.1  # ❌ No exception for this IP
```

### Test 7: Test Port Forwarding

SSH to router:

```bash
ssh -p 2222 routeradmin@localhost
```

Add port forward (assuming homelab1 is 192.168.2.100 and running a web server):

```bash
sudo nano /etc/nixos/router-config.nix
```

```nix
portForwards = [
  {
    proto = "tcp";
    externalPort = 8080;
    destination = "192.168.2.100";
    destinationPort = 80;
  }
];
```

Apply:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#router
```

Test from Windows/WSL2:

```bash
# Port 8080 on localhost (WAN) should forward to homelab1:80
curl http://localhost:8080
```

---

## Automated Testing

### Full Test Script

Create a script to automate common tests:

```bash
#!/bin/bash
# test-router.sh

echo "=== Router Connectivity Tests ==="

# Test 1: SSH
echo "Test 1: SSH to router..."
ssh -p 2222 -o ConnectTimeout=5 routeradmin@localhost "echo 'SSH OK'" || echo "FAILED"

# Test 2: Grafana
echo "Test 2: Grafana dashboard..."
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q 200 && echo "OK" || echo "FAILED"

# Test 3: DNS
echo "Test 3: DNS resolution..."
ssh -p 2222 routeradmin@localhost "dig google.com @127.0.0.1 +short" > /dev/null && echo "OK" || echo "FAILED"

# Test 4: Internet
echo "Test 4: Internet connectivity..."
ssh -p 2222 routeradmin@localhost "ping -c 1 1.1.1.1" > /dev/null && echo "OK" || echo "FAILED"

# Test 5: DHCP
echo "Test 5: DHCP server..."
ssh -p 2222 routeradmin@localhost "systemctl is-active kea-dhcp4-server" | grep -q active && echo "OK" || echo "FAILED"

echo "=== Tests complete ==="
```

---

## Troubleshooting VM Testing

### VM Won't Start

**Issue**: QEMU fails to start

**Solution**:
```bash
# Check if QEMU is installed
qemu-system-x86_64 --version

# Install if needed
sudo apt-get update
sudo apt-get install qemu-system-x86
```

### Can't Access VNC

**Issue**: VNC viewer can't connect to `localhost:5900`

**Solution**:
- Make sure VM is running
- Try `127.0.0.1:5900` instead of `localhost:5900`
- Check Windows Firewall isn't blocking VNC

### No Internet in VM

**Issue**: Router can't reach internet

**Solution**:
- Check WSL2 has internet: `ping 1.1.1.1`
- Verify WAN interface (`ens3`) got DHCP: `ip addr show ens3`
- Check NAT: `ip route show`

### Client Can't Connect to Router

**Issue**: Test client VM can't connect

**Solution**:
- Make sure router VM is running first
- Check LAN port number matches (8001-8004)
- Verify bridges are up on router: `ip link show br0`

### Slow VM Performance

**Issue**: VM is very slow

**Solution**:
- This is normal in WSL2 without KVM acceleration
- Reduce memory: Edit `test-vm-qemu.sh`, change `VM_MEMORY="2G"`
- Reduce CPUs: Change `VM_CPUS="2"`
- Use serial console instead of VNC

### Port Already in Use

**Issue**: `Address already in use` error

**Solution**:
```bash
# Find what's using the port
netstat -tulpn | grep 8001

# Kill old QEMU process
pkill qemu
```

---

## Cleaning Up

### Stop All VMs

Press `Ctrl+A` then `X` in each QEMU terminal.

Or from another terminal:

```bash
pkill qemu-system-x86_64
```

### Remove Test VMs

```bash
cd /mnt/c/Users/YourName/github/nixos-router/tests

# Remove router disk
rm nixos-router-test.qcow2

# Remove client disks
rm client*.qcow2
rm homelab*.qcow2
rm lan*.qcow2

# Keep ISOs for next time (or delete to save space)
# rm files/nixos-minimal.iso
# rm files/alpine-virt-3.19.0-x86_64.iso
```

---

## Tips for Testing

1. **Use snapshots**: QEMU supports snapshots for quick testing
   ```bash
   # Create snapshot
   qemu-img snapshot -c test1 nixos-router-test.qcow2
   
   # Restore snapshot
   qemu-img snapshot -a test1 nixos-router-test.qcow2
   ```

2. **Test isolation thoroughly**: Spin up multiple client VMs to verify isolation

3. **Monitor performance**: Watch Grafana dashboard while testing

4. **Test failover**: Disconnect WAN to see how router handles it

5. **Stress test**: Use `iperf3` between client VMs to test throughput

---

## Next Steps

Once testing is complete and everything works:

1. Document any configuration changes you made
2. Commit your `router-config.nix` to the repository
3. Deploy to physical hardware
4. Enjoy your production router!

---

## Additional Resources

- **QEMU Documentation**: https://www.qemu.org/docs/master/
- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Alpine Linux**: https://alpinelinux.org/

