# -------------------------------------------------------------------------
# Program: Register-ProfileMaintenanceLogonTask.ps1
# Description: Creates a logon scheduled task that runs WinGet app and PowerShell module updates with no profile in a hidden console.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

<#
.SYNOPSIS
Creates or updates a Windows Scheduled Task for WinGet app and PowerShell module updates at user logon.

.DESCRIPTION
Registers a scheduled task that runs both maintenance scripts at logon using PowerShell with -NoProfile in a hidden window:
- Invoke-PowerShellModuleUpdates.ps1
- Invoke-WingetUpdates.ps1

The task runs with highest privileges for the current user.

Use -Unregister to remove the scheduled task instead of creating or updating it.

.PARAMETER TaskName
Name of the scheduled task. Defaults to WinGet Apps and PowerShell Modules Updates At Logon.

.PARAMETER TaskPath
Task Scheduler folder path for the task. Defaults to \Greg\.

.PARAMETER Unregister
Removes the scheduled task with the specified name.

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
    [string]$TaskName = 'WinGet Apps and PowerShell Modules Updates At Logon',

    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = '\Greg\',

    [switch]$Unregister
)

$Main = {
    . $Helpers

    # Ensure the script is running on Windows where ScheduledTasks is available.
    Confirm-TaskPlatformSupport

    # Remove the scheduled task and stop when unregister mode is requested.
    if ($Unregister) {
        Unregister-ProfileMaintenanceTask -TaskName $TaskName -TaskPath $TaskPath
        return
    }

    # Resolve required paths and validate prerequisites before task registration.
    $context = Get-TaskRegistrationContext
    Confirm-TaskRegistrationPrerequisites -Context $context

    # Register or update the scheduled task with two logon actions.
    Register-ProfileMaintenanceTask -Context $context

    # Show the resulting task details for quick verification.
    Show-TaskRegistrationResult -TaskName $TaskName -TaskPath $TaskPath
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
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $pwshCommand = Get-Command -Name 'pwsh.exe' -ErrorAction SilentlyContinue
        $normalizedTaskPath = ConvertTo-NormalizedTaskPath -TaskPath $TaskPath

        [PSCustomObject]@{
            ScriptRoot             = $scriptRoot
            ModuleUpdateScriptPath = $moduleUpdateScriptPath
            WingetUpdateScriptPath = $wingetUpdateScriptPath
            CurrentUser            = $currentUser
            PwshPath               = if ($pwshCommand) { $pwshCommand.Source } else { $null }
            TaskName               = $TaskName
            TaskPath               = $normalizedTaskPath
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

    function Confirm-TaskRegistrationPrerequisites {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        # Ensure both maintenance scripts exist in the same folder as this script.
        if (-not (Test-Path -Path $Context.ModuleUpdateScriptPath)) {
            throw "Script not found: $($Context.ModuleUpdateScriptPath)"
        }

        if (-not (Test-Path -Path $Context.WingetUpdateScriptPath)) {
            throw "Script not found: $($Context.WingetUpdateScriptPath)"
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

    function Ensure-ScheduledTaskFolder {
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

    function Register-ProfileMaintenanceTask {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$Context
        )

        # Create two actions so both maintenance scripts run at each user logon.
        $action1 = New-ScheduledTaskAction -Execute $Context.PwshPath -Argument "-NoProfile -WindowStyle Hidden -File `"$($Context.ModuleUpdateScriptPath)`" -AllModules" -WorkingDirectory $Context.ScriptRoot
        $action2 = New-ScheduledTaskAction -Execute $Context.PwshPath -Argument "-NoProfile -WindowStyle Hidden -File `"$($Context.WingetUpdateScriptPath)`"" -WorkingDirectory $Context.ScriptRoot

        # Trigger task at logon for the current user account.
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Context.CurrentUser

        # Run task with highest privileges using current user's interactive logon token.
        $principal = New-ScheduledTaskPrincipal -UserId $Context.CurrentUser -LogonType Interactive -RunLevel Highest

        # Configure basic task behavior for logon automation.
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable

        # Ensure the requested Task Scheduler folder exists before registration.
        Ensure-ScheduledTaskFolder -TaskPath $Context.TaskPath

        # Register or replace the task definition.
        $taskDefinition = New-ScheduledTask -Action @($action1, $action2) -Principal $principal -Trigger $trigger -Settings $settings
        Register-ScheduledTask -TaskPath $Context.TaskPath -TaskName $Context.TaskName -InputObject $taskDefinition -Force | Out-Null
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
