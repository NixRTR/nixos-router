#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cleans up all test VMs and files for NixOS router testing
.DESCRIPTION
    Stops and removes all test VMs, deletes VHDs, and optionally removes ISOs and virtual switches
.PARAMETER KeepISOs
    Keep downloaded ISO files (default: false)
.PARAMETER KeepSwitches
    Keep virtual switches (default: false)
.PARAMETER Force
    Skip confirmation prompts (default: false)
.EXAMPLE
    .\Cleanup-TestEnvironment.ps1
.EXAMPLE
    .\Cleanup-TestEnvironment.ps1 -KeepISOs -KeepSwitches
.EXAMPLE
    .\Cleanup-TestEnvironment.ps1 -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$KeepISOs = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepSwitches = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"

# Configuration
$ScriptPath = $PSScriptRoot
$VMPath = Join-Path $ScriptPath "VMs"
$ISOPath = Join-Path $ScriptPath "ISOs"

# Colors
function Write-Info($message) {
    Write-Host "[INFO] $message" -ForegroundColor Blue
}

function Write-Success($message) {
    Write-Host "[SUCCESS] $message" -ForegroundColor Green
}

function Write-Warning2($message) {
    Write-Host "[WARNING] $message" -ForegroundColor Yellow
}

function Write-Error2($message) {
    Write-Host "[ERROR] $message" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  NixOS Router Test Cleanup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Confirmation
if (-not $Force) {
    Write-Warning2 "This will delete all test VMs and their data!"
    if (-not $KeepISOs) {
        Write-Warning2 "Downloaded ISOs will also be deleted!"
    }
    if (-not $KeepSwitches) {
        Write-Warning2 "Virtual switches will also be deleted!"
    }
    Write-Host ""
    $response = Read-Host "Are you sure you want to continue? (yes/N)"
    
    if ($response -ne "yes") {
        Write-Info "Cleanup cancelled"
        exit 0
    }
}

Write-Host ""
Write-Info "Starting cleanup..."
Write-Host ""

# Count what we're cleaning
$vmsRemoved = 0
$vhdsRemoved = 0
$isosRemoved = 0
$switchesRemoved = 0

# Find and remove all test VMs
Write-Info "Looking for test VMs..."
$allVMs = Get-VM -ErrorAction SilentlyContinue

if ($allVMs) {
    $testVMs = $allVMs | Where-Object { $_.Name -like "NixOS-Router-*" }
    
    if ($testVMs) {
        foreach ($vm in $testVMs) {
            Write-Info "Processing VM: $($vm.Name)"
            
            # Stop VM if running
            if ($vm.State -ne "Off") {
                Write-Info "  Stopping VM..."
                Stop-VM -Name $vm.Name -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
            
            # Remove VM
            Write-Info "  Removing VM..."
            Remove-VM -Name $vm.Name -Force -ErrorAction SilentlyContinue
            
            if ($?) {
                Write-Success "  Removed: $($vm.Name)"
                $vmsRemoved++
            } else {
                Write-Error2 "  Failed to remove: $($vm.Name)"
            }
        }
    } else {
        Write-Info "No test VMs found"
    }
} else {
    Write-Info "No VMs found"
}

Write-Host ""

# Remove VHD files
Write-Info "Looking for VHD files..."
if (Test-Path $VMPath) {
    $vhds = Get-ChildItem -Path $VMPath -Include "*.vhdx","*.vhd" -Recurse -ErrorAction SilentlyContinue
    
    if ($vhds) {
        foreach ($vhd in $vhds) {
            Write-Info "  Removing: $($vhd.Name)"
            Remove-Item $vhd.FullName -Force -ErrorAction SilentlyContinue
            
            if ($?) {
                Write-Success "  Deleted: $($vhd.Name)"
                $vhdsRemoved++
            } else {
                Write-Error2 "  Failed to delete: $($vhd.Name)"
            }
        }
    } else {
        Write-Info "No VHD files found"
    }
    
    # Remove VM directories
    Write-Info "Cleaning up VM directories..."
    $vmDirs = Get-ChildItem -Path $VMPath -Directory -ErrorAction SilentlyContinue
    
    foreach ($dir in $vmDirs) {
        Write-Info "  Removing directory: $($dir.Name)"
        Remove-Item $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Info "VMs directory does not exist"
}

Write-Host ""

# Remove ISOs (optional)
if (-not $KeepISOs) {
    Write-Info "Looking for ISO files..."
    if (Test-Path $ISOPath) {
        $isos = Get-ChildItem -Path $ISOPath -Filter "*.iso" -ErrorAction SilentlyContinue
        
        if ($isos) {
            foreach ($iso in $isos) {
                Write-Info "  Removing: $($iso.Name) ($(([Math]::Round($iso.Length / 1MB, 2))) MB)"
                Remove-Item $iso.FullName -Force -ErrorAction SilentlyContinue
                
                if ($?) {
                    Write-Success "  Deleted: $($iso.Name)"
                    $isosRemoved++
                } else {
                    Write-Error2 "  Failed to delete: $($iso.Name)"
                }
            }
        } else {
            Write-Info "No ISO files found"
        }
    } else {
        Write-Info "ISOs directory does not exist"
    }
} else {
    Write-Info "Keeping ISO files (use -KeepISOs:$false to remove them)"
}

Write-Host ""

# Remove virtual switches (optional)
if (-not $KeepSwitches) {
    Write-Info "Looking for test virtual switches..."
    $switches = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "NixOS-Router-*" }
    
    if ($switches) {
        foreach ($switch in $switches) {
            Write-Info "  Removing switch: $($switch.Name)"
            Remove-VMSwitch -Name $switch.Name -Force -ErrorAction SilentlyContinue
            
            if ($?) {
                Write-Success "  Removed: $($switch.Name)"
                $switchesRemoved++
            } else {
                Write-Error2 "  Failed to remove: $($switch.Name)"
            }
        }
    } else {
        Write-Info "No test virtual switches found"
    }
} else {
    Write-Info "Keeping virtual switches (use -KeepSwitches:$false to remove them)"
}

Write-Host ""

# Clean up empty directories
Write-Info "Cleaning up empty directories..."
if ((Test-Path $VMPath) -and ((Get-ChildItem $VMPath -ErrorAction SilentlyContinue).Count -eq 0)) {
    Remove-Item $VMPath -Force -ErrorAction SilentlyContinue
    Write-Success "Removed empty VMs directory"
}

if ((Test-Path $ISOPath) -and ((Get-ChildItem $ISOPath -ErrorAction SilentlyContinue).Count -eq 0)) {
    Remove-Item $ISOPath -Force -ErrorAction SilentlyContinue
    Write-Success "Removed empty ISOs directory"
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "         Cleanup Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VMs removed:        $vmsRemoved"
Write-Host "VHDs deleted:       $vhdsRemoved"
Write-Host "ISOs deleted:       $isosRemoved"
Write-Host "Switches removed:   $switchesRemoved"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($vmsRemoved -gt 0 -or $vhdsRemoved -gt 0) {
    Write-Success "Cleanup completed successfully!"
} else {
    Write-Info "Nothing to clean up"
}

Write-Host ""
Write-Info "Test environment has been cleaned"
if ($KeepISOs) {
    Write-Info "ISOs were kept for future tests"
}
if ($KeepSwitches) {
    Write-Info "Virtual switches were kept for future tests"
}
Write-Host ""

