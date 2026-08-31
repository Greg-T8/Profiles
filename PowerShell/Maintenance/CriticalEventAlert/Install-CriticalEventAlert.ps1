<#
.SYNOPSIS
Installs the Critical Event Alert scheduled task for the current user.

.DESCRIPTION
Registers the dedicated Application event-log source, copies maintained monitor
files to LocalAppData, establishes an event baseline, and creates or updates the
current user's event-triggered and logon-triggered monitoring task.

.CONTEXT
Personal PowerShell profile - Windows reliability monitoring

.AUTHOR
Greg Tate

.NOTES
Program: Install-CriticalEventAlert.ps1
#>

[CmdletBinding()]
param()

# Installation configuration
$ApplicationName = 'GregTate\CriticalEventAlert'
$EventSource = 'CriticalEventAlert'
$InstallationPath = Join-Path $env:LOCALAPPDATA $ApplicationName
$TaskName = 'CriticalEventAlert'
$TaskPath = '\GregTate\'

$Main = {
    . $Helpers

    Confirm-CriticalEventAlertAdministrator
    Initialize-CriticalEventAlertInstallation
    Register-CriticalEventAlertEventSource
    Initialize-CriticalEventAlertBaseline
    Register-CriticalEventAlertTask
}

$Helpers = {
    # Ensure event-log source registration occurs only from an elevated session.
    function Confirm-CriticalEventAlertAdministrator {
        # Stop before making partial changes when the installer is not elevated.
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Run Install-CriticalEventAlert.ps1 from an elevated PowerShell session.'
        }
    }

    # Copy the maintained monitor implementation into its stable task execution location.
    function Initialize-CriticalEventAlertInstallation {
        # Create the application folder before copying task dependencies.
        New-Item -ItemType Directory -Path $InstallationPath -Force |
            Out-Null

        # Copy only the task payload files so the task does not depend on the repository path.
        foreach ($fileName in @('CriticalEventAlert.psm1', 'Monitor-CriticalEventAlert.ps1')) {
            $sourcePath = Join-Path $PSScriptRoot $fileName
            $destinationPath = Join-Path $InstallationPath $fileName

            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Required task payload file was not found: $sourcePath"
            }

            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
    }

    # Create the Application event-log source used for durable alert history.
    function Register-CriticalEventAlertEventSource {
        # Preserve an existing source while preventing accidental use of a different log.
        if ([Diagnostics.EventLog]::SourceExists($EventSource)) {
            $existingLog = [Diagnostics.EventLog]::LogNameFromSourceName($EventSource, '.')

            if ($existingLog -ne 'Application') {
                throw "The $EventSource event source already belongs to the $existingLog log."
            }

            return
        }

        New-EventLog -LogName Application -Source $EventSource
    }

    # Create the event-log checkpoint before task registration can trigger the monitor.
    function Initialize-CriticalEventAlertBaseline {
        # Use the installed monitor so the task and installer share the same state contract.
        $powerShellPath = Join-Path $PSHOME 'pwsh.exe'
        $monitorPath = Join-Path $InstallationPath 'Monitor-CriticalEventAlert.ps1'
        & $powerShellPath `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $monitorPath `
            -Baseline

        if ($LASTEXITCODE -ne 0) {
            throw "The monitor baseline failed with exit code $LASTEXITCODE."
        }
    }

    # Create the task folder and register the focused event and logon triggers.
    function Register-CriticalEventAlertTask {
        # Build the current user's SID and PowerShell executable path for task registration.
        $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $powerShellPath = Join-Path $PSHOME 'pwsh.exe'
        $monitorPath = Join-Path $InstallationPath 'Monitor-CriticalEventAlert.ps1'

        if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
            throw "PowerShell executable was not found: $powerShellPath"
        }

        # Ensure the purpose-named Task Scheduler folder exists without modifying other tasks.
        $schedulerService = New-Object -ComObject 'Schedule.Service'
        $schedulerService.Connect()

        try {
            $null = $schedulerService.GetFolder($TaskPath.TrimEnd('\\'))
        }
        catch {
            $null = $schedulerService.GetFolder('\').CreateFolder('GregTate', $null)
        }

        # Select all Critical System events plus precise storage and fatal hardware signatures.
        $eventSubscription = @'
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[(Level=1) or (Provider[@Name='Disk'] and (EventID=7 or EventID=11 or EventID=15 or EventID=51 or EventID=153 or EventID=157)) or ((Provider[@Name='storahci'] or Provider[@Name='storport']) and (EventID=11 or EventID=129 or EventID=153 or EventID=157)) or (Provider[@Name='Ntfs'] and EventID=55) or (Provider[@Name='Microsoft-Windows-WHEA-Logger'] and (EventID=1 or EventID=18))]]</Select>
  </Query>
</QueryList>
'@

        # Escape machine-specific values before inserting them into Task Scheduler XML.
        $escapedUserSid = [Security.SecurityElement]::Escape($currentUserSid)
        $escapedPowerShellPath = [Security.SecurityElement]::Escape($powerShellPath)
        $escapedMonitorPath = [Security.SecurityElement]::Escape($monitorPath)
        $escapedInstallationPath = [Security.SecurityElement]::Escape($InstallationPath)
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Greg Tate</Author>
    <Description>Alerts the signed-in user about focused Windows reliability events.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription><![CDATA[$eventSubscription]]></Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$escapedUserSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$escapedPowerShellPath</Command>
      <Arguments>-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File &quot;$escapedMonitorPath&quot;</Arguments>
      <WorkingDirectory>$escapedInstallationPath</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

        # Update only the named task so unrelated scheduled tasks remain untouched.
        Register-ScheduledTask `
            -TaskName $TaskName `
            -TaskPath $TaskPath `
            -Xml $taskXml `
            -Force |
            Out-Null
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
