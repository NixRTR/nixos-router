#!/usr/bin/env bash
# Automated Router Testing Script
# Tests router functionality after installation

set -euo pipefail

# Configuration
ROUTER_SSH_PORT="${1:-2222}"
ROUTER_IP="localhost"
GRAFANA_PORT="3000"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_failure() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Test SSH connectivity
test_ssh() {
    echo
    log_info "Test 1: SSH Connectivity"
    if timeout 10 ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        routeradmin@"$ROUTER_IP" "echo 'SSH test successful'" &>/dev/null; then
        log_success "SSH connection works"
    else
        log_failure "SSH connection failed"
        log_warning "Make sure router VM is running and you've added your SSH key or use password"
    fi
}

# Test system services
test_services() {
    echo
    log_info "Test 2: System Services"
    
    SERVICES=("systemd-networkd" "blocky" "kea-dhcp4-server" "grafana" "prometheus")
    
    for service in "${SERVICES[@]}"; do
        if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
            "systemctl is-active $service" 2>/dev/null | grep -q "^active$"; then
            log_success "$service is running"
        else
            log_failure "$service is not running"
        fi
    done
}

# Test network interfaces
test_interfaces() {
    echo
    log_info "Test 3: Network Interfaces"
    
    # Check WAN interface has IP
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "ip addr show | grep -q 'inet.*ens3'" 2>/dev/null; then
        log_success "WAN interface (ens3) has IP address"
    else
        log_failure "WAN interface (ens3) has no IP address"
    fi
    
    # Check br0 exists
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "ip link show br0" &>/dev/null; then
        log_success "Bridge br0 exists"
    else
        log_failure "Bridge br0 does not exist"
    fi
}

# Test DNS resolution
test_dns() {
    echo
    log_info "Test 4: DNS Resolution"
    
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "dig google.com @127.0.0.1 +short +time=5" 2>/dev/null | grep -q '^[0-9]'; then
        log_success "DNS resolution works"
    else
        log_failure "DNS resolution failed"
    fi
}

# Test internet connectivity
test_internet() {
    echo
    log_info "Test 5: Internet Connectivity"
    
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "ping -c 1 -W 5 1.1.1.1" &>/dev/null; then
        log_success "Internet connectivity works"
    else
        log_failure "No internet connectivity"
    fi
}

# Test Grafana dashboard
test_grafana() {
    echo
    log_info "Test 6: Grafana Dashboard"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ROUTER_IP:$GRAFANA_PORT" 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" == "302" ]] || [[ "$HTTP_CODE" == "200" ]]; then
        log_success "Grafana dashboard is accessible"
    else
        log_failure "Grafana dashboard not accessible (HTTP $HTTP_CODE)"
    fi
}

# Test firewall/NAT
test_firewall() {
    echo
    log_info "Test 7: Firewall/NAT Configuration"
    
    # Check NAT rules
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "sudo iptables -t nat -L POSTROUTING -n | grep -q MASQUERADE" 2>/dev/null; then
        log_success "NAT masquerading is configured"
    else
        log_failure "NAT masquerading not configured"
    fi
    
    # Check forwarding is enabled
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "cat /proc/sys/net/ipv4/ip_forward" 2>/dev/null | grep -q "1"; then
        log_success "IP forwarding is enabled"
    else
        log_failure "IP forwarding is not enabled"
    fi
}

# Test DHCP server
test_dhcp() {
    echo
    log_info "Test 8: DHCP Server Configuration"
    
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "sudo cat /etc/kea/dhcp4.conf" &>/dev/null; then
        log_success "DHCP configuration file exists"
    else
        log_failure "DHCP configuration file not found"
    fi
}

# Test performance optimizations
test_optimizations() {
    echo
    log_info "Test 9: Performance Optimizations"
    
    # Check BBR
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "sysctl net.ipv4.tcp_congestion_control" 2>/dev/null | grep -q "bbr"; then
        log_success "BBR congestion control enabled"
    else
        log_failure "BBR not enabled"
    fi
    
    # Check MSS clamping
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "sudo iptables -t mangle -L FORWARD -n | grep -q TCPMSS" 2>/dev/null; then
        log_success "MSS clamping configured"
    else
        log_failure "MSS clamping not configured"
    fi
}

# Test isolation (if multi-LAN mode)
test_isolation() {
    echo
    log_info "Test 10: Network Isolation (if enabled)"
    
    # Check if br1 exists (multi-LAN mode)
    if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
        "ip link show br1" &>/dev/null; then
        log_info "Multi-LAN mode detected (br0 and br1)"
        
        # Check for isolation firewall rules
        if ssh -p "$ROUTER_SSH_PORT" -o StrictHostKeyChecking=no routeradmin@"$ROUTER_IP" \
            "sudo iptables -L FORWARD -n | grep -q 'br0.*br1.*DROP'" 2>/dev/null; then
            log_success "Network isolation rules are configured"
        else
            log_failure "Network isolation rules not found"
        fi
    else
        log_info "Single-LAN mode (skipping isolation tests)"
        ((TOTAL_TESTS++))  # Count as neutral
    fi
}

# Summary
show_summary() {
    echo
    echo "========================================"
    echo "         Test Summary"
    echo "========================================"
    echo -e "Total Tests:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
    else
        echo -e "Failed:       $FAILED_TESTS"
    fi
    echo "========================================"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All tests passed! Router is working correctly."
        exit 0
    else
        log_warning "$FAILED_TESTS test(s) failed. Check the output above for details."
        exit 1
    fi
}

# Main
main() {
    echo "========================================"
    echo "   NixOS Router Automated Testing"
    echo "========================================"
    echo "Testing router at: $ROUTER_IP:$ROUTER_SSH_PORT"
    echo
    
    test_ssh
    test_services
    test_interfaces
    test_dns
    test_internet
    test_grafana
    test_firewall
    test_dhcp
    test_optimizations
    test_isolation
    
    show_summary
}

main "$@"

