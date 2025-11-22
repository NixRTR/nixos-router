import{j as e}from"./ui-vendor-CtbJYEGA.js";import{M as t}from"./MarkdownContent-D-Zi6kKK.js";import"./react-vendor-ZjkKMkft.js";import"./markdown-vendor-D8KYDTzx.js";const n=`# CAKE Configuration

CAKE (Common Applications Kept Enhanced) is a comprehensive queue management system that reduces bufferbloat and improves network latency under load.

## Why Enable CAKE?

CAKE addresses bufferbloat, a common networking problem where excessive buffering in routers and switches causes high latency and jitter, especially during network congestion. Without proper queue management, packets pile up in router buffers, leading to:

- **High latency** - Delayed responses to user actions
- **Jitter** - Inconsistent latency making real-time applications unreliable
- **Poor interactive performance** - Laggy gaming, video calls, and remote sessions
- **Slow page loads** - Even when bandwidth isn't fully utilized

CAKE actively manages traffic queues to minimize these issues by:

- **Smart queue management** - Prevents buffer buildup through intelligent packet scheduling
- **Automatic bandwidth detection** - Monitors network conditions and adjusts dynamically
- **Latency prioritization** - Ensures responsive traffic gets priority over bulk transfers
- **DiffServ support** - Honors Differentiated Services (QoS) markings for proper traffic classification

## Benefits

Enabling CAKE provides several key benefits:

- **Reduced latency** - Significantly lower ping times, especially under load
- **Consistent performance** - Stable latency even when network is busy
- **Better gaming experience** - Smooth gameplay with minimal lag spikes
- **Improved video calls** - Clear audio and video without freezing or stuttering
- **Faster web browsing** - More responsive page loads even during downloads
- **Better remote desktop performance** - Smooth and responsive remote sessions

CAKE works automatically in the background - once configured, it requires no ongoing maintenance and adapts to your network conditions.

## Basic Configuration

Enable CAKE with default settings:

\`\`\`nix
wan = {
  type = "dhcp";  # or "pppoe"
  interface = "eno1";
  
  cake = {
    enable = true;
    aggressiveness = "auto";  # Recommended default
  };
};
\`\`\`

## Configuration Options

### Enable

Enable or disable CAKE traffic shaping:

\`\`\`nix
cake = {
  enable = true;  # Set to false to disable
};
\`\`\`

When enabled, CAKE automatically configures itself on your WAN interface after the network comes online.

### Aggressiveness

Controls how aggressively CAKE manages latency versus throughput. Choose the level that best fits your connection:

\`\`\`nix
cake = {
  enable = true;
  aggressiveness = "auto";  # Options: "auto", "conservative", "moderate", "aggressive"
};
\`\`\`

**Aggressiveness Levels:**

- **\`auto\`** (Recommended) - Monitors bandwidth automatically and adjusts queue management dynamically. Best for most users as it adapts to your connection speed and usage patterns.
  
- **\`conservative\`** - Minimal shaping with default CAKE settings (target ~5ms, interval ~100ms). Best for high-speed links (gigabit+) where maximum throughput is prioritized over absolute lowest latency.

- **\`moderate\`** - Balanced approach using CAKE defaults. Good middle ground between latency reduction and throughput for most connections.

- **\`aggressive\`** - Maximum latency reduction with more aggressive Active Queue Management (target 2ms, interval 50ms). Best for slower links (< 100Mbit) where keeping latency low is critical for interactive applications.

### Upload Bandwidth

Set explicit upload bandwidth limit for optimal performance:

\`\`\`nix
cake = {
  enable = true;
  aggressiveness = "auto";
  uploadBandwidth = "190Mbit";  # ~95% of your actual upload speed
};
\`\`\`

**When to set explicit bandwidth:**
- When you know your exact connection speeds
- For best performance and consistency
- To ensure CAKE shapes to your actual limits

**Format:** Use bandwidth strings like \`"200Mbit"\`, \`"500Mbit"\`, \`"1000mbit"\` (case insensitive)

**Recommendation:** Set to approximately **95% of your actual upload speed** to account for protocol overhead (Ethernet, IP, TCP headers). For example:
- 200 Mbit/s connection → \`"190Mbit"\`
- 500 Mbit/s connection → \`"475Mbit"\`
- 1000 Mbit/s connection → \`"950Mbit"\`

**If not set:** CAKE will use \`autorate-ingress\` to automatically detect your upload bandwidth by monitoring incoming traffic patterns.

### Download Bandwidth

Optional reference value for download bandwidth:

\`\`\`nix
cake = {
  enable = true;
  aggressiveness = "auto";
  uploadBandwidth = "190Mbit";
  downloadBandwidth = "475Mbit";  # For reference/documentation
};
\`\`\`

**Note:** CAKE primarily shapes egress (upload) traffic on the root queue discipline. The \`downloadBandwidth\` setting is mainly for documentation/reference and doesn't directly affect CAKE's operation. CAKE uses \`autorate-ingress\` to automatically tune egress shaping based on observed ingress (download) patterns when explicit bandwidth isn't set.

## Complete Example

Here's a complete CAKE configuration example:

\`\`\`nix
wan = {
  type = "pppoe";
  interface = "eno1";
  
  cake = {
    enable = true;
    aggressiveness = "auto";
    uploadBandwidth = "190Mbit";    # 200 Mbit/s * 0.95
    downloadBandwidth = "475Mbit";  # 500 Mbit/s * 0.95
  };
};
\`\`\`

## How It Works

CAKE is applied to your WAN interface as a queue discipline (qdisc) using Linux's traffic control system:

1. **Interface Detection** - CAKE automatically detects your WAN interface
   - For DHCP connections: Uses the physical interface (e.g., \`eno1\`)
   - For PPPoE connections: Uses the logical interface (e.g., \`ppp0\`)

2. **Automatic Setup** - A systemd service configures CAKE when the network comes online

3. **Traffic Shaping** - CAKE manages outbound (upload) traffic queues to prevent bufferbloat

4. **Adaptive Control** - With \`autorate-ingress\`, CAKE monitors incoming traffic to automatically tune shaping parameters

## Verification

After enabling CAKE, verify it's active:

\`\`\`bash
# Check if CAKE qdisc is configured
tc qdisc show dev ppp0  # or your WAN interface name

# Look for "cake" in the output
# Example output: qdisc cake 8001: root refcnt 2 bandwidth unlimited diffserv4 nat wash autorate-ingress
\`\`\`

## When Not to Use CAKE

CAKE is beneficial for most home router scenarios, but you might skip it if:

- You have very high-speed symmetric connections (10Gbit+) with excellent buffer management
- You're using a different QoS/traffic shaping solution
- You're on a low-bandwidth connection where shaping could reduce throughput too much

For most users, especially those with asymmetric connections (common with cable/DSL/fiber), CAKE provides significant benefits with minimal overhead.
`;function r(){return e.jsx("div",{className:"p-6 max-w-4xl mx-auto",children:e.jsx("div",{className:"bg-white dark:bg-gray-800 rounded-lg shadow-sm p-6",children:e.jsx(t,{content:n})})})}export{r as CakeConfig};
