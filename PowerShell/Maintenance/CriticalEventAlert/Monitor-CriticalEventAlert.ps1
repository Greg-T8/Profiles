<#
.SYNOPSIS
Monitors focused Windows reliability events and notifies the signed-in user.

.DESCRIPTION
Reads new qualifying System events and current physical-disk health, writes an
Application event-log record for every detected issue, and suppresses repeated
toast notifications for 24 hours.

.CONTEXT
Personal PowerShell profile - Windows reliability monitoring

.AUTHOR
Greg Tate

.NOTES
Program: Monitor-CriticalEventAlert.ps1
#>

[CmdletBinding()]
param(
    [switch]$Baseline
)

# Monitoring configuration
$ApplicationName = 'GregTate\CriticalEventAlert'
$EventSource = 'CriticalEventAlert'
$StatePath = Join-Path $env:LOCALAPPDATA "$ApplicationName\state.json"
$ModulePath = Join-Path $PSScriptRoot 'CriticalEventAlert.psm1'

$Main = {
    . $Helpers

    Import-CriticalEventAlertModule
    Invoke-CriticalEventAlertMonitor
}

$Helpers = {
    # Load the maintained shared implementation that accompanies this monitor.
    function Import-CriticalEventAlertModule {
        Import-Module -Name $ModulePath -Force -ErrorAction Stop
    }

    # Process qualifying event-log and physical-disk health signals.
    function Invoke-CriticalEventAlertMonitor {
        # Load or create the per-user checkpoint before querying the System log.
        $stateAlreadyExists = Test-Path -LiteralPath $StatePath
        $state = Get-CriticalEventAlertState -Path $StatePath

        # Establish the first-run baseline without replaying historical System events.
        if ($Baseline -or -not $stateAlreadyExists) {
            $state.LastScanUtc = [datetime]::UtcNow.ToString('o')
            Invoke-CriticalEventAlertDiskHealthCheck -State $state
            Save-CriticalEventAlertState -State $state -Path $StatePath
            return
        }

        # Read all System events recorded since the prior completed monitor run.
        $startTime = [datetime]::Parse(
            $state.LastScanUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            StartTime = $startTime.ToLocalTime()
        } -ErrorAction Stop |
            Sort-Object -Property TimeCreated, RecordId

        # Persist every focused event and toast each unique issue at most once per day.
        foreach ($eventRecord in $events) {
            $candidate = $eventRecord |
                ConvertTo-CriticalEventAlertCandidate

            if ($candidate) {
                Invoke-CriticalEventAlertCandidate -Candidate $candidate -State $state
            }
        }

        # Evaluate persistent physical-disk health at sign-in and event-triggered runs.
        Invoke-CriticalEventAlertDiskHealthCheck -State $state

        # Advance the checkpoint only after all candidate processing succeeds.
        $state.LastScanUtc = [datetime]::UtcNow.ToString('o')
        Save-CriticalEventAlertState -State $state -Path $StatePath
    }

    # Write every candidate to the event log and notify only when not suppressed.
    function Invoke-CriticalEventAlertCandidate {
        param(
            [Parameter(Mandatory)]
            [psobject]$Candidate,

            [Parameter(Mandatory)]
            [hashtable]$State
        )

        # Retain the observed event regardless of notification suppression state.
        Write-CriticalEventAlertEventLog -Candidate $Candidate -Source $EventSource
        $signature = Get-CriticalEventAlertSignature -Candidate $Candidate

        # Show a toast only when this issue has not already been presented recently.
        if (-not (Test-CriticalEventAlertSuppression -State $State -Signature $signature)) {
            $toastShown = Show-CriticalEventAlertToast -Candidate $Candidate

            if ($toastShown) {
                Set-CriticalEventAlertSuppression -State $State -Signature $signature
            }
        }
    }

    # Convert current unhealthy physical disks into normal alert candidates.
    function Invoke-CriticalEventAlertDiskHealthCheck {
        param(
            [Parameter(Mandatory)]
            [hashtable]$State
        )

        # Avoid treating unavailable Storage cmdlets as a reliability alert.
        try {
            $diskCandidates = Get-CriticalEventAlertDiskHealthCandidate
        }
        catch {
            return
        }

        # Process each unhealthy disk using the same logging and suppression policy.
        foreach ($candidate in $diskCandidates) {
            Invoke-CriticalEventAlertCandidate -Candidate $candidate -State $State
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
