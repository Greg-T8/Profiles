<#
.SYNOPSIS
    Run logon maintenance sequentially and present a consolidated report.

.DESCRIPTION
    Runs WinGet, PowerShell module, and npm maintenance in separate processes.
    Registers or removes the controller logon task when requested.

.CONTEXT
    Windows logon maintenance automation.

.AUTHOR
    Greg Tate & coding agent

.NOTES
    Last Modified: 2026-11-25
    Revision History:
        2026-11-25 - Fix evidence filter pattern syntax.
        2026-11-25 - Include npm run timing and package-change summary.
        2026-11-25 - Initial version.
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

# Define the ordered maintenance stages and their existing logon arguments.
$TaskName = 'Run Maintenance At Logon'
$Stages = @(
    @{ Name = 'WinGet'; Script = 'Invoke-WingetUpdates.ps1'; Arguments = ''; Completion = 'WinGet update completed' }
    @{ Name = 'PowerShell modules'; Script = 'Invoke-PowerShellModuleUpdates.ps1'; Arguments = '-AllModules'; Completion = 'PowerShell module maintenance completed' }
    @{ Name = 'Node packages'; Script = 'Invoke-NodePackageUpdates.ps1'; Arguments = ''; Completion = 'npm global update completed' }
)

$Main = {
    . $Helpers

    # Route task registration separately from the maintenance run.
    if ($Register -or $Unregister) {
        Set-ControllerTask
        return
    }
    Invoke-MaintenanceRun
}

$Helpers = {
    function Set-ControllerTask {
        # Register or remove the controller's current-user logon task.
        $path = '\' + $TaskPath.Trim(' ', '\') + '\'
        if ($TaskPath.Trim(' ', '\').Length -eq 0) { $path = '\' }
        if ($Unregister) {
            if (Get-ScheduledTask -TaskPath $path -TaskName $TaskName -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskPath $path -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            }
            return
        }
        if ($PSVersionTable.PSEdition -ne 'Core') { throw 'Register this task from PowerShell 7.' }
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $folder = if ($path -eq '\') { '\' } else { $path.TrimEnd('\') }
        $null = $service.GetFolder($folder)
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -Priority 7 -ExecutionTimeLimit (New-TimeSpan -Hours 72)
        $arguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $PSCommandPath
        $pwsh = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $PSScriptRoot
        $definition = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings
        Register-ScheduledTask -TaskPath $path -TaskName $TaskName -InputObject $definition -Force -ErrorAction Stop | Out-Null
        $registered = Get-ScheduledTask -TaskPath $path -TaskName $TaskName -ErrorAction Stop
        if ($registered.Actions.Count -ne 1 -or $registered.Actions[0].Execute -ne $pwsh -or $registered.Actions[0].Arguments -ne $arguments -or $registered.Settings.Enabled -ne $true -or $registered.Principal.RunLevel -ne 'Highest') {
            throw 'Controller task registration could not be verified.'
        }
        $registered
    }

    function Invoke-MaintenanceRun {
        # Run each stage even after a failure and always present the report.
        $directory = Join-Path $env:APPDATA '_UserPackageAndModuleUpdates'
        $null = New-Item -ItemType Directory -Path $directory -Force
        $date = Get-Date -Format 'yyyy-MM-dd'
        $index = 1
        do {
            $report = Join-Path $directory ('{0}-{1:D3}-MaintenanceSummary.log' -f $date, $index++)
        } while (Test-Path -LiteralPath $report)
        $failed = $false
        "Maintenance started: $(Get-Date -Format s)" | Set-Content -LiteralPath $report

        # Keep each run's pointer and diagnostic streams distinct from other runs.
        $runId = [guid]::NewGuid().ToString('N')
        $previousPointer = $env:MAINTENANCE_LOG_POINTER
        try {
            foreach ($stage in $Stages) {
                $result = Invoke-MaintenanceStage -Stage $stage -Directory $directory -RunId $runId
                $result.Lines | Add-Content -LiteralPath $report
                if ($result.Failed) { $failed = $true }
            }
        }
        finally {
            $env:MAINTENANCE_LOG_POINTER = $previousPointer
            "`nMaintenance finished: $(Get-Date -Format s)" | Add-Content -LiteralPath $report
            try { Invoke-Item -LiteralPath $report -ErrorAction Stop }
            catch { Write-Warning "Could not open maintenance report '$report': $_" }
        }
        if ($failed) { throw "One or more maintenance stages need attention. See $report" }
    }

    function Invoke-MaintenanceStage {
        # Execute one stage and summarize evidence from its own log.
        param($Stage, [string]$Directory, [string]$RunId)
        $pointer = Join-Path $env:TEMP ("maintenance-{0}-{1}.txt" -f $RunId, $Stage.Script)
        $stdout = Join-Path $Directory ("{0}-{1}-stdout.log" -f $RunId, $Stage.Name.Replace(' ', ''))
        $stderr = Join-Path $Directory ("{0}-{1}-stderr.log" -f $RunId, $Stage.Name.Replace(' ', ''))
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("`n===== $($Stage.Name) =====")
        $failed = $false
        $env:MAINTENANCE_LOG_POINTER = $pointer
        try {
            $script = Join-Path $PSScriptRoot $Stage.Script
            $arguments = '-NoProfile -File "{0}" {1}' -f $script, $Stage.Arguments
            $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
            $lines.Add("Process exit code: $($process.ExitCode)")
            if ($process.ExitCode -ne 0) { $failed = $true }
            $log = if (Test-Path -LiteralPath $pointer) { (Get-Content -LiteralPath $pointer -Raw).Trim() } else { $null }
            if (-not $log -or -not (Test-Path -LiteralPath $log -PathType Leaf)) {
                $lines.Add('ERROR: The stage did not produce its expected log.')
                $failed = $true
            }
            else {
                $lines.Add("Log: $log")
                $content = @(Get-Content -LiteralPath $log)
                $evidence = @($content | Where-Object { $_ -match '^(===== npm global update (started|completed):|changed \d+ packages? in |Summary:|Version comparison:|Updated:|Added:|Removed:|Dependency versions changed:|WARNING:|ERROR:|WinGet module update failed:|Updated packages:|\s+- .*\([^)]* -> [^)]*\)|\s+- .*\(error:.*|^[^:]+:\s+\S+\s+->\s+\S+)' })
                foreach ($item in $evidence) { $lines.Add($item) }
                if (-not ($content | Where-Object { $_ -like "*$($Stage.Completion)*" })) {
                    $lines.Add('ERROR: Completion marker missing from stage log.')
                    $failed = $true
                }
                if ($evidence | Where-Object { $_ -match '^(ERROR:|WinGet module update failed:|\s+- .*\(error:)' }) { $failed = $true }
            }
        }
        catch {
            $lines.Add("ERROR: Could not complete stage: $_")
            $failed = $true
        }
        finally {
            # Preserve diagnostics only when a stage needs attention.
            if ($failed) {
                if (Test-Path -LiteralPath $stdout) { $lines.Add("Standard output: $stdout") }
                if (Test-Path -LiteralPath $stderr) { $lines.Add("Standard error: $stderr") }
            }
            else {
                Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue
            }
            Remove-Item -LiteralPath $pointer -ErrorAction SilentlyContinue
        }
        $lines.Add($(if ($failed) { 'Status: Needs attention' } else { 'Status: Completed' }))
        [PSCustomObject]@{ Failed = $failed; Lines = $lines.ToArray() }
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
