<#
.SYNOPSIS
    Updates WinGet packages with indexed logs for login automation.

.DESCRIPTION
    Runs WinGet upgrades using the Microsoft.WinGet.Client module and writes
    structured, date-indexed log files under a script-local logs\ folder.
    Each run receives a unique log file. After a successful update pass, the
    log is opened automatically. Old log files are pruned according to the
    configured retention policy.

.PARAMETER RetentionDays
    Number of days to retain indexed WinGet log files. Accepts 0 (delete all
    existing logs before the current run) through 3650. A value of -1 (the
    default) uses the retention period defined in $LogRetentionConfig (30 days).

.EXAMPLE
    .\Invoke-WingetUpdates.ps1
    Runs WinGet updates using the default 30-day log retention policy.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -RetentionDays 7
    Runs WinGet updates and retains only logs from the past 7 days.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -RetentionDays 0
    Runs WinGet updates and deletes all existing logs before the run.

.CONTEXT
    User login maintenance automation (Windows Task Scheduler)

.AUTHOR
    Greg Tate

.NOTES
    Program: Invoke-WingetUpdates.ps1
#>

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

    $wingetChanged = Invoke-WinGetUpdate -WinGetLogPath $logContext.WinGetLogPath
    Open-UpdateLog -WinGetLogPath $logContext.WinGetLogPath -WingetChanged:$wingetChanged
}

$Helpers = {
    function New-UpdateLogContext {
        <#
        .SYNOPSIS
            Creates a dated, indexed log-file context for a WinGet update run.

        .DESCRIPTION
            Ensures the script-local logs\ directory exists, applies the log
            retention policy, then generates a unique log file path using a
            yyyy-MM-dd-NNN naming scheme where NNN increments per run per day.

        .PARAMETER LogRetentionConfig
            Hashtable with Enabled (bool) and RetentionDays (int) keys that
            control whether old log files are pruned and how old they must be.

        .PARAMETER RetentionDaysOverride
            When >= 0, overrides the RetentionDays value from LogRetentionConfig.
            Defaults to -1 (use LogRetentionConfig.RetentionDays).

        .OUTPUTS
            PSCustomObject with LogDirectory and WinGetLogPath properties.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        # Create and return update log path under the shared AppData log folder used by Invoke-PowerShellModuleUpdates.
        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            if ($PSCmdlet.ShouldProcess($logDirectory, 'Create log directory')) {
                New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
            }
        }

        # Apply retention policy before determining the next same-day index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) { $RetentionDaysOverride } else { [int]$LogRetentionConfig.RetentionDays }
            if ($effectiveRetentionDays -gt 0) {
                Remove-OldUpdateLog -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
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

    function Remove-OldUpdateLog {
        <#
        .SYNOPSIS
            Removes indexed WinGet log files older than the retention threshold.

        .DESCRIPTION
            Scans LogDirectory for files matching the yyyy-MM-dd-NNN-WinGetUpdates.log
            pattern and deletes any whose LastWriteTime predates the computed cutoff.

        .PARAMETER LogDirectory
            Full path to the directory that contains the indexed log files.

        .PARAMETER RetentionDays
            Age threshold in days. Log files older than this value are deleted.
            Must be between 1 and 3650.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        # Remove indexed winget log files older than the configured retention period.
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $logsToRemove = Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-WinGetUpdates\.log$' -and
                $_.LastWriteTime -lt $cutoff
            }

        foreach ($logFile in $logsToRemove) {
            if ($PSCmdlet.ShouldProcess($logFile.FullName, 'Remove old WinGet log')) {
                Remove-Item -Path $logFile.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function Invoke-WinGetUpdate {
        <#
        .SYNOPSIS
            Runs WinGet package upgrades via Microsoft.WinGet.Client and logs results.

        .DESCRIPTION
            Imports the Microsoft.WinGet.Client module, discovers all installed
            packages that have updates available, applies each upgrade silently,
            and records structured output to the provided log file. Returns $true
            when at least one package was successfully updated, $false otherwise.

        .PARAMETER WinGetLogPath
            Full path to the log file where run output should be appended.

        .OUTPUTS
            System.Boolean - $true if one or more packages were updated; otherwise $false.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Write a run header for this WinGet update pass.
        $runHeader = "`n===== WinGet update started: $(Get-Date -Format s) ====="
        $runHeader | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        'Scope: All installed WinGet packages' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

        # Execute WinGet updates via Microsoft.WinGet.Client and emit text-first log lines.
        if (Get-Module -ListAvailable -Name 'Microsoft.WinGet.Client') {
            $originalProgressPreference = $ProgressPreference
            $successfulUpdates = 0
            $installedPackageCount = 0
            $updatedPackageLines = [System.Collections.Generic.List[string]]::new()
            $pinnedPackageLines = [System.Collections.Generic.List[string]]::new()
            $skippedPackageLines = [System.Collections.Generic.List[string]]::new()
            try {
                # Suppress progress records so logs remain text/object focused.
                $ProgressPreference = 'SilentlyContinue'

                # Load WinGet cmdlets and verify the package manager is ready.
                Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
                Assert-WinGetPackageManager -ErrorAction Stop | Out-Null

                # Discover all installed packages and compute pending updates from that set.
                $installedPackages = @(Get-WinGetPackage -ErrorAction Stop)
                $installedPackageCount = $installedPackages.Count
                $availableUpdates = @($installedPackages | Where-Object { $_.IsUpdateAvailable })

                # Read pinned package metadata from winget CLI output.
                if (Get-Command -Name winget -ErrorAction SilentlyContinue) {
                    $pinListOutput = @(winget pin list --disable-interactivity 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $pinListOutput) {
                        $pinListOutput | ForEach-Object {
                            $line = "$($_)".Trim()
                            if (-not $line) {
                                return
                            }

                            if ($line -match '^Name\s+Id\s+Version\s+Source\s+Pin type$') {
                                return
                            }

                            if ($line -match '^-{3,}$') {
                                return
                            }

                            $columns = @($line -split '\s{2,}')
                            if ($columns.Count -ge 2) {
                                $pinnedPackageLines.Add("  - $($columns[0]) [$($columns[1])] (pinned)")
                            }
                        }
                    }
                }

                # Record up-to-date packages in a compact, line-oriented format.
                $installedPackages |
                    Where-Object { -not $_.IsUpdateAvailable } |
                    ForEach-Object {
                        $skippedPackageLines.Add("  - $($_.Name) [$($_.Id)] (up-to-date)")
                    }

                # Exit cleanly when there are no upgrades to apply.
                if (-not $availableUpdates) {
                    "Summary: $installedPackageCount packages checked, 0 updated, $($skippedPackageLines.Count) skipped." | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    'Pinned packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    if ($pinnedPackageLines.Count -gt 0) {
                        $pinnedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    }
                    else {
                        '  - None' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    }

                    if ($skippedPackageLines.Count -gt 0) {
                        'Skipped packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                        $skippedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    }
                    "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    return $false
                }

                # Apply upgrades one package at a time to preserve per-package status logging.
                foreach ($package in $availableUpdates) {
                    try {
                        $package | Update-WinGetPackage -Mode Silent -Confirm:$false -ErrorAction Stop | Out-Null
                        $successfulUpdates += 1

                        if ($package.AvailableVersions -and $package.AvailableVersions.Count -gt 0) {
                            $availableVersion = $package.AvailableVersions[0]
                        }
                        else {
                            $availableVersion = '?'
                        }

                        $updatedPackageLines.Add("  - $($package.Name) [$($package.Id)] ($($package.InstalledVersion) -> $availableVersion)")
                    }
                    catch {
                        # Continue processing remaining packages while capturing update failures.
                        $skippedPackageLines.Add("  - $($package.Name) [$($package.Id)] (error: $($_.Exception.Message))")
                    }
                }

                # Write compact summary and grouped package result lines.
                "Summary: $installedPackageCount packages checked, $successfulUpdates updated, $($skippedPackageLines.Count) skipped." | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

                if ($updatedPackageLines.Count -gt 0) {
                    'Updated packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    $updatedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

                'Pinned packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                if ($pinnedPackageLines.Count -gt 0) {
                    $pinnedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }
                else {
                    '  - None' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

                if ($skippedPackageLines.Count -gt 0) {
                    'Skipped packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    $skippedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

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

    function Open-UpdateLog {
        <#
        .SYNOPSIS
            Opens the WinGet log file when package updates were applied.

        .DESCRIPTION
            Invokes the default handler for WinGetLogPath only when WingetChanged
            is set and the log file exists, so the log is surfaced after a run
            that produced actual changes.

        .PARAMETER WinGetLogPath
            Full path to the WinGet log file to open.

        .PARAMETER WingetChanged
            Switch indicating that at least one WinGet package was updated during
            the current run. The log is opened only when this switch is present.
        #>
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
