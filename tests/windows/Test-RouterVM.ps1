#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Manages NixOS router test VM on Hyper-V
.DESCRIPTION
    Creates, starts, stops, and manages the NixOS router test VM
.PARAMETER Action
    Action to perform: Create, Start, Stop, Delete, Status
.EXAMPLE
    .\Test-RouterVM.ps1 -Action Create
.EXAMPLE
    .\Test-RouterVM.ps1 -Action Start
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "Start", "Stop", "Delete", "Status", "Connect")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

# Configuration
$VMName = "NixOS-Router-Test"
$VMMemory = 4GB
$VMProcessors = 4
$VHDSize = 20GB
$ScriptPath = $PSScriptRoot
$VMPath = Join-Path $ScriptPath "VMs"
$ISOPath = Join-Path $ScriptPath "ISOs\nixos-minimal.iso"
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
function New-RouterVM {
    Write-Info "Creating NixOS Router Test VM..."
    
    if (Test-VMExists) {
        Write-Failure "VM '$VMName' already exists"
        Write-Info "Delete it first with: .\Test-RouterVM.ps1 -Action Delete"
        return
    }
    
    # Check for ISO and offer to download
    if (-not (Test-Path $ISOPath)) {
        Write-Warning2 "NixOS ISO not found: $ISOPath"
        $response = Read-Host "Download NixOS ISO (~1GB)? (y/N)"
        
        if ($response -match "^[Yy]$") {
            Write-Info "Downloading NixOS ISO..."
            Write-Info "This may take several minutes..."
            
            $isoUrl = "https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso"
            
            try {
                # Use BITS transfer for better reliability
                Import-Module BitsTransfer
                Start-BitsTransfer -Source $isoUrl -Destination $ISOPath -Description "Downloading NixOS ISO" -DisplayName "NixOS ISO Download"
                Write-Success "NixOS ISO downloaded successfully"
            }
            catch {
                Write-Warning2 "BITS transfer failed, trying WebClient..."
                try {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.DownloadFile($isoUrl, $ISOPath)
                    Write-Success "NixOS ISO downloaded successfully"
                }
                catch {
                    Write-Failure "Failed to download ISO: $_"
                    Write-Info "Please download manually from: $isoUrl"
                    Write-Info "Save to: $ISOPath"
                    return
                }
            }
        } else {
            Write-Failure "ISO is required to create VM"
            Write-Info "Download from: https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso"
            Write-Info "Save to: $ISOPath"
            return
        }
    }
    
    # Create VM directory
    if (-not (Test-Path $VMPath)) {
        New-Item -ItemType Directory -Path $VMPath | Out-Null
    }
    
    # Create VHD
    Write-Info "Creating virtual hard disk ($VHDSize)..."
    New-VHD -Path $VHDPath -SizeBytes $VHDSize -Dynamic | Out-Null
    Write-Success "VHD created: $VHDPath"
    
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
    
    # Disable Secure Boot (for NixOS compatibility)
    Set-VMFirmware -VM $vm -EnableSecureBoot Off
    
    # Add DVD drive with ISO
    Add-VMDvdDrive -VM $vm -Path $ISOPath
    
    # Set boot order (DVD first)
    $dvd = Get-VMDvdDrive -VM $vm
    Set-VMFirmware -VM $vm -FirstBootDevice $dvd
    
    # Network configuration
    # WAN adapter (Default Switch or first available external switch)
    $wanSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
    if ($null -eq $wanSwitch) {
        $wanSwitch = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
    }
    if ($null -eq $wanSwitch) {
        $wanSwitch = Get-VMSwitch -Name "NixOS-Router-WAN" -ErrorAction SilentlyContinue
    }
    
    if ($null -ne $wanSwitch) {
        Write-Info "Adding WAN adapter (using $($wanSwitch.Name))..."
        Add-VMNetworkAdapter -VM $vm -SwitchName $wanSwitch.Name -Name "WAN"
        Write-Success "WAN adapter added"
    } else {
        Write-Warning2 "No suitable WAN switch found"
    }
    
    # LAN adapters
    $lanSwitches = @("NixOS-Router-LAN1", "NixOS-Router-LAN2", "NixOS-Router-LAN3", "NixOS-Router-LAN4")
    $lanNames = @("LAN1", "LAN2", "LAN3", "LAN4")
    
    for ($i = 0; $i -lt $lanSwitches.Count; $i++) {
        $switchName = $lanSwitches[$i]
        $adapterName = $lanNames[$i]
        
        $switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
        if ($null -ne $switch) {
            Write-Info "Adding $adapterName adapter..."
            Add-VMNetworkAdapter -VM $vm -SwitchName $switchName -Name $adapterName
            Write-Success "$adapterName adapter added"
        } else {
            Write-Warning2 "Switch $switchName not found, skipping $adapterName"
        }
    }
    
    Write-Success "VM '$VMName' created successfully!"
    Write-Info "Configuration:"
    Write-Host "  - Memory: $($VMMemory / 1GB)GB"
    Write-Host "  - Processors: $VMProcessors"
    Write-Host "  - Disk: $VHDSize"
    Write-Host "  - Network: 1 WAN + 4 LAN adapters"
    Write-Host ""
    Write-Info "Start the VM with: .\Test-RouterVM.ps1 -Action Start"
}

# Start VM
function Start-RouterVM {
    Write-Info "Starting VM '$VMName'..."
    
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        Write-Info "Create it first with: .\Test-RouterVM.ps1 -Action Create"
        return
    }
    
    $vm = Get-VM -Name $VMName
    
    if ($vm.State -eq "Running") {
        Write-Success "VM is already running"
        Write-Info "Connect with: .\Test-RouterVM.ps1 -Action Connect"
        return
    }
    
    Start-VM -Name $VMName
    Write-Success "VM started"
    Write-Info "Open Hyper-V Manager to connect to the console"
    Write-Info "Or use: .\Test-RouterVM.ps1 -Action Connect"
}

# Stop VM
function Stop-RouterVM {
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
function Remove-RouterVM {
    Write-Info "Deleting VM '$VMName'..."
    
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    $response = Read-Host "Are you sure you want to delete VM '$VMName'? This will delete all data (y/N)"
    
    if ($response -notmatch "^[Yy]$") {
        Write-Info "Cancelled"
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
        Write-Info "Removing VHD..."
        Remove-Item $VHDPath -Force
    }
    
    Write-Success "VM '$VMName' deleted"
}

# Show VM status
function Show-RouterVMStatus {
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        Write-Info "Create it with: .\Test-RouterVM.ps1 -Action Create"
        return
    }
    
    $vm = Get-VM -Name $VMName
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  VM Status: $VMName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "State:       $($vm.State)"
    Write-Host "Memory:      $($vm.MemoryAssigned / 1GB)GB / $($vm.MemoryStartup / 1GB)GB"
    Write-Host "Processors:  $($vm.ProcessorCount)"
    Write-Host "Uptime:      $($vm.Uptime)"
    Write-Host ""
    
    Write-Host "Network Adapters:" -ForegroundColor Yellow
    $adapters = Get-VMNetworkAdapter -VM $vm
    foreach ($adapter in $adapters) {
        Write-Host "  - $($adapter.Name): $($adapter.SwitchName)"
    }
    Write-Host ""
}

# Connect to VM console
function Connect-RouterVM {
    if (-not (Test-VMExists)) {
        Write-Failure "VM '$VMName' does not exist"
        return
    }
    
    Write-Info "Opening VM console..."
    vmconnect.exe localhost $VMName
}

# Main
switch ($Action) {
    "Create" { New-RouterVM }
    "Start" { Start-RouterVM }
    "Stop" { Stop-RouterVM }
    "Delete" { Remove-RouterVM }
    "Status" { Show-RouterVMStatus }
    "Connect" { Connect-RouterVM }
}

