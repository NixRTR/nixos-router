#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets up Hyper-V for NixOS router testing on Windows
.DESCRIPTION
    Checks and enables Hyper-V, creates virtual switches, and prepares the environment
.EXAMPLE
    .\Setup-HyperV.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

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

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NixOS Router Testing Setup (Hyper-V)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Failure "This script must be run as Administrator"
    exit 1
}

# Check Windows version
Write-Info "Checking Windows version..."
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -lt 10) {
    Write-Failure "Windows 10 or later is required"
    exit 1
}
Write-Success "Windows version: $($osVersion.Major).$($osVersion.Minor)"

# Check Hyper-V feature
Write-Info "Checking Hyper-V status..."
$hypervFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

if ($hypervFeature.State -eq "Enabled") {
    Write-Success "Hyper-V is already enabled"
} else {
    Write-Warning2 "Hyper-V is not enabled"
    $response = Read-Host "Would you like to enable Hyper-V? This will require a reboot (y/N)"
    
    if ($response -match "^[Yy]$") {
        Write-Info "Enabling Hyper-V..."
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
        Write-Success "Hyper-V enabled"
        Write-Warning2 "Please reboot your computer and run this script again"
        exit 0
    } else {
        Write-Failure "Hyper-V is required for testing"
        exit 1
    }
}

# Check Hyper-V PowerShell module
Write-Info "Checking Hyper-V PowerShell module..."
if (Get-Module -ListAvailable -Name Hyper-V) {
    Write-Success "Hyper-V PowerShell module is available"
    Import-Module Hyper-V
} else {
    Write-Failure "Hyper-V PowerShell module not found"
    Write-Info "Install with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell"
    exit 1
}

# Create virtual switches
Write-Info "Setting up virtual switches..."

# WAN switch (uses Default Switch or creates External switch)
$wanSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if ($null -eq $wanSwitch) {
    Write-Info "Default Switch not found, looking for External switches..."
    $externalSwitches = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" }
    
    if ($externalSwitches.Count -gt 0) {
        $wanSwitch = $externalSwitches[0]
        Write-Success "Using external switch: $($wanSwitch.Name)"
    } else {
        Write-Warning2 "No external switch found. Creating internal switch for WAN..."
        New-VMSwitch -Name "NixOS-Router-WAN" -SwitchType Internal | Out-Null
        Write-Success "Created internal switch: NixOS-Router-WAN"
    }
} else {
    Write-Success "Using Default Switch for WAN"
}

# LAN switches (Internal for testing)
$lanSwitches = @("NixOS-Router-LAN1", "NixOS-Router-LAN2", "NixOS-Router-LAN3", "NixOS-Router-LAN4")

foreach ($switchName in $lanSwitches) {
    $switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
    
    if ($null -eq $switch) {
        Write-Info "Creating switch: $switchName"
        New-VMSwitch -Name $switchName -SwitchType Internal | Out-Null
        Write-Success "Created: $switchName"
    } else {
        Write-Success "Switch already exists: $switchName"
    }
}

# Create directories
Write-Info "Creating directories..."
$scriptPath = $PSScriptRoot
$isoPath = Join-Path $scriptPath "ISOs"
$vmPath = Join-Path $scriptPath "VMs"

if (-not (Test-Path $isoPath)) {
    New-Item -ItemType Directory -Path $isoPath | Out-Null
    Write-Success "Created: ISOs directory"
} else {
    Write-Success "ISOs directory exists"
}

if (-not (Test-Path $vmPath)) {
    New-Item -ItemType Directory -Path $vmPath | Out-Null
    Write-Success "Created: VMs directory"
} else {
    Write-Success "VMs directory exists"
}

# Download NixOS ISO
$nixosIso = Join-Path $isoPath "nixos-minimal.iso"
$nixosIsoUrl = "https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso"

if (-not (Test-Path $nixosIso)) {
    Write-Info "NixOS ISO not found"
    $response = Read-Host "Download NixOS ISO (~1GB)? (y/N)"
    
    if ($response -match "^[Yy]$") {
        Write-Info "Downloading NixOS ISO from: $nixosIsoUrl"
        Write-Info "This may take several minutes..."
        
        try {
            # Use BITS transfer for better reliability and progress
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $nixosIsoUrl -Destination $nixosIso -Description "Downloading NixOS ISO" -DisplayName "NixOS ISO Download"
            Write-Success "NixOS ISO downloaded successfully"
        }
        catch {
            Write-Warning2 "BITS transfer failed, trying WebClient..."
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($nixosIsoUrl, $nixosIso)
                Write-Success "NixOS ISO downloaded successfully"
            }
            catch {
                Write-Failure "Failed to download ISO: $_"
                Write-Info "Please download manually from: $nixosIsoUrl"
                Write-Info "Save to: $nixosIso"
            }
        }
    } else {
        Write-Info "Skipped. Download manually from: $nixosIsoUrl"
        Write-Info "Save to: $nixosIso"
    }
} else {
    Write-Success "NixOS ISO found"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "         Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $nixosIso)) {
    Write-Warning2 "NixOS ISO not downloaded yet"
    Write-Info "Run this script again and choose 'y' to download the ISO"
    Write-Host ""
}

Write-Success "Hyper-V environment is ready for testing!"
Write-Info "See README.md for next steps and detailed instructions"
Write-Host ""

