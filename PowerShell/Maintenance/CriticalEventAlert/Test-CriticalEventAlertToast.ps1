<#
.SYNOPSIS
Tests the CriticalEventAlert notification toast.

.DESCRIPTION
Invokes the installed CriticalEventAlert monitor in toast-test mode. The test
uses the same installed module and Windows toast bridge used by the scheduled
task, writes its result to the normal CriticalEventAlert log, and leaves the
monitor checkpoint and alert suppression history unchanged.

.CONTEXT
Personal PowerShell profile - Windows reliability monitoring

.AUTHOR
Greg Tate

.NOTES
Program: Test-CriticalEventAlertToast.ps1
#>

[CmdletBinding()]
param(
    [string]$MonitorPath = (Join-Path $env:LOCALAPPDATA 'GregTate\CriticalEventAlert\Monitor-CriticalEventAlert.ps1')
)

# Test configuration
$LogPath = Join-Path $env:LOCALAPPDATA 'GregTate\CriticalEventAlert\CriticalEventAlert.log'

$Main = {
    . $Helpers

    Confirm-CriticalEventAlertTestInstallation
    Invoke-CriticalEventAlertToastTest
}

$Helpers = {
    # Confirm that the test targets the installed scheduled-task payload.
    function Confirm-CriticalEventAlertTestInstallation {
        $requiredPath = Split-Path -Path $MonitorPath -Parent
        $modulePath = Join-Path $requiredPath 'CriticalEventAlert.psm1'

        if (-not (Test-Path -LiteralPath $MonitorPath -PathType Leaf)) {
            throw "Installed monitor was not found: $MonitorPath"
        }

        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "Installed module was not found: $modulePath"
        }
    }

    # Invoke the installed monitor's isolated toast-test path and report its result.
    function Invoke-CriticalEventAlertToastTest {
        try {
            & $MonitorPath -TestToast
        }
        catch {
            throw "CriticalEventAlert toast test failed. Review $LogPath. $($_.Exception.Message)"
        }

        Write-Output "CriticalEventAlert toast test completed. Review $LogPath for the recorded result."
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
