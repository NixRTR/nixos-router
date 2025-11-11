<#
.SYNOPSIS
    Automated testing script for NixOS router
.DESCRIPTION
    Runs automated tests on the router VM to verify functionality
.PARAMETER RouterIP
    IP address of the router (default: auto-detect from VM)
.PARAMETER SSHPort
    SSH port to connect to (default: 22)
.EXAMPLE
    .\Test-Router.ps1
.EXAMPLE
    .\Test-Router.ps1 -RouterIP "192.168.1.1" -SSHPort 22
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$RouterIP = "",
    
    [Parameter(Mandatory=$false)]
    [int]$SSHPort = 22,
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "routeradmin"
)

$ErrorActionPreference = "Continue"  # Continue on errors for test reporting

# Test counters
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

# Colors
function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Blue
}

function Write-TestSuccess($message) {
    Write-Host "[PASS] $message" -ForegroundColor Green
    $script:PassedTests++
    $script:TotalTests++
}

function Write-TestFailure($message) {
    Write-Host "[FAIL] $message" -ForegroundColor Red
    $script:FailedTests++
    $script:TotalTests++
}

function Write-Warning2($message) {
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NixOS Router Automated Testing" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if SSH is available
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue
if ($null -eq $sshAvailable) {
    Write-Warning2 "SSH client not found. Some tests will be skipped."
    Write-Info "Install OpenSSH client: Settings > Apps > Optional Features > OpenSSH Client"
}

# Get router IP from Hyper-V if not specified
if ([string]::IsNullOrEmpty($RouterIP)) {
    Write-Info "Auto-detecting router IP from VM..."
    $vm = Get-VM -Name "NixOS-Router-Test" -ErrorAction SilentlyContinue
    
    if ($null -eq $vm) {
        Write-TestFailure "VM 'NixOS-Router-Test' not found"
        Write-Info "Create VM with: .\Test-RouterVM.ps1 -Action Create"
        exit 1
    }
    
    if ($vm.State -ne "Running") {
        Write-TestFailure "VM is not running (State: $($vm.State))"
        Write-Info "Start VM with: .\Test-RouterVM.ps1 -Action Start"
        exit 1
    }
    
    # Try to get IP from first network adapter
    $adapters = Get-VMNetworkAdapter -VM $vm
    foreach ($adapter in $adapters) {
        if ($adapter.IPAddresses.Count -gt 0) {
            # Get first IPv4 address
            $ipv4 = $adapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
            if ($null -ne $ipv4 -and $ipv4 -ne "0.0.0.0") {
                $RouterIP = $ipv4
                Write-Info "Detected router IP: $RouterIP"
                break
            }
        }
    }
    
    if ([string]::IsNullOrEmpty($RouterIP)) {
        Write-Warning2 "Could not auto-detect router IP"
        Write-Info "Please specify manually: .\Test-Router.ps1 -RouterIP <ip>"
        Write-Info "Or check the router console for its IP address"
        exit 1
    }
} else {
    Write-Info "Using specified router IP: $RouterIP"
}

Write-Info "Testing router at: ${RouterIP}:${SSHPort}"
Write-Host ""

# Test 1: Ping connectivity
Write-Info "Test 1: Network Connectivity"
$pingResult = Test-Connection -ComputerName $RouterIP -Count 2 -Quiet
if ($pingResult) {
    Write-TestSuccess "Router is reachable via ping"
} else {
    Write-TestFailure "Cannot ping router"
}

# Test 2: SSH connectivity
if ($null -ne $sshAvailable) {
    Write-Host ""
    Write-Info "Test 2: SSH Connectivity"
    
    # Try SSH connection (with timeout)
    $sshTest = ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSHPort "${Username}@${RouterIP}" "echo 'SSH test successful'" 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-TestSuccess "SSH connection works"
    } else {
        Write-TestFailure "SSH connection failed"
        Write-Warning2 "Make sure you've configured SSH keys or password authentication"
    }
    
    # Helper function to run SSH command
    function Invoke-SSHCommand {
        param([string]$Command)
        
        $result = ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p $SSHPort "${Username}@${RouterIP}" "$Command" 2>$null
        return @{
            Output = $result
            Success = ($LASTEXITCODE -eq 0)
        }
    }
    
    # Test 3: System services
    Write-Host ""
    Write-Info "Test 3: System Services"
    
    $services = @("systemd-networkd", "blocky", "kea-dhcp4-server", "grafana", "prometheus")
    
    foreach ($service in $services) {
        $result = Invoke-SSHCommand "systemctl is-active $service"
        
        if ($result.Success -and $result.Output -eq "active") {
            Write-TestSuccess "$service is running"
        } else {
            Write-TestFailure "$service is not running"
        }
    }
    
    # Test 4: Network interfaces
    Write-Host ""
    Write-Info "Test 4: Network Interfaces"
    
    # Check WAN interface
    $result = Invoke-SSHCommand "ip addr show | grep -c 'inet.*eth0'"
    if ($result.Success -and [int]$result.Output -gt 0) {
        Write-TestSuccess "WAN interface has IP address"
    } else {
        Write-TestFailure "WAN interface has no IP address"
    }
    
    # Check br0 exists
    $result = Invoke-SSHCommand "ip link show br0"
    if ($result.Success) {
        Write-TestSuccess "Bridge br0 exists"
    } else {
        Write-TestFailure "Bridge br0 does not exist"
    }
    
    # Test 5: DNS resolution
    Write-Host ""
    Write-Info "Test 5: DNS Resolution"
    
    $result = Invoke-SSHCommand "dig google.com @127.0.0.1 +short +time=5 2>/dev/null | head -1"
    if ($result.Success -and $result.Output -match '^\d+\.\d+\.\d+\.\d+$') {
        Write-TestSuccess "DNS resolution works"
    } else {
        Write-TestFailure "DNS resolution failed"
    }
    
    # Test 6: Internet connectivity
    Write-Host ""
    Write-Info "Test 6: Internet Connectivity"
    
    $result = Invoke-SSHCommand "ping -c 1 -W 5 1.1.1.1"
    if ($result.Success) {
        Write-TestSuccess "Internet connectivity works"
    } else {
        Write-TestFailure "No internet connectivity"
    }
    
    # Test 7: Firewall/NAT
    Write-Host ""
    Write-Info "Test 7: Firewall/NAT Configuration"
    
    # Check NAT
    $result = Invoke-SSHCommand "sudo iptables -t nat -L POSTROUTING -n | grep -c MASQUERADE"
    if ($result.Success -and [int]$result.Output -gt 0) {
        Write-TestSuccess "NAT masquerading is configured"
    } else {
        Write-TestFailure "NAT masquerading not configured"
    }
    
    # Check IP forwarding
    $result = Invoke-SSHCommand "cat /proc/sys/net/ipv4/ip_forward"
    if ($result.Success -and $result.Output -eq "1") {
        Write-TestSuccess "IP forwarding is enabled"
    } else {
        Write-TestFailure "IP forwarding is not enabled"
    }
    
    # Test 8: DHCP server
    Write-Host ""
    Write-Info "Test 8: DHCP Server Configuration"
    
    $result = Invoke-SSHCommand "test -f /etc/kea/dhcp4.conf && echo 'exists'"
    if ($result.Success -and $result.Output -eq "exists") {
        Write-TestSuccess "DHCP configuration file exists"
    } else {
        Write-TestFailure "DHCP configuration file not found"
    }
    
    # Test 9: Performance optimizations
    Write-Host ""
    Write-Info "Test 9: Performance Optimizations"
    
    # Check BBR
    $result = Invoke-SSHCommand "sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -o bbr"
    if ($result.Success -and $result.Output -eq "bbr") {
        Write-TestSuccess "BBR congestion control enabled"
    } else {
        Write-TestFailure "BBR not enabled"
    }
    
    # Check MSS clamping
    $result = Invoke-SSHCommand "sudo iptables -t mangle -L FORWARD -n | grep -c TCPMSS"
    if ($result.Success -and [int]$result.Output -gt 0) {
        Write-TestSuccess "MSS clamping configured"
    } else {
        Write-TestFailure "MSS clamping not configured"
    }
    
    # Test 10: Network isolation (if multi-LAN mode)
    Write-Host ""
    Write-Info "Test 10: Network Isolation (if enabled)"
    
    $result = Invoke-SSHCommand "ip link show br1"
    if ($result.Success) {
        Write-Info "Multi-LAN mode detected (br0 and br1)"
        
        # Check isolation rules
        $result = Invoke-SSHCommand "sudo iptables -L FORWARD -n | grep -c 'br0.*br1.*DROP'"
        if ($result.Success -and [int]$result.Output -gt 0) {
            Write-TestSuccess "Network isolation rules are configured"
        } else {
            Write-TestFailure "Network isolation rules not found"
        }
    } else {
        Write-Info "Single-LAN mode (skipping isolation tests)"
        $script:TotalTests++  # Count as neutral
    }
} else {
    Write-Host ""
    Write-Warning2 "SSH client not available - skipping SSH-based tests"
    Write-Info "Install OpenSSH: Settings > Apps > Optional Features > OpenSSH Client"
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "         Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests:  $script:TotalTests"
Write-Host "Passed:       " -NoNewline
Write-Host "$script:PassedTests" -ForegroundColor Green
Write-Host "Failed:       " -NoNewline
if ($script:FailedTests -gt 0) {
    Write-Host "$script:FailedTests" -ForegroundColor Red
} else {
    Write-Host "$script:FailedTests"
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($script:FailedTests -eq 0) {
    Write-Host "[SUCCESS] All tests passed! Router is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Warning2 "$script:FailedTests tests failed. Check the output above for details."
    exit 1
}

