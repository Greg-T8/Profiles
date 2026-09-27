<#
.SYNOPSIS
Removes old files from the Snagit Captures folder and writes indexed logs.

.DESCRIPTION
Deletes files older than a configured age from the Snagit Captures folder,
then outputs cleanup totals for files removed and total size reclaimed.
Logs are written to date-indexed files under %APPDATA%\_UserPackageAndModuleUpdates.

.CONTEXT
User login maintenance automation (Windows Task Scheduler)

.AUTHOR
Greg Tate

.PARAMETER LogRetentionDays
Number of days to retain indexed cleanup log files.
A value of -1 (default) uses the configured retention period.
A value of 0 removes existing cleanup logs before the current run.

.PARAMETER CaptureFolderPath
Optional override for the Snagit capture folder path.
Defaults to $env:USERPROFILE\Snagit Captures.

.PARAMETER AgeInDays
Number of days used to calculate the cleanup cutoff date.
Files older than this threshold are removed.

.PARAMETER Register
Creates or updates the current-user logon task for Snagit capture cleanup.

.PARAMETER Unregister
Removes only this maintenance task.

.PARAMETER TaskPath
Task Scheduler folder path used with -Register or -Unregister. Defaults to \Custom Tasks\.

.EXAMPLE
.\Maintenance\Invoke-SnagitCaptureFolderCleanup.ps1 -Register

.EXAMPLE
.\Maintenance\Invoke-SnagitCaptureFolderCleanup.ps1 -Unregister

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1 -LogRetentionDays 7

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1 -AgeInDays 30

.NOTES
Program: Invoke-SnagitCaptureFolderCleanup.ps1
#>

#region PARAMETERS
[CmdletBinding(DefaultParameterSetName = 'Maintenance')]
param(
    [Parameter(ParameterSetName = 'Maintenance')]
    [ValidateRange(-1, 3650)]
    [int]$LogRetentionDays = -1,

    [Parameter(ParameterSetName = 'Maintenance')]
    [ValidateNotNullOrEmpty()]
    [string]$CaptureFolderPath = (Join-Path -Path $env:USERPROFILE -ChildPath 'Snagit Captures'),

    [Parameter(ParameterSetName = 'Maintenance')]
    [ValidateRange(1, 3650)]
    [int]$AgeInDays = 30,

    [Parameter(Mandatory, ParameterSetName = 'Register')]
    [switch]$Register,

    [Parameter(Mandatory, ParameterSetName = 'Unregister')]
    [switch]$Unregister,

    [Parameter(ParameterSetName = 'Register')]
    [Parameter(ParameterSetName = 'Unregister')]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = '\Custom Tasks\'
)
#endregion

#region CONFIGURATION
# Configure default cleanup behavior for capture files.
$SnagitCleanupConfig = @{
    AgeInDays = 14
}

# Configure log retention for indexed cleanup log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}
#endregion

#region MAIN
# Orchestrate log preparation, cleanup execution, and result output.
# Task identity and parameters used only when registering or unregistering this maintenance task.
$TaskName = 'Clean Up Snagit Capture Folder At Logon'
$InvokeScriptName = 'Invoke-SnagitCaptureFolderCleanup.ps1'
$TaskArguments = ''
$RegisterTask = $Register.IsPresent
$UnregisterTask = $Unregister.IsPresent
$Main = {
    . $Helpers

    # Route task lifecycle requests away from the normal capture cleanup flow.
    if ($RegisterTask -or $UnregisterTask) {
        . $RegistrationHelpers
        Confirm-TaskPlatformSupport
        $context = Get-TaskRegistrationContext

        if ($UnregisterTask) {
            Unregister-MaintenanceTask -Context $context
            return
        }

        Confirm-TaskRegistrationPrerequisite -Context $context
        Register-MaintenanceTask -Context $context
        Confirm-MaintenanceTask -Context $context
        Show-TaskRegistrationResult -Context $context
        return
    }

    # Build indexed log context and apply retention before this run.
    $logContext = New-CleanupLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $LogRetentionDays

    # Compute cutoff date and perform capture folder cleanup.
    $effectiveAgeInDays = $AgeInDays
    if (-not $PSBoundParameters.ContainsKey('AgeInDays')) {
        $effectiveAgeInDays = [int]$SnagitCleanupConfig.AgeInDays
    }

    $cutoffDate = (Get-Date).AddDays(-$effectiveAgeInDays)
    $cleanupResult = Invoke-SnagitCaptureCleanup -CaptureFolderPath $CaptureFolderPath -CutoffDate $cutoffDate -SnagitCleanupLogPath $logContext.SnagitCleanupLogPath

    $cleanupResult
}
#endregion

#region HELPERS
# Define helper functions used by the main orchestration flow.
$Helpers = {
    function New-CleanupLogContext {
        # Create and return indexed cleanup log paths under %APPDATA%.
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        # Apply retention policy before calculating the next same-day log index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) {
                $RetentionDaysOverride
            }
            else {
                [int]$LogRetentionConfig.RetentionDays
            }

            if ($effectiveRetentionDays -eq 0) {
                Clear-AllCleanupLogs -LogDirectory $logDirectory
            }
            elseif ($effectiveRetentionDays -gt 0) {
                Remove-OldCleanupLogs -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
            }
        }

        $datePrefix = Get-Date -Format 'yyyy-MM-dd'
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-SnagitCaptureFolderCleanup.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-SnagitCaptureFolderCleanup$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        [PSCustomObject]@{
            LogDirectory          = $logDirectory
            SnagitCleanupLogPath  = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-SnagitCaptureFolderCleanup.log"
        }
    }

    function Remove-OldCleanupLogs {
        # Remove indexed cleanup logs older than the configured retention period.
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-SnagitCaptureFolderCleanup\.log$' -and
                $_.LastWriteTime -lt $cutoff
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Clear-AllCleanupLogs {
        # Remove all indexed cleanup logs when retention is explicitly set to zero.
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory
        )

        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-SnagitCaptureFolderCleanup\.log$' } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Invoke-SnagitCaptureCleanup {
        # Remove old files from the capture folder and return cleanup totals.
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$CaptureFolderPath,

            [Parameter(Mandatory)]
            [datetime]$CutoffDate,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$SnagitCleanupLogPath
        )

        "===== Snagit cleanup started: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "Capture folder: $CaptureFolderPath" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "Cutoff date: $($CutoffDate.ToString('s'))" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

        if (-not (Test-Path -Path $CaptureFolderPath)) {
            'Capture folder does not exist. No files removed.' | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
            "===== Snagit cleanup completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

            return [PSCustomObject]@{
                CaptureFolderPath = $CaptureFolderPath
                CutoffDate        = $CutoffDate
                FilesRemoved      = 0
                BytesRemoved      = 0
                SizeRemovedMB     = 0
            }
        }

        $filesToRemove = @(Get-ChildItem -Path $CaptureFolderPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $CutoffDate })
        $filesRemoved = $filesToRemove.Count
        [int64]$bytesRemoved = ($filesToRemove | Measure-Object -Property Length -Sum).Sum

        if (-not $bytesRemoved) {
            $bytesRemoved = 0
        }

        if ($filesRemoved -gt 0) {
            $filesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        $sizeRemovedMB = [math]::Round(($bytesRemoved / 1MB), 2)
        "Summary: Removed $filesRemoved files totaling $sizeRemovedMB MB ($bytesRemoved bytes)." | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "===== Snagit cleanup completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

        return [PSCustomObject]@{
            CaptureFolderPath = $CaptureFolderPath
            CutoffDate        = $CutoffDate
            FilesRemoved      = $filesRemoved
            BytesRemoved      = $bytesRemoved
            SizeRemovedMB     = $sizeRemovedMB
        }
    }

    function Open-CleanupLog {
        # Open the cleanup log file only when files were removed in this run.
        param(
            [Parameter(Mandatory)]
            [string]$SnagitCleanupLogPath,

            [Parameter(Mandatory)]
            [int]$FilesRemoved
        )

        if ($FilesRemoved -gt 0 -and (Test-Path -Path $SnagitCleanupLogPath)) {
            Invoke-Item -Path $SnagitCleanupLogPath
        }
    }
}

$RegistrationHelpers = {
    # Ensure the script runs on Windows where ScheduledTasks is available.
    function Confirm-TaskPlatformSupport {
        if (-not $IsWindows) {
            throw 'This script requires Windows and the ScheduledTasks module.'
        }
    }

    # Normalize a Task Scheduler path with leading and trailing backslashes.
    function ConvertTo-NormalizedTaskPath {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $normalizedPath = $Path.Trim()
        if (-not $normalizedPath.StartsWith('\')) {
            $normalizedPath = "\$normalizedPath"
        }

        if (-not $normalizedPath.EndsWith('\')) {
            $normalizedPath = "$normalizedPath\"
        }

        return $normalizedPath
    }

    # Create the task context used by registration and verification.
    function Get-TaskRegistrationContext {
        $pwshCommand = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            ScriptRoot      = $PSScriptRoot
            ScriptPath      = Join-Path -Path $PSScriptRoot -ChildPath $InvokeScriptName
            ScriptArguments = $TaskArguments
            CurrentUser     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            PwshPath        = if ($pwshCommand) { $pwshCommand.Source } else { $null }
            TaskName        = $TaskName
            TaskPath        = ConvertTo-NormalizedTaskPath -Path $TaskPath
        }
    }

    # Confirm the target script and PowerShell executable exist before registration.
    function Confirm-TaskRegistrationPrerequisite {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        if (-not (Test-Path -LiteralPath $Context.ScriptPath -PathType Leaf)) {
            throw "Script not found: $($Context.ScriptPath)"
        }

        if ([string]::IsNullOrWhiteSpace($Context.PwshPath)) {
            throw 'pwsh.exe was not found on PATH.'
        }
    }

    # Remove this task when present and report when it is already absent.
    function Unregister-MaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        $task = Get-ScheduledTask `
            -TaskPath $Context.TaskPath `
            -TaskName $Context.TaskName `
            -ErrorAction SilentlyContinue

        if (-not $task) {
            Write-Host "Task not found: $($Context.TaskPath)$($Context.TaskName)" -ForegroundColor Yellow
            return
        }

        Unregister-ScheduledTask `
            -TaskPath $Context.TaskPath `
            -TaskName $Context.TaskName `
            -Confirm:$false
        Write-Host "Task unregistered: $($Context.TaskPath)$($Context.TaskName)" -ForegroundColor Yellow
    }

    # Create the requested Task Scheduler folder when it does not exist.
    function New-MaintenanceTaskFolder {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $normalizedPath = ConvertTo-NormalizedTaskPath -Path $Path
        $folderName = $normalizedPath.Trim('\')
        if ([string]::IsNullOrWhiteSpace($folderName)) {
            return
        }

        $scheduleService = New-Object -ComObject 'Schedule.Service'
        $scheduleService.Connect()

        try {
            $null = $scheduleService.GetFolder("\$folderName")
        }
        catch {
            try {
                $null = $scheduleService.GetFolder('\').CreateFolder($folderName)
            }
            catch {
                if ($_.Exception.Message -match '0x800700B7') {
                    return
                }

                throw
            }
        }
    }

    # Register one logon task with the established profile maintenance settings.
    function Register-MaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Context.CurrentUser
        $principal = New-ScheduledTaskPrincipal `
            -UserId $Context.CurrentUser `
            -LogonType Interactive `
            -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet `
            -Compatibility Win8 `
            -AllowStartIfOnBatteries `
            -StartWhenAvailable `
            -IdleDuration (New-TimeSpan -Minutes 10) `
            -IdleWaitTimeout (New-TimeSpan -Hours 1) `
            -MultipleInstances IgnoreNew `
            -Priority 7 `
            -ExecutionTimeLimit (New-TimeSpan -Hours 72)

        # Ensure the requested Task Scheduler folder exists before registration.
        New-MaintenanceTaskFolder -Path $Context.TaskPath

        # Build the hidden PowerShell action and append task-specific arguments.
        $arguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $Context.ScriptPath
        if (-not [string]::IsNullOrWhiteSpace($Context.ScriptArguments)) {
            $arguments = '{0} {1}' -f $arguments, $Context.ScriptArguments
        }

        $action = New-ScheduledTaskAction `
            -Execute $Context.PwshPath `
            -Argument $arguments `
            -WorkingDirectory $Context.ScriptRoot
        $taskDefinition = New-ScheduledTask `
            -Action $action `
            -Principal $principal `
            -Trigger $trigger `
            -Settings $settings

        Register-ScheduledTask `
            -TaskPath $Context.TaskPath `
            -TaskName $Context.TaskName `
            -InputObject $taskDefinition `
            -Force |
            Out-Null
    }

    # Verify the registered task matches the expected action and profile settings.
    function Confirm-MaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        $registeredTask = Get-ScheduledTask `
            -TaskPath $Context.TaskPath `
            -TaskName $Context.TaskName `
            -ErrorAction Stop

        if ($registeredTask.Actions.Count -ne 1) {
            throw "Task does not have exactly one action: $($Context.TaskPath)$($Context.TaskName)"
        }

        $expectedArguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $Context.ScriptPath
        if (-not [string]::IsNullOrWhiteSpace($Context.ScriptArguments)) {
            $expectedArguments = '{0} {1}' -f $expectedArguments, $Context.ScriptArguments
        }

        if ($registeredTask.Actions[0].Execute -ne $Context.PwshPath -or
            $registeredTask.Actions[0].Arguments -ne $expectedArguments -or
            $registeredTask.Actions[0].WorkingDirectory -ne $Context.ScriptRoot) {
            throw "Task action does not match the requested script: $($Context.TaskPath)$($Context.TaskName)"
        }

        if (-not $registeredTask.Triggers -or
            $registeredTask.Triggers.Count -ne 1 -or
            $registeredTask.Triggers[0].CimClass.CimClassName -ne 'MSFT_TaskLogonTrigger' -or
            -not $registeredTask.Triggers[0].Enabled -or
            $registeredTask.Triggers[0].UserId -ne $Context.CurrentUser) {
            throw "Task does not have the expected current-user logon trigger: $($Context.TaskPath)$($Context.TaskName)"
        }

        if (-not $registeredTask.Settings.Enabled -or
            $registeredTask.Principal.RunLevel -ne 'Highest' -or
            $registeredTask.Principal.LogonType -ne 'Interactive') {
            throw "Task enabled state or principal differs from the existing task: $($Context.TaskPath)$($Context.TaskName)"
        }

        $taskSettings = $registeredTask.Settings
        if ($taskSettings.DisallowStartIfOnBatteries -or
            -not $taskSettings.StopIfGoingOnBatteries -or
            -not $taskSettings.StartWhenAvailable -or
            $taskSettings.MultipleInstances -ne 'IgnoreNew' -or
            -not $taskSettings.UseUnifiedSchedulingEngine -or
            $taskSettings.IdleSettings.IdleDuration -ne 'PT10M' -or
            $taskSettings.IdleSettings.WaitTimeout -ne 'PT1H' -or
            -not $taskSettings.IdleSettings.StopOnIdleEnd -or
            $taskSettings.IdleSettings.RestartOnIdle) {
            throw "Task settings differ from the existing profile task: $($Context.TaskPath)$($Context.TaskName)"
        }
    }

    # Display the registered task identity and action for review.
    function Show-TaskRegistrationResult {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        $task = Get-ScheduledTask `
            -TaskPath $Context.TaskPath `
            -TaskName $Context.TaskName `
            -ErrorAction Stop
        Write-Host "Task registered: $($task.TaskName)" -ForegroundColor Green
        Write-Host "Task path: $($task.TaskPath)" -ForegroundColor Gray
        Write-Host "Runs as: $($task.Principal.UserId)" -ForegroundColor Gray
        Write-Host "Run level: $($task.Principal.RunLevel)" -ForegroundColor Gray

        $task.Actions |
            ForEach-Object {
                Write-Host "Action: $($_.Execute) $($_.Arguments)" -ForegroundColor Gray
            }
    }
}

#endregion

#region EXECUTION
# Execute from script root and always restore caller location.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
#endregion
