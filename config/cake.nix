{
  # CAKE traffic shaping configuration (optional)
  # CAKE (Common Applications Kept Enhanced) is a comprehensive queue management system
  # that reduces bufferbloat and improves latency under load
  
  # Set to true to enable CAKE traffic shaping
  enable = false;
  
  # Options: "auto", "conservative", "moderate", "aggressive"
  # auto: Monitors bandwidth and adjusts automatically (recommended)
  # conservative: Minimal shaping, best for high-speed links
  # moderate: Balanced latency/throughput
  # aggressive: Maximum latency reduction, best for slower links
  aggressiveness = "auto";
  
  # Optional: Set explicit bandwidth limits (recommended for better performance)
  # If not set, CAKE will use autorate-ingress to automatically detect bandwidth
  # Format: "200Mbit", "500Mbit", "1000mbit", etc.
  # Set to ~95% of your actual speeds to account for overhead
  uploadBandwidth = "190Mbit";    # Your upload speed (egress shaping) - 200Mbit * 0.95
  downloadBandwidth = "475Mbit";  # Your download speed (for reference) - 500Mbit * 0.95
  
  # Note: CAKE on root qdisc shapes egress (upload). When uploadBandwidth is set,
  # autorate-ingress is disabled and explicit bandwidth is used instead.
}
