<#
.SYNOPSIS
    Update globally installed npm packages.

.DESCRIPTION
    Updates global npm packages, compares before-and-after versions, and opens an
    indexed maintenance log. Register or unregister the current user's Windows
    logon task with the supplied switches.

.CONTEXT
    Windows logon maintenance automation.

.AUTHOR
    Greg Tate & coding agent

.NOTES
    Last Modified: 2026-11-25
    Revision History:
        2026-11-25 - Support controller log reporting and presentation.
        2026-11-25 - Distinguish npm install counts from version comparison results.
        2026-11-25 - Log global dependency version changes around npm updates.
        2026-11-24 - Save and open indexed logs in the shared maintenance folder.
        2026-11-24 - Allow Puppeteer browser installation during updates.
        2026-11-24 - Initial version.
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Register')]
    [switch]$Register,

    [Parameter(Mandatory, ParameterSetName = 'Unregister')]
    [switch]$Unregister,

    [Parameter(ParameterSetName = 'Register')]
    [Parameter(ParameterSetName = 'Unregister')]
    [string]$TaskPath = '\Custom Tasks\'
)

# Keep the task identity consistent across registration and removal.
$TaskName = 'Update Node Packages At Logon'
$Main = {
    . $Helpers

    # Route task management separately from package maintenance.
    if ($Register -or $Unregister) {
        Set-NodeUpdateTask
        return
    }
    Invoke-NodePackageUpdate
}

$Helpers = {
    function Set-NodeUpdateTask {
        # Register or remove the current user's logon task.
        $normalizedPath = '\' + $TaskPath.Trim(' ', '\') + '\'
        if ($TaskPath.Trim(' ', '\').Length -eq 0) { $normalizedPath = '\' }

        # Remove only the named maintenance task when requested.
        if ($Unregister) {
            $existing = Get-ScheduledTask -TaskPath $normalizedPath -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($existing) {
                Unregister-ScheduledTask -TaskPath $normalizedPath -TaskName $TaskName -Confirm:$false
            }
            return
        }

        # Resolve the actual executable and require an existing task folder.
        $pwsh = (Get-Process -Id $PID).Path
        if ($PSVersionTable.PSEdition -ne 'Core') { throw 'Register this task from PowerShell 7.' }
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $folderPath = if ($normalizedPath -eq '\') { '\' } else { $normalizedPath.TrimEnd('\') }
        $null = $service.GetFolder($folderPath)
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -Priority 7 -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        $arguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $PSScriptRoot
        $definition = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings
        Register-ScheduledTask -TaskPath $normalizedPath -TaskName $TaskName -InputObject $definition -Force -ErrorAction Stop | Out-Null
        Get-ScheduledTask -TaskPath $normalizedPath -TaskName $TaskName -ErrorAction Stop
    }

    function Get-GlobalPackageSnapshot {
        # Capture every installed global package and its dependency versions.
        param(
            [Parameter(Mandatory)]
            [string]$NpmPath
        )

        $jsonOutput = & $NpmPath list --global --all --json --loglevel=error 2>$null
        $packageTree = ($jsonOutput -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $snapshot = @{}
        Add-DependencyVersion -Dependencies $packageTree.dependencies -Snapshot $snapshot
        return $snapshot
    }

    function Add-DependencyVersion {
        # Collect each installed package version from a nested npm dependency tree.
        param(
            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Dependencies,

            [Parameter(Mandatory)]
            [hashtable]$Snapshot
        )

        # Walk each dependency entry to build the package-version inventory.
        foreach ($dependency in $Dependencies.GetEnumerator()) {
            $packageName = [string]$dependency.Key
            $package = $dependency.Value

            # Keep every observed version when the tree contains duplicates.
            if ($package.version) {
                if (-not $Snapshot.ContainsKey($packageName)) {
                    $Snapshot[$packageName] = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                }
                $null = $Snapshot[$packageName].Add([string]$package.version)
            }

            # Include nested dependencies as well as top-level global packages.
            if ($package.dependencies -is [System.Collections.IDictionary]) {
                Add-DependencyVersion -Dependencies $package.dependencies -Snapshot $Snapshot
            }
        }
    }

    function Write-GlobalPackageChanges {
        # Write added, removed, and version-changed global packages to the run log.
        param(
            [Parameter(Mandatory)]
            [hashtable]$Before,

            [Parameter(Mandatory)]
            [hashtable]$After,

            [Parameter(Mandatory)]
            [string]$LogPath
        )

        $changedPackageCount = 0
        $packageNames = @($Before.Keys + $After.Keys | Sort-Object -Unique)

        # Compare the installed version set for every package name in either snapshot.
        foreach ($packageName in $packageNames) {
            $beforeVersions = if ($Before.ContainsKey($packageName)) { @($Before[$packageName]) } else { @() }
            $afterVersions = if ($After.ContainsKey($packageName)) { @($After[$packageName]) } else { @() }
            $beforeText = $beforeVersions -join ', '
            $afterText = $afterVersions -join ', '

            # Report package names that were added or removed from the global tree.
            if ($beforeVersions.Count -eq 0) {
                "Added: $packageName@$afterText" | Out-File -FilePath $LogPath -Append
                $changedPackageCount++
            }
            elseif ($afterVersions.Count -eq 0) {
                "Removed: $packageName@$beforeText" | Out-File -FilePath $LogPath -Append
                $changedPackageCount++
            }
            elseif ($beforeText -ne $afterText) {
                if ($beforeVersions.Count -eq 1 -and $afterVersions.Count -eq 1) {
                    "Updated: $packageName $beforeText -> $afterText" | Out-File -FilePath $LogPath -Append
                }
                else {
                    "Dependency versions changed: $packageName (before: $beforeText; after: $afterText)" | Out-File -FilePath $LogPath -Append
                }
                $changedPackageCount++
            }
        }

        # Label the comparison result separately from npm's install summary.
        if ($changedPackageCount -eq 0) {
            'Version comparison: no installed global package versions changed.' | Out-File -FilePath $LogPath -Append
        }
        else {
            "Version comparison: $changedPackageCount package names were added, removed, or changed version." | Out-File -FilePath $LogPath -Append
        }
    }

    function Invoke-NodePackageUpdate {
        # Record npm output and preserve a failure exit code for Task Scheduler.
        $logDirectory = Join-Path $env:APPDATA '_UserPackageAndModuleUpdates'
        $null = New-Item -ItemType Directory -Path $logDirectory -Force
        $datePrefix = Get-Date -Format 'yyyy-MM-dd'
        $index = 1
        do {
            $logPath = Join-Path $logDirectory ('{0}-{1:D3}-NodePackageUpdates.log' -f $datePrefix, $index)
            $index++
        } while (Test-Path -LiteralPath $logPath)
        # Report the exact log to the controller when orchestrated.
        if ($env:MAINTENANCE_LOG_POINTER) { Set-Content -LiteralPath $env:MAINTENANCE_LOG_POINTER -Value $logPath }
        "===== npm global update started: $(Get-Date -Format s) =====" | Out-File -FilePath $logPath -Append

        # Capture both npm diagnostics and the native process exit status.
        try {
            $npm = Get-Command npm.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1

            # Capture the installed dependency tree before npm changes it.
            $beforeSnapshot = $null
            try {
                $beforeSnapshot = Get-GlobalPackageSnapshot -NpmPath $npm.Source
            }
            catch {
                "WARNING: Could not capture the pre-update package list: $_" | Out-File -FilePath $logPath -Append
            }

            'The npm summary below reports its installation result; version comparison is recorded separately.' | Out-File -FilePath $logPath -Append
            & $npm.Source update --global --no-fund --no-audit --allow-scripts=puppeteer 2>&1 | Out-File -FilePath $logPath -Append
            $exitCode = $LASTEXITCODE

            # Compare the resulting dependency tree with the captured inventory.
            if ($null -ne $beforeSnapshot) {
                try {
                    $afterSnapshot = Get-GlobalPackageSnapshot -NpmPath $npm.Source
                    Write-GlobalPackageChanges -Before $beforeSnapshot -After $afterSnapshot -LogPath $logPath
                }
                catch {
                    "WARNING: Could not capture or compare the post-update package list: $_" | Out-File -FilePath $logPath -Append
                }
            }

            if ($exitCode -ne 0) {
                throw "npm exited with code $exitCode."
            }
            "===== npm global update completed: $(Get-Date -Format s) =====" | Out-File -FilePath $logPath -Append
        }
        catch {
            "ERROR: $_" | Out-File -FilePath $logPath -Append
            throw
        }
        finally {
            # Present the run log even when npm reports a failure.
            try {
                if (-not $env:MAINTENANCE_LOG_POINTER) { Invoke-Item -LiteralPath $logPath -ErrorAction Stop }
            }
            catch {
                Write-Warning "Could not open update log '$logPath': $_"
            }
        }
    }
}

# Execute from the script directory and restore the caller's location.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
