# Performance Optimization

This router is optimized for high-performance networking with multiple built-in optimizations.

## Overview

Out of the box, the router includes:

- ✅ **BBR Congestion Control**: Modern TCP algorithm for better throughput
- ✅ **Hardware Offloading**: Shift packet processing to NIC
- ✅ **MSS Clamping**: Prevent packet fragmentation
- ✅ **TCP Fast Open**: Reduce connection latency
- ✅ **Connection Tracking Optimization**: Handle more concurrent connections
- ✅ **Performance CPU Governor**: Maximum CPU frequency

---

## TCP Optimizations

### BBR Congestion Control

**What it is**: TCP congestion control algorithm developed by Google.

**Benefits**:
- Higher throughput on high-latency links
- Better performance with packet loss
- Ideal for home routers with varying WAN conditions

**How it works**:
- Traditional algorithms (Cubic) react to packet loss
- BBR probes available bandwidth and RTT
- Maintains optimal sending rate

**Configuration** (already enabled):

```nix
boot.kernel.sysctl = {
  "net.ipv4.tcp_congestion_control" = "bbr";
  "net.core.default_qdisc" = "fq";  # Fair Queue required for BBR
};
```

**Verification**:

```bash
# Check congestion control
sysctl net.ipv4.tcp_congestion_control
# Output: net.ipv4.tcp_congestion_control = bbr

# Check queue discipline
sysctl net.core.default_qdisc
# Output: net.core.default_qdisc = fq
```

### TCP Buffer Sizes

**What they are**: Memory buffers for sending/receiving data.

**Benefits**:
- Larger buffers = higher throughput on fast networks
- Default Linux buffers are conservative

**Configuration** (already enabled):

```nix
boot.kernel.sysctl = {
  # Maximum buffer size (128 MB)
  "net.core.rmem_max" = 134217728;
  "net.core.wmem_max" = 134217728;
  
  # TCP-specific buffers (min, default, max)
  "net.ipv4.tcp_rmem" = "4096 87380 67108864";  # Receive
  "net.ipv4.tcp_wmem" = "4096 65536 67108864";  # Send
};
```

**Impact**:
- Allows TCP connections to use up to 64 MB of buffer
- Critical for multi-gigabit throughput
- Minimal memory overhead (only used when needed)

### TCP Fast Open

**What it is**: Allows data in SYN packet, reducing handshake time.

**Benefits**:
- Reduces latency for short-lived connections (HTTP requests)
- Especially useful for web browsing

**Configuration** (already enabled):

```nix
boot.kernel.sysctl = {
  "net.ipv4.tcp_fastopen" = 3;  # Client + Server
};
```

**Verification**:

```bash
sysctl net.ipv4.tcp_fastopen
# Output: net.ipv4.tcp_fastopen = 3
```

### TCP TIME_WAIT Optimization

**What it is**: Reduces time TCP connections stay in TIME_WAIT state.

**Benefits**:
- Faster port reuse
- Supports more concurrent connections
- Reduces NAT table bloat

**Configuration** (already enabled):

```nix
boot.kernel.sysctl = {
  "net.ipv4.tcp_fin_timeout" = 30;     # 30 seconds (down from 60)
  "net.ipv4.tcp_tw_reuse" = 1;         # Reuse TIME_WAIT sockets
};
```

---

## MSS Clamping

### What is MSS?

**MSS (Maximum Segment Size)**: Largest amount of data in a single TCP packet.

**Problem**:
- WAN MTU (Maximum Transmission Unit) is often 1500 bytes
- PPPoE reduces it to 1492 bytes
- If device sends 1500-byte packets over 1492-byte link → fragmentation
- Fragmented packets cause slowness (like your GitHub issue!)

### How MSS Clamping Works

Router automatically adjusts MSS in TCP handshakes to match WAN MTU.

```
Device: "I can handle 1460 bytes (MSS)"
Router: "Actually, use 1452 bytes (clamped to MTU - overhead)"
```

**Configuration** (already enabled):

```nix
networking.nat.extraCommands = ''
  # Clamp MSS to PMTU (Path MTU)
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
'';
```

**Verification**:

```bash
sudo iptables -t mangle -L FORWARD -v -n
# Should see: TCPMSS tcp -- * * 0.0.0.0/0 0.0.0.0/0 tcp flags:0x06/0x02 TCPMSS clamp to PMTU
```

**Impact**: Fixes slow loading issues on certain websites (like GitHub).

---

## Hardware Offloading

### What is Hardware Offloading?

Network cards can handle certain tasks in hardware instead of CPU:

- **RX/TX Checksum**: Verify packet integrity
- **TCP Segmentation Offload (TSO)**: Split large packets
- **Generic Segmentation Offload (GSO)**: Generic packet splitting
- **Generic Receive Offload (GRO)**: Combine small packets
- **Large Receive Offload (LRO)**: Combine received packets

### Benefits

- Reduces CPU usage
- Increases maximum throughput
- Lower latency

### Configuration (already enabled)

```nix
systemd.network.links."10-${wanInterface}" = {
  matchConfig.Name = wanInterface;
  linkConfig = {
    ReceiveChecksumOffload = true;
    TransmitChecksumOffload = true;
    TCPSegmentationOffload = true;
    GenericSegmentationOffload = true;
    GenericReceiveOffload = true;
    LargeReceiveOffload = true;
  };
};
```

### Verification

```bash
# Check offload status
sudo ethtool -k eno1 | grep offload
```

Expected output:

```
rx-checksumming: on
tx-checksumming: on
tcp-segmentation-offload: on
generic-segmentation-offload: on
generic-receive-offload: on
large-receive-offload: on
```

### Troubleshooting

If offloading is not working:

1. **NIC may not support it**:
   ```bash
   ethtool -k eno1 | grep "fixed"
   ```
   Features marked `[fixed]` cannot be changed.

2. **Driver may not support it**:
   Check driver: `lspci -k | grep -A 3 Ethernet`

3. **Disable problematic features**:
   Some NICs have buggy LRO implementation:
   ```nix
   linkConfig = {
     # ...
     LargeReceiveOffload = false;  # Disable if causing issues
   };
   ```

---

## Connection Tracking

### What is Connection Tracking?

Linux tracks every connection for NAT and firewalling.

**Problem**: Default limits are low for routers.

### Optimizations (already enabled)

```nix
boot.kernel.sysctl = {
  # Increase max connections (256k)
  "net.netfilter.nf_conntrack_max" = 262144;
  
  # Keep established connections for 24 hours
  "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;
  
  # Shorter TIME_WAIT timeout (30 seconds)
  "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 30;
};
```

### Monitoring

Check current connection count:

```bash
# Connection count
sudo conntrack -L | wc -l

# Connection table usage
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
```

### Tuning

If you're hitting connection limits:

```nix
boot.kernel.sysctl = {
  "net.netfilter.nf_conntrack_max" = 524288;  # 512k (double)
};
```

**Warning**: Uses more RAM (each connection = ~300 bytes).

---

## CPU Governor

### What is CPU Governor?

Controls CPU frequency scaling (power vs performance).

### Configuration (already enabled)

```nix
powerManagement.cpuFreqGovernor = "performance";
```

Keeps CPU at maximum frequency (no dynamic scaling).

### Alternatives

**powersave**: Minimum frequency (low power, worse performance)
**ondemand**: Dynamic scaling (balanced)
**performance**: Maximum frequency (best performance, more power)

**Router recommendation**: Use `performance` (routers need consistent low latency).

### Verification

```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Output: performance (for all CPUs)

# Check current frequency
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
```

---

## Security vs Performance

Some security features impact performance. The router balances both.

### SYN Flood Protection

**Enabled** (minimal performance impact):

```nix
boot.kernel.sysctl = {
  "net.ipv4.tcp_syncookies" = 1;         # Enable SYN cookies
  "net.ipv4.tcp_max_syn_backlog" = 8192; # Large backlog
  "net.ipv4.tcp_synack_retries" = 2;     # Quick retry
};
```

**Impact**: Negligible. Only activates under attack.

### Reverse Path Filtering

**Enabled** (minimal performance impact):

```nix
boot.kernel.sysctl = {
  "net.ipv4.conf.all.rp_filter" = 1;  # Strict mode
};
```

Drops packets with invalid source IPs (anti-spoofing).

**Impact**: Negligible. Single routing table lookup.

### Connection Tracking

**Required for NAT** (moderate performance impact):

Can't be disabled if using NAT. Already optimized (see [Connection Tracking](#connection-tracking)).

---

## Advanced Tuning

### Increase Network Device Backlog

For high-speed networks (>1 Gbps):

```nix
boot.kernel.sysctl = {
  "net.core.netdev_max_backlog" = 10000;  # Default: 5000
};
```

**When to use**: Seeing dropped packets in `ip -s link show`.

### Optimize Interrupt Handling

Spread network interrupts across CPU cores:

```bash
# Check interrupt distribution
cat /proc/interrupts | grep eth

# Install irqbalance (already included)
systemctl enable irqbalance
systemctl start irqbalance
```

### Disable IPv6 (if not using)

**Already enabled in config** when IPv6 is disabled per-bridge:

```nix
lan.bridges = [
  {
    ipv6.enable = false;
  }
];
```

Reduces overhead if you're not using IPv6.

### Tune Socket Backlog

For high connection rate:

```nix
boot.kernel.sysctl = {
  "net.core.somaxconn" = 4096;  # Default: 128
};
```

**When to use**: Running web server behind router with many concurrent connections.

---

## Performance Testing

### Bandwidth Testing

**iperf3**: Test raw throughput

```bash
# On server (e.g., another PC on LAN)
iperf3 -s

# On client
iperf3 -c 192.168.2.10
```

**Expected results**:
- Gigabit link: ~940 Mbps (accounting for overhead)
- 2.5 Gbps link: ~2.3 Gbps

### Latency Testing

**ping**: Basic latency

```bash
# Local latency (should be <1ms)
ping 192.168.2.1

# WAN latency (depends on ISP)
ping 1.1.1.1
```

**hping3**: Advanced latency/load testing

```bash
# TCP SYN latency
hping3 -S 192.168.2.1 -p 80 -c 10
```

### Load Testing

**iperf3 multi-stream**: Test router under load

```bash
# 10 parallel streams
iperf3 -c 192.168.2.10 -P 10
```

**ab (ApacheBench)**: HTTP load testing

```bash
# 1000 requests, 100 concurrent
ab -n 1000 -c 100 http://192.168.2.10/
```

### Monitoring During Tests

Watch router performance:

```bash
# CPU usage
htop

# Network throughput
iftop -i br0

# Connection tracking
watch -n 1 'cat /proc/sys/net/netfilter/nf_conntrack_count'
```

---

## Troubleshooting Performance Issues

### Low Throughput

**Symptoms**: Speed tests show below ISP advertised speed

**Diagnosis**:

1. **Test direct to modem** (bypass router):
   - If fast: Router bottleneck
   - If slow: ISP issue

2. **Check CPU usage** during transfer:
   ```bash
   htop
   ```
   - CPU >80%: Need hardware offloading or faster CPU
   - CPU low: Not CPU bottleneck

3. **Check hardware offloading**:
   ```bash
   sudo ethtool -k eno1 | grep offload
   ```
   - Offloads off: Enable them
   - Offloads on: NIC may not support high speeds

4. **Check MSS clamping**:
   ```bash
   sudo iptables -t mangle -L FORWARD -v -n
   ```
   - Missing TCPMSS rule: Add MSS clamping

**Solutions**:
- Enable hardware offloading
- Add MSS clamping
- Upgrade to faster CPU
- Check for ISP throttling

### High Latency

**Symptoms**: Ping times >10ms to router, lag in games

**Diagnosis**:

1. **Ping router**:
   ```bash
   ping 192.168.2.1
   ```
   - High latency: Router overloaded
   - Low latency: Issue elsewhere

2. **Check CPU governor**:
   ```bash
   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
   ```
   - Should be `performance`

3. **Check buffer bloat**:
   - Run [DSLReports Speed Test](http://www.dslreports.com/speedtest)
   - "Bufferbloat" grade should be A or B

**Solutions**:
- Set CPU governor to `performance`
- Enable BBR congestion control
- Consider traffic shaping (not yet implemented)

### Packet Loss

**Symptoms**: Intermittent disconnections, retransmissions

**Diagnosis**:

1. **Check interface errors**:
   ```bash
   ip -s link show eno1
   ```
   Look for "errors", "dropped", "overruns"

2. **Check dmesg**:
   ```bash
   dmesg | grep -i error
   ```

3. **Check cables**:
   Bad Ethernet cable can cause packet loss

**Solutions**:
- Replace cables
- Increase netdev_max_backlog
- Check NIC driver updates

---

## Benchmarking Results

Typical performance on modern hardware (Intel i5, 4-port Intel NIC):

| Metric | Value |
|--------|-------|
| WAN → LAN throughput | 940 Mbps (Gigabit) |
| LAN → WAN throughput | 940 Mbps (Gigabit) |
| Router latency | <1 ms |
| Concurrent connections | 50,000+ |
| CPU usage (max throughput) | 30-40% |
| CPU usage (idle) | 5-10% |
| Memory usage | 2-3 GB |

**Your results may vary** based on:
- CPU speed
- NIC capabilities
- Number of firewall rules
- Number of active connections

---

## Future Optimizations

Planned features:

- **Traffic Shaping (QoS)**: Prioritize latency-sensitive traffic
- **XDP (Express Data Path)**: Kernel bypass for extreme performance
- **DPDK**: Userspace packet processing
- **Hardware Flow Offload**: Offload entire flows to NIC

---

## Next Steps

- **[Monitoring](monitoring.md)** - Watch performance metrics in Grafana
- **[Troubleshooting](troubleshooting.md)** - Fix performance issues
- **[Configuration](configuration.md)** - Tune settings for your network


