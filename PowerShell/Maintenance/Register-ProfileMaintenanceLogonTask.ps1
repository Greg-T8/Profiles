# -------------------------------------------------------------------------
# Program: Register-ProfileMaintenanceLogonTask.ps1
# Description: Creates separate logon scheduled tasks for WinGet, PowerShell module, and Snagit capture cleanup updates.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

<#
.SYNOPSIS
Creates or updates Windows Scheduled Tasks for profile maintenance scripts at user logon.

.DESCRIPTION
Registers separate scheduled tasks that run maintenance scripts at logon using PowerShell with -NoProfile in a hidden window:
- Invoke-PowerShellModuleUpdates.ps1
- Invoke-WingetUpdates.ps1
- Invoke-SnagitCaptureFolderCleanup.ps1

Each task runs with highest privileges for the current user and preserves the existing logon task settings.

Use -Unregister to remove the maintenance tasks instead of creating or updating them.

.PARAMETER TaskPath
Task Scheduler folder path for the tasks. Defaults to \Custom Tasks\.

.PARAMETER Unregister
Removes the three maintenance tasks and the retired combined task.

.EXAMPLE
.\Maintenance\Register-ProfileMaintenanceLogonTask.ps1

.EXAMPLE
.\Maintenance\Register-ProfileMaintenanceLogonTask.ps1 -Unregister

.NOTES
Program: Register-ProfileMaintenanceLogonTask.ps1
#>

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = '\Custom Tasks\',

    [switch]$Unregister
)

$Main = {
    . $Helpers

    # Ensure the script is running on Windows where ScheduledTasks is available.
    Confirm-TaskPlatformSupport

    # Remove the scheduled task and stop when unregister mode is requested.
    if ($Unregister) {
        Unregister-ProfileMaintenanceTaskSet -TaskPath $TaskPath
        return
    }

    # Resolve required paths and validate prerequisites before task registration.
    $context = Get-TaskRegistrationContext
    Confirm-TaskRegistrationPrerequisite -Context $context

    # Register or update the three independent logon tasks.
    Register-ProfileMaintenanceTask -Context $context

    # Verify every replacement before removing the former combined task.
    Confirm-ProfileMaintenanceTask -Context $context
    Unregister-ProfileMaintenanceTask -TaskName 'WinGet Apps and PowerShell Modules Updates At Logon' -TaskPath '\Greg\'
}

$Helpers = {
    function Confirm-TaskPlatformSupport {
        # Ensure the script is running on Windows where ScheduledTasks is available.
        if (-not $IsWindows) {
            throw 'This script requires Windows and the ScheduledTasks module.'
        }
    }

    function Get-TaskRegistrationContext {
        # Build reusable context values for task registration.
        $scriptRoot = $PSScriptRoot
        $moduleUpdateScriptPath = Join-Path -Path $scriptRoot -ChildPath 'Invoke-PowerShellModuleUpdates.ps1'
        $wingetUpdateScriptPath = Join-Path -Path $scriptRoot -ChildPath 'Invoke-WingetUpdates.ps1'
        $snagitCleanupScriptPath = Join-Path -Path $scriptRoot -ChildPath 'Invoke-SnagitCaptureFolderCleanup.ps1'
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $pwshCommand = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue
        $normalizedTaskPath = ConvertTo-NormalizedTaskPath -TaskPath $TaskPath

        [PSCustomObject]@{
            ScriptRoot             = $scriptRoot
            ModuleUpdateScriptPath = $moduleUpdateScriptPath
            WingetUpdateScriptPath = $wingetUpdateScriptPath
            SnagitCleanupScriptPath = $snagitCleanupScriptPath
            CurrentUser            = $currentUser
            PwshPath               = if ($pwshCommand) { $pwshCommand.Source } else { $null }
            TaskPath               = $normalizedTaskPath
            Tasks                  = @(
                [PSCustomObject]@{
                    TaskName        = 'Update PowerShell Modules At Logon'
                    ScriptPath      = $moduleUpdateScriptPath
                    ScriptArguments = '-AllModules'
                },
                [PSCustomObject]@{
                    TaskName        = 'Update WinGet Apps At Logon'
                    ScriptPath      = $wingetUpdateScriptPath
                    ScriptArguments = ''
                },
                [PSCustomObject]@{
                    TaskName        = 'Clean Up Snagit Capture Folder At Logon'
                    ScriptPath      = $snagitCleanupScriptPath
                    ScriptArguments = ''
                }
            )
        }
    }

    function ConvertTo-NormalizedTaskPath {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskPath
        )

        # Normalize task path so it always has leading and trailing backslashes.
        $normalizedTaskPath = $TaskPath.Trim()
        if (-not $normalizedTaskPath.StartsWith('\')) {
            $normalizedTaskPath = "\$normalizedTaskPath"
        }

        if (-not $normalizedTaskPath.EndsWith('\')) {
            $normalizedTaskPath = "$normalizedTaskPath\"
        }

        return $normalizedTaskPath
    }

    function Confirm-TaskRegistrationPrerequisite {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        # Ensure maintenance scripts exist in the same folder as this script.
        if (-not (Test-Path -Path $Context.ModuleUpdateScriptPath)) {
            throw "Script not found: $($Context.ModuleUpdateScriptPath)"
        }

        if (-not (Test-Path -Path $Context.WingetUpdateScriptPath)) {
            throw "Script not found: $($Context.WingetUpdateScriptPath)"
        }

        if (-not (Test-Path -Path $Context.SnagitCleanupScriptPath)) {
            throw "Script not found: $($Context.SnagitCleanupScriptPath)"
        }

        # Ensure PowerShell executable is available for scheduled task actions.
        if ([string]::IsNullOrWhiteSpace($Context.PwshPath)) {
            throw 'pwsh.exe was not found on PATH.'
        }
    }

    function Unregister-ProfileMaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskPath
        )

        # Remove the task when present and report status when it is already absent.
        $normalizedTaskPath = ConvertTo-NormalizedTaskPath -TaskPath $TaskPath
        $task = Get-ScheduledTask -TaskPath $normalizedTaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "Task not found: $normalizedTaskPath$TaskName" -ForegroundColor Yellow
            return
        }

        Unregister-ScheduledTask -TaskPath $normalizedTaskPath -TaskName $TaskName -Confirm:$false
        Write-Host "Task unregistered: $normalizedTaskPath$TaskName" -ForegroundColor Yellow
    }

    # Create the requested Task Scheduler folder when it does not already exist.
    function New-ScheduledTaskFolder {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskPath
        )

        # Create the task folder when it does not exist.
        $normalizedTaskPath = ConvertTo-NormalizedTaskPath -TaskPath $TaskPath
        $folderName = $normalizedTaskPath.Trim('\')
        if ([string]::IsNullOrWhiteSpace($folderName)) {
            return
        }

        $scheduleService = New-Object -ComObject 'Schedule.Service'
        $scheduleService.Connect()

        try {
            $null = $scheduleService.GetFolder("\$folderName")
        }
        catch {
            if ($PSCmdlet.ShouldProcess($normalizedTaskPath, 'Create Task Scheduler folder')) {
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
    }

    # Register each maintenance script as its own scheduled task.
    function Register-ProfileMaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        # Create the shared trigger, principal, and settings used by each task.
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Context.CurrentUser
        $principal = New-ScheduledTaskPrincipal -UserId $Context.CurrentUser -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -StartWhenAvailable -IdleDuration (New-TimeSpan -Minutes 10) -IdleWaitTimeout (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew -Priority 7 -ExecutionTimeLimit (New-TimeSpan -Hours 72)

        # Ensure the requested Task Scheduler folder exists before registering tasks.
        New-ScheduledTaskFolder -TaskPath $Context.TaskPath

        # Register each maintenance script as an independent task with one action.
        foreach ($task in $Context.Tasks) {
            $arguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $task.ScriptPath
            if (-not [string]::IsNullOrWhiteSpace($task.ScriptArguments)) {
                $arguments = '{0} {1}' -f $arguments, $task.ScriptArguments
            }

            $action = New-ScheduledTaskAction -Execute $Context.PwshPath -Argument $arguments -WorkingDirectory $Context.ScriptRoot
            $taskDefinition = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings
            Register-ScheduledTask -TaskPath $Context.TaskPath -TaskName $task.TaskName -InputObject $taskDefinition -Force | Out-Null
        }
    }

    # Check each replacement task before the combined task is removed.
    function Confirm-ProfileMaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        # Confirm each replacement has its intended single action and logon trigger.
        foreach ($taskDefinition in $Context.Tasks) {
            $registeredTask = Get-ScheduledTask -TaskPath $Context.TaskPath -TaskName $taskDefinition.TaskName -ErrorAction Stop
            if ($registeredTask.Actions.Count -ne 1) {
                throw "Task does not have exactly one action: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }

            $expectedArguments = '-NoProfile -WindowStyle Hidden -File "{0}"' -f $taskDefinition.ScriptPath
            if (-not [string]::IsNullOrWhiteSpace($taskDefinition.ScriptArguments)) {
                $expectedArguments = '{0} {1}' -f $expectedArguments, $taskDefinition.ScriptArguments
            }

            if ($registeredTask.Actions[0].Execute -ne $Context.PwshPath -or $registeredTask.Actions[0].Arguments -ne $expectedArguments) {
                throw "Task action does not match the requested script: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }

            if (-not $registeredTask.Triggers -or $registeredTask.Triggers[0].CimClass.CimClassName -ne 'MSFT_TaskLogonTrigger') {
                throw "Task does not have the expected logon trigger: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }

            if ($registeredTask.Triggers.Count -ne 1 -or -not $registeredTask.Triggers[0].Enabled -or $registeredTask.Triggers[0].UserId -ne $Context.CurrentUser) {
                throw "Task logon trigger does not match the current user: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }

            if (-not $registeredTask.Settings.Enabled -or $registeredTask.Principal.RunLevel -ne 'Highest' -or $registeredTask.Principal.LogonType -ne 'Interactive') {
                throw "Task enabled state or principal differs from the existing task: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }

            $settings = $registeredTask.Settings
            if ($settings.DisallowStartIfOnBatteries -or -not $settings.StopIfGoingOnBatteries -or -not $settings.StartWhenAvailable -or $settings.MultipleInstances -ne 'IgnoreNew' -or -not $settings.UseUnifiedSchedulingEngine -or $settings.IdleSettings.IdleDuration -ne 'PT10M' -or $settings.IdleSettings.WaitTimeout -ne 'PT1H' -or -not $settings.IdleSettings.StopOnIdleEnd -or $settings.IdleSettings.RestartOnIdle) {
                throw "Task settings differ from the existing combined task: $($registeredTask.TaskPath)$($registeredTask.TaskName)"
            }
        }
    }

    # Remove all split task names and the retired combined registration.
    function Unregister-ProfileMaintenanceTaskSet {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskPath
        )

        # Remove each split task and the original combined registration when present.
        foreach ($taskName in @(
            'Update PowerShell Modules At Logon',
            'Update WinGet Apps At Logon',
            'Clean Up Snagit Capture Folder At Logon',
            'WinGet Apps and PowerShell Modules Updates At Logon'
        )) {
            Unregister-ProfileMaintenanceTask -TaskName $taskName -TaskPath $TaskPath
        }

        Unregister-ProfileMaintenanceTask -TaskName 'WinGet Apps and PowerShell Modules Updates At Logon' -TaskPath 'Greg'
    }

    function Show-TaskRegistrationResult {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskPath
        )

        # Display the scheduled task summary and actions that were registered.
        $normalizedTaskPath = ConvertTo-NormalizedTaskPath -TaskPath $TaskPath
        $task = Get-ScheduledTask -TaskPath $normalizedTaskPath -TaskName $TaskName -ErrorAction Stop
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
