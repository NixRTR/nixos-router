#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates and manages test client VMs for router testing
.DESCRIPTION
    Creates small Alpine Linux VMs to test DHCP and network connectivity
.PARAMETER Name
    Name of the client VM
.PARAMETER LANSwitch
    LAN switch to connect to (NixOS-Router-LAN1 through LAN4)
.PARAMETER Action
    Action to perform: Create, Start, Stop, Delete, Connect
.EXAMPLE
    .\Test-ClientVM.ps1 -Name "Client1" -LANSwitch "NixOS-Router-LAN1" -Action Create
.EXAMPLE
    .\Test-ClientVM.ps1 -Name "Client1" -Action Start
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("NixOS-Router-LAN1", "NixOS-Router-LAN2", "NixOS-Router-LAN3", "NixOS-Router-LAN4")]
    [string]$LANSwitch = "NixOS-Router-LAN1",
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Start", "Stop", "Delete", "Connect", "Status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

# Configuration
$VMName = "NixOS-Router-$Name"
$VMMemory = 512MB
$VMProcessors = 1
$VHDSize = 2GB
$ScriptPath = $PSScriptRoot
$VMPath = Join-Path $ScriptPath "VMs"
$AlpineISOPath = Join-Path $ScriptPath "ISOs\alpine-virt.iso"
$VHDPath = Join-Path $VMPath "$VMName.vhdx"

# Colors
function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Blue
}

function Write-Success($message) {
    Write-Host "[SUCCESS] $message" -ForegroundColor Green
}

function Write-Failure($message) {
    Write-Host "[ERROR] $message" -ForegroundColor Red
}

function Write-Warning2($message) {
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

# Check if VM exists
function Test-VMExists {
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    return $null -ne $vm
}

# Create VM
function New-ClientVM {
    Write-Info "Creating test client VM '$VMName'..."
    
    if (Test-VMExists) {
        Write-Failure "VM '$VMName' already exists"
        Write-Info "Delete it first with: .\Test-ClientVM.ps1 -Name '$Name' -Action Delete"
        return
    }
    
    # Check for Alpine ISO and offer to download
    if (-not (Test-Path $AlpineISOPath)) {
        Write-Warning2 "Alpine Linux ISO not found: $AlpineISOPath"
        $response = Read-Host "Download Alpine Linux ISO (~50MB)? (y/N)"
        
        if ($response -match "^[Yy]$") {
            Write-Info "Downloading Alpine Linux ISO..."
            
            $alpineUrl = "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso"
            
            try {
                # Use BITS transfer
                Import-Module BitsTransfer
                Start-BitsTransfer -Source $alpineUrl -Destination $AlpineISOPath -Description "Downloading Alpine Linux ISO" -DisplayName "Alpine ISO Download"
                Write-Success "Alpine Linux ISO downloaded successfully"
            }
            catch {
                Write-Warning2 "BITS transfer failed, trying WebClient..."
                try {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($alpineUrl, $AlpineISOPath)
                    Write-Success "Alpine Linux ISO downloaded successfully"
                }
                catch {
                    Write-Failure "Failed to download ISO: $_"
                    Write-Info "Please download manually from: $alpineUrl"
                    Write-Info "Save to: $AlpineISOPath"
                    
                    $response2 = Read-Host "Continue without ISO? VM will not boot (y/N)"
                    if ($response2 -notmatch "^[Yy]$") {
                        return
                    }
                }
            }
        } else {
            Write-Info "Skipped. Download manually from: https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso"
            Write-Info "Save to: $AlpineISOPath"
            
            $response2 = Read-Host "Continue without ISO? VM will not boot (y/N)"
            if ($response2 -notmatch "^[Yy]$") {
                return
            }
        }
    }
    
    # Create VM directory
    if (-not (Test-Path $VMPath)) {
        New-Item -ItemType Directory -Path $VMPath | Out-Null
    }
    
    # Create VHD
    Write-Info "Creating virtual hard disk..."
    New-VHD -Path $VHDPath -SizeBytes $VHDSize -Dynamic | Out-Null
    Write-Success "VHD created"
    
    # Create VM
    Write-Info "Creating VM..."
    $vm = New-VM -Name $VMName `
        -MemoryStartupBytes $VMMemory `
        -Generation 2 `
        -VHDPath $VHDPath `
        -Path $VMPath
    
    # Configure VM
    Set-VM -VM $vm -ProcessorCount $VMProcessors -AutomaticCheckpointsEnabled $false
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
    
    # Disable Secure Boot
    Set-VMFirmware -VM $vm -EnableSecureBoot Off
    
    # Add DVD drive with ISO (if available)
    if (Test-Path $AlpineISOPath) {
        Add-VMDvdDrive -VM $vm -Path $AlpineISOPath
        
        # Set boot order (DVD first)
        $dvd = Get-VMDvdDrive -VM $vm
        Set-VMFirmware -VM $vm -FirstBootDevice $dvd
    }
    
    # Connect to LAN switch
    $switch = Get-VMSwitch -Name $LANSwitch -ErrorAction SilentlyContinue
    if ($null -ne $switch) {
        Write-Info "Connecting to $LANSwitch..."
        Add-VMNetworkAdapter -VM $vm -SwitchName $LANSwitch -Name "LAN"
        Write-Success "Connected to $LANSwitch"
    } else {
        Write-Failure "Switch '$LANSwitch' not found"
        Write-Info "Run Setup-HyperV.ps1 to create switches"
        return
    }
    
    Write-Success "Client VM '$VMName' created successfully!"
    Write-Info "Configuration:"
    Write-Host "  - Memory: $($VMMemory / 1MB)MB"
    Write-Host "  - Processors: $VMProcessors"
    Write-Host "  - Network: $LANSwitch"
    Write-Host ""
    Write-Info "Start the VM with: .\Test-ClientVM.ps1 -Name '$Name' -Action Start"
}

# Start VM
function Start-ClientVM {
    Write-Info "Starting VM '$VMName'..."
    
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        Write-Info "Create it first with: .\Test-ClientVM.ps1 -Name '$Name' -LANSwitch '$LANSwitch' -Action Create"
        return
    }
    
    $vm = Get-VM -Name $VMName
    
    if ($vm.State -eq "Running") {
        Write-Success "VM is already running"
        return
    }
    
    Start-VM -Name $VMName
    Write-Success "VM started"
    Write-Info "Connect with: .\Test-ClientVM.ps1 -Name '$Name' -Action Connect"
}

# Stop VM
function Stop-ClientVM {
    Write-Info "Stopping VM '$VMName'..."
    
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    $vm = Get-VM -Name $VMName
    
    if ($vm.State -eq "Off") {
        Write-Success "VM is already stopped"
        return
    }
    
    Stop-VM -Name $VMName -Force
    Write-Success "VM stopped"
}

# Delete VM
function Remove-ClientVM {
    Write-Info "Deleting VM '$VMName'..."
    
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    # Stop VM if running
    $vm = Get-VM -Name $VMName
    if ($vm.State -ne "Off") {
        Write-Info "Stopping VM..."
        Stop-VM -Name $VMName -Force
    }
    
    # Remove VM
    Remove-VM -Name $VMName -Force
    
    # Remove VHD
    if (Test-Path $VHDPath) {
        Remove-Item $VHDPath -Force
    }
    
    Write-Success "VM '$VMName' deleted"
}

# Show VM status
function Show-ClientVMStatus {
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    $vm = Get-VM -Name $VMName
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  VM Status: $VMName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "State:       $($vm.State)"
    Write-Host "Memory:      $($vm.MemoryAssigned / 1MB)MB"
    Write-Host "Processors:  $($vm.ProcessorCount)"
    Write-Host ""
    
    $adapters = Get-VMNetworkAdapter -VM $vm
    foreach ($adapter in $adapters) {
        Write-Host "Network:     $($adapter.SwitchName)"
    }
    Write-Host ""
}

# Connect to VM console
function Connect-ClientVM {
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    Write-Info "Opening VM console..."
    vmconnect.exe localhost $VMName
}

# Main
switch ($Action) {
    "Create" { New-ClientVM }
    "Start" { Start-ClientVM }
    "Stop" { Stop-ClientVM }
    "Delete" { Remove-ClientVM }
    "Status" { Show-ClientVMStatus }
    "Connect" { Connect-ClientVM }
}

