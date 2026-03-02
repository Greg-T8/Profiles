# -------------------------------------------------------------------------
# Program: Invoke-WingetUpdates.ps1
# Description: Updates WinGet packages with indexed logs for login automation.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

[CmdletBinding()]
param(
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = -1
)

# Configure log retention for indexed update log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}

$Main = {
    . $Helpers

    $wingetChanged = $false
    $logContext = New-UpdateLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $RetentionDays

    $wingetChanged = Invoke-WinGetUpdates -WinGetLogPath $logContext.WinGetLogPath
    Open-UpdateLogs -WinGetLogPath $logContext.WinGetLogPath -WingetChanged:$wingetChanged
}

$Helpers = {
    function New-UpdateLogContext {
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        # Create and return update log path under the script-local logs folder.
        $logDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        # Apply retention policy before determining the next same-day index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) { $RetentionDaysOverride } else { [int]$LogRetentionConfig.RetentionDays }
            if ($effectiveRetentionDays -gt 0) {
                Remove-OldUpdateLogs -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
            }
        }

        # Prefix log file names with the run date.
        $datePrefix = Get-Date -Format 'yyyy-MM-dd'

        # Derive next same-day index so each run gets a unique log.
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-WinGetUpdates.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-WinGetUpdates$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        # Return log file context.
        [PSCustomObject]@{
            LogDirectory  = $logDirectory
            WinGetLogPath = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-WinGetUpdates.log"
        }
    }

    function Remove-OldUpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        # Remove indexed winget log files older than the configured retention period.
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-WinGetUpdates\.log$' -and
                $_.LastWriteTime -lt $cutoff
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Invoke-WinGetUpdates {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Write a run header for this WinGet update pass.
        $runHeader = "`n===== WinGet update started: $(Get-Date -Format s) ====="
        $runHeader | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

        # Execute WinGet updates via Microsoft.WinGet.Client for structured object output.
        if (Get-Module -ListAvailable -Name 'Microsoft.WinGet.Client') {
            $originalProgressPreference = $ProgressPreference
            $successfulUpdates = 0
            $updateResults = @()
            try {
                # Suppress progress records so logs remain text/object focused.
                $ProgressPreference = 'SilentlyContinue'

                # Load WinGet cmdlets and verify the package manager is ready.
                Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
                Assert-WinGetPackageManager -ErrorAction Stop | Out-Null

                # Discover all installed packages that currently have updates available.
                $availableUpdates = Get-WinGetPackage -ErrorAction Stop |
                    Where-Object { $_.IsUpdateAvailable }

                # Exit cleanly when there are no upgrades to apply.
                if (-not $availableUpdates) {
                    'No package upgrades available.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    return $false
                }

                # Write a structured snapshot of all pending package upgrades.
                'Packages with available updates:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                $availableUpdates |
                    Select-Object Name, Id, InstalledVersion, @{Name = 'AvailableVersion'; Expression = {
                        if ($_.AvailableVersions -and $_.AvailableVersions.Count -gt 0) {
                            $_.AvailableVersions[0]
                        }
                        else {
                            $null
                        }
                    } }, Source |
                    ConvertTo-Json -Depth 4 |
                    Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

                # Apply upgrades one package at a time to preserve per-package status logging.
                foreach ($package in $availableUpdates) {
                    try {
                        $result = $package | Update-WinGetPackage -Mode Silent -Confirm:$false -ErrorAction Stop
                        $successfulUpdates += 1

                        if ($null -ne $result) {
                            $updateResults += $result
                        }

                        "Updated package: $($package.Name) [$($package.Id)]" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    }
                    catch {
                        # Continue processing remaining packages while capturing update failures.
                        "Failed package update: $($package.Name) [$($package.Id)] - $($_.Exception.Message)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    }
                }

                # Emit structured install/update result objects when available.
                if ($updateResults) {
                    'Package update results:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    $updateResults |
                        Select-Object * |
                        ConvertTo-Json -Depth 6 |
                        Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

                "winget updates applied: $successfulUpdates" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return ($successfulUpdates -gt 0)
            }
            catch {
                "WinGet module update failed: $($_.Exception.Message)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return $false
            }
            finally {
                $ProgressPreference = $originalProgressPreference
            }
        }

        'Microsoft.WinGet.Client module was not found.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        return $false
    }

    function Open-UpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath,

            [switch]$WingetChanged
        )

        # Launch WinGet log only when package updates were actually applied.
        if ($WingetChanged -and (Test-Path -Path $WinGetLogPath)) {
            Invoke-Item -Path $WinGetLogPath
        }
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
