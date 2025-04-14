<#
    Title: Modular System Maintenance and Update Script
    Description: This script is organized into modular functions, each responsible for a separate system 
                 maintenance and update task. It covers:
                    - Repairing Windows Store Apps
                    - Scanning for Windows Updates
                    - Checking and optimizing fixed volumes
                    - Downloading and installing Windows Updates
                    - Running Windows updates via the PSWindowsUpdate module
                    - Updating installed applications using winget
                    - Scanning and repairing system files (DISM and SFC)
                    - Updating Windows Defender and executing a quick scan
                    - Cleaning up disk space
    Note: Run this script in an elevated (Administrator) PowerShell session.
#>

function Repair-WindowsStoreApps {
    <#
    .SYNOPSIS
        Repairs Windows Store Apps by resetting the Windows Store cache.
    
    .DESCRIPTION
        This function launches the Windows Store reset utility (wsreset.exe) to clear and repair 
        Windows Store apps. It waits for the process to complete and adds a brief pause afterwards.
    #>
    Write-Host "[Repair-WindowsStoreApps] Repairing Windows Store Apps..."
    try {
        Start-Process -FilePath "wsreset.exe" -NoNewWindow -Wait
        Start-Sleep -Seconds 5
    } catch {
        Write-Warning "Failed to run wsreset.exe: $_"
    }
}

function Check-WindowsUpdatesScan {
    <#
    .SYNOPSIS
        Initiates a Windows Update scan.
    
    .DESCRIPTION
        This function uses the usoclient and wuauclt utilities to trigger a scan for available Windows 
        Updates. It also resets update authorization and forces a new detection.
    #>
    Write-Host "[Check-WindowsUpdatesScan] Scanning for Windows Updates..."
    try {
        Start-Process -FilePath "usoclient.exe" -ArgumentList "startscan" -NoNewWindow -Wait
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/resetauthorization" -NoNewWindow -Wait
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow -Wait
    } catch {
        Write-Warning "Failed to initiate Windows Update scan: $_"
    }
}

function Check-OptimizeVolumes {
    <#
    .SYNOPSIS
        Checks the health of fixed volumes and optimizes them.
    
    .DESCRIPTION
        This function enumerates all fixed volumes (internal drives) on the system. For each volume, it 
        checks for file system errors using the Repair-Volume cmdlet. If an offline repair is indicated, 
        it attempts that repair. Finally, it optimizes the volume using Optimize-Volume, ensuring defragmentation 
        for HDDs or TRIM for SSDs.
    #>
    Write-Host "[Check-OptimizeVolumes] Processing fixed volumes..."
    $volumes = Get-Volume | Where-Object DriveType -eq 'Fixed'
    foreach ($volume in $volumes) {
        if (-not $volume.DriveLetter) {
            Write-Host "Skipping volume $($volume.UniqueId) because it has no drive letter."
            continue
        }
        Write-Host "----------------------------------------------"
        Write-Host "Processing volume $($volume.DriveLetter)..."
        try {
            $scanResult = Repair-Volume -DriveLetter $volume.DriveLetter -Scan -ErrorAction Stop
            Write-Host "    Health check completed successfully."
        } catch {
            Write-Warning "    Error scanning volume $($volume.DriveLetter): $_"
            continue
        }
        if ($scanResult.NeedOfflineScanAndFix) {
            Write-Host "    Offline repair required. Initiating repair..."
            try {
                Repair-Volume -DriveLetter $volume.DriveLetter -OfflineScanAndFix -ErrorAction Stop
                Write-Host "    Offline repair initiated. A reboot may be required."
            } catch {
                Write-Warning "    Failed to initiate offline repair on volume $($volume.DriveLetter): $_"
                continue
            }
        } else {
            Write-Host "    No offline repair required."
        }
        Write-Host "    Optimizing volume $($volume.DriveLetter)..."
        try {
            Optimize-Volume -DriveLetter $volume.DriveLetter -Verbose -ErrorAction Stop
            Write-Host "    Optimization completed."
        } catch {
            Write-Warning "    Failed to optimize volume $($volume.DriveLetter): $_"
        }
        Write-Host ""
    }
}

function DownloadAndInstall-WindowsUpdates {
    <#
    .SYNOPSIS
        Downloads and installs Windows Updates.
    
    .DESCRIPTION
        This function triggers the download of Windows Updates using usoclient and wuauclt, and then 
        initiates the installation of the downloaded updates.
    #>
    Write-Host "[DownloadAndInstall-WindowsUpdates] Downloading Windows Updates..."
    try {
        Start-Process -FilePath "usoclient.exe" -ArgumentList "startdownload" -NoNewWindow -Wait
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/updatenow" -NoNewWindow -Wait
    } catch {
        Write-Warning "Failed to download Windows Updates: $_"
    }
    Write-Host "[DownloadAndInstall-WindowsUpdates] Installing Windows Updates..."
    try {
        Start-Process -FilePath "usoclient.exe" -ArgumentList "startinstall" -NoNewWindow -Wait
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/reportnow" -NoNewWindow -Wait
    } catch {
        Write-Warning "Failed to install Windows Updates: $_"
    }
    Start-Sleep -Seconds 1
}

function Update-WithPSWindowsUpdate {
    <#
    .SYNOPSIS
        Configures and runs the PSWindowsUpdate module.
    
    .DESCRIPTION
        This function adjusts the execution policy, configures the PSGallery repository, and installs 
        the NuGet package provider along with the PSWindowsUpdate module. It then checks for available 
        updates using Get-WindowsUpdate and installs them. Finally, it resets the repository trust setting.
    #>
    Write-Host "[Update-WithPSWindowsUpdate] Configuring PSWindowsUpdate module..."
    try {
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
        Install-Module -Name PSWindowsUpdate -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop
    } catch {
        Write-Warning "Failed to install or configure PSWindowsUpdate module: $_"
    }
    Write-Host "[Update-WithPSWindowsUpdate] Checking for updates via PSWindowsUpdate..."
    try {
        Get-WindowsUpdate -Verbose
        Write-Host "[Update-WithPSWindowsUpdate] Installing updates via PSWindowsUpdate..."
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -Verbose
    } catch {
        Write-Warning "Windows Update via PSWindowsUpdate encountered an error: $_"
    }
    try {
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Untrusted
    } catch {
        Write-Warning "Failed to revert PSRepository settings: $_"
    }
    Start-Sleep -Seconds 5
}

function Update-InstalledApps {
    <#
    .SYNOPSIS
        Updates installed applications using winget.
    
    .DESCRIPTION
        This function leverages winget to upgrade all installed applications. It automatically accepts 
        source and package agreements.
    #>
    Write-Host "[Update-InstalledApps] Updating installed applications using winget..."
    try {
        winget upgrade --all --accept-source-agreements --accept-package-agreements
    } catch {
        Write-Warning "Failed to update applications using winget: $_"
    }
}

function Scan-SystemFiles {
    <#
    .SYNOPSIS
        Scans and repairs system files.
    
    .DESCRIPTION
        This function uses DISM to scan, check, and restore the system image followed by running SFC to
        verify the integrity of system files.
    #>
    Write-Host "[Scan-SystemFiles] Scanning system files for integrity..."
    try {
        dism /online /cleanup-image /scanhealth
        dism /online /cleanup-image /checkhealth
        dism /online /cleanup-image /restorehealth
        sfc /scannow
    } catch {
        Write-Warning "System file integrity check encountered an error: $_"
    }
    Start-Sleep -Seconds 5
}

function Update-WindowsDefender {
    <#
    .SYNOPSIS
        Updates Windows Defender signatures and conducts a quick scan.
    
    .DESCRIPTION
        This function updates Windows Defender's virus and spyware definitions, then performs a quick scan 
        using MpCmdRun.exe.
    #>
    Write-Host "[Update-WindowsDefender] Updating Windows Defender signatures..."
    try {
        & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -SignatureUpdate
    } catch {
        Write-Warning "Failed to update Windows Defender signatures: $_"
    }
    Write-Host "[Update-WindowsDefender] Running Windows Defender Quick Scan..."
    try {
        & "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -Scan -ScanType 1
    } catch {
        Write-Warning "Windows Defender quick scan encountered an error: $_"
    }
    Start-Sleep -Seconds 5
}

function Clean-DiskSpace {
    <#
    .SYNOPSIS
        Cleans disk space using Disk Cleanup.
    
    .DESCRIPTION
        This function invokes Disk Cleanup (cleanmgr.exe) with predefined sagerun settings to free up disk 
        space by removing unnecessary files.
    #>
    Write-Host "[Clean-DiskSpace] Performing disk cleanup..."
    try {
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -NoNewWindow -Wait
    } catch {
        Write-Warning "Disk cleanup encountered an error: $_"
    }
    Start-Sleep -Seconds 5
}

# =============================================
# Main Script Execution:
Write-Host "============================================"
Write-Host "Starting System Maintenance and Update Tasks"
Write-Host "============================================"

Check-WindowsUpdatesScan
DownloadAndInstall-WindowsUpdates
Update-WithPSWindowsUpdate
Update-InstalledApps
Repair-WindowsStoreApps
Scan-SystemFiles
Check-OptimizeVolumes
Update-WindowsDefender
Clean-DiskSpace

Write-Host "============================================"
Write-Host "All maintenance and update tasks are completed."
Write-Host "============================================"

Start-Sleep -Seconds 1800

# Reboot
