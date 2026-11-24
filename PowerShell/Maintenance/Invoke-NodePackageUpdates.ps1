<#
.SYNOPSIS
    Update globally installed npm packages.

.DESCRIPTION
    Updates global npm packages and opens an indexed maintenance log. Register or
    unregister the current user's Windows logon task with the supplied switches.

.CONTEXT
    Windows logon maintenance automation.

.AUTHOR
    Greg Tate & coding agent

.NOTES
    Last Modified: 2026-11-24
    Revision History:
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
        "===== npm global update started: $(Get-Date -Format s) =====" | Out-File -FilePath $logPath -Append

        # Capture both npm diagnostics and the native process exit status.
        try {
            $npm = Get-Command npm.cmd -CommandType Application -ErrorAction Stop | Select-Object -First 1
            & $npm.Source update --global --no-fund --no-audit --allow-scripts=puppeteer 2>&1 | Out-File -FilePath $logPath -Append
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) { throw "npm exited with code $exitCode." }
            "===== npm global update completed: $(Get-Date -Format s) =====" | Out-File -FilePath $logPath -Append
        }
        catch {
            "ERROR: $_" | Out-File -FilePath $logPath -Append
            throw
        }
        finally {
            # Present the run log even when npm reports a failure.
            try {
                Invoke-Item -LiteralPath $logPath -ErrorAction Stop
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
