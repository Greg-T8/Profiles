# -------------------------------------------------------------------------
# Program: Register-SnagitCaptureFolderCleanupTask.ps1
# Description: Registers the Snagit capture folder cleanup scheduled task for the current user
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# -------------------------------------------------------------------------

<#
.SYNOPSIS
Registers or unregisters the Snagit capture folder cleanup task for the current user.

.DESCRIPTION
Creates or updates one logon-triggered scheduled task for Invoke-SnagitCaptureFolderCleanup.ps1.

.PARAMETER TaskPath
Task Scheduler folder path. Defaults to \Custom Tasks\.

.PARAMETER Unregister
Removes only this maintenance task.

.EXAMPLE
.\Maintenance\Register-SnagitCaptureFolderCleanupTask.ps1

.EXAMPLE
.\Maintenance\Register-SnagitCaptureFolderCleanupTask.ps1 -Unregister

.NOTES
Program: Register-SnagitCaptureFolderCleanupTask.ps1
#>

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = '\Custom Tasks\',

    [switch]$Unregister
)

# Define the task identity and its target maintenance script.
$TaskName = 'Clean Up Snagit Capture Folder At Logon'
$InvokeScriptName = 'Invoke-SnagitCaptureFolderCleanup.ps1'
$TaskArguments = ''

$Main = {
    . $Helpers

    # Ensure Task Scheduler is available before managing the task.
    Confirm-TaskPlatformSupport

    # Build the task context from the current user and this script location.
    $context = Get-TaskRegistrationContext

    # Remove only the matching task and exit when unregister mode is requested.
    if ($Unregister) {
        Unregister-MaintenanceTask -Context $context
        return
    }

    # Validate the target script and PowerShell executable before registration.
    Confirm-TaskRegistrationPrerequisite -Context $context

    # Register or update the one maintenance task.
    Register-MaintenanceTask -Context $context

    # Confirm the task action and logon settings after registration.
    Confirm-MaintenanceTask -Context $context
    Show-TaskRegistrationResult -Context $context
}

$Helpers = {
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

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}