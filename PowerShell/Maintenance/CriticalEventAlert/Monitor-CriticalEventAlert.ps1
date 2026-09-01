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
    [switch]$Baseline,

    [switch]$TestToast,

    [switch]$LoginCheck
)

# Monitoring configuration
$ApplicationName = 'GregTate\CriticalEventAlert'
$EventSource = 'CriticalEventAlert'
$StatePath = Join-Path $env:LOCALAPPDATA "$ApplicationName\state.json"
$LogPath = Join-Path $env:LOCALAPPDATA "$ApplicationName\CriticalEventAlert.log"
$ModulePath = Join-Path $PSScriptRoot 'CriticalEventAlert.psm1'

$Main = {
    . $Helpers

    Import-CriticalEventAlertModule

    # Record each invocation and route manual toast tests away from monitoring.
    Write-CriticalEventAlertLog `
        -Path $LogPath `
        -Message "Run started. Baseline=$Baseline; TestToast=$TestToast; LoginCheck=$LoginCheck."

    try {
        if ($TestToast) {
            $toastShown = Invoke-CriticalEventAlertToastTest

            if (-not $toastShown) {
                throw 'The toast test did not display a notification.'
            }

            Write-Output 'Toast notification displayed.'
        }
        elseif ($LoginCheck) {
            Invoke-CriticalEventAlertLoginCheck
        }
        else {
            Invoke-CriticalEventAlertMonitor
        }
    }
    catch {
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Level Error `
            -Message "Run failed: $($_.Exception.Message)"
        throw
    }
    finally {
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message 'Run finished.'
    }
}

$Helpers = {
    # Load the maintained shared implementation that accompanies this monitor.
    function Import-CriticalEventAlertModule {
        Import-Module -Name $ModulePath -Force -ErrorAction Stop
    }

    # Display a synthetic toast using the same delivery path as real alerts.
    function Invoke-CriticalEventAlertToastTest {
        $candidate = [pscustomobject]@{
            Classification = 'Test toast notification'
            Description    = 'Manual CriticalEventAlert toast delivery test.'
            Device         = 'Manual test'
            EventId        = 0
            ProviderName   = 'CriticalEventAlert.Test'
            TimeCreated    = Get-Date
            RecordId       = 0
        }

        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message 'Toast test started.'
        $failureReason = $null
        $toastShown = Show-CriticalEventAlertToast `
            -Candidate $candidate `
            -LogPath $LogPath `
            -FailureReason ([ref]$failureReason)

        if ($toastShown) {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Message 'Toast test result: displayed.'
        }
        else {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Level Warning `
                -Message "Toast test result: not displayed. Reason=$failureReason"
        }

        return $toastShown
    }

    # Run the complete reliability scan at sign-in and always display one status toast.
    function Invoke-CriticalEventAlertLoginCheck {
        $stateAlreadyExists = Test-Path -LiteralPath $StatePath
        $state = Get-CriticalEventAlertState -Path $StatePath
        $issueCandidates = @()
        $scanCompleted = $true

        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message "Login check started. StateExists=$stateAlreadyExists."

        try {
            # Establish the first-run baseline without replaying historical System events.
            if ($Baseline -or -not $stateAlreadyExists) {
                $state.LastScanUtc = [datetime]::UtcNow.ToString('o')
            }
            else {
                # Read events since the prior completed login check and retain every candidate.
                $startTime = [datetime]::Parse(
                    $state.LastScanUtc,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind
                )
                $events = Get-WinEvent -FilterHashtable @{
                    LogName   = 'System'
                    StartTime = $startTime.ToLocalTime()
                } -ErrorAction Stop |
                    Sort-Object -Property TimeCreated, RecordId

                foreach ($eventRecord in $events) {
                    $candidate = $eventRecord |
                        ConvertTo-CriticalEventAlertCandidate

                    if ($candidate) {
                        $issueCandidates += $candidate
                        Invoke-CriticalEventAlertCandidate `
                            -Candidate $candidate `
                            -State $state `
                            -SuppressToast
                    }
                }
            }

            # Evaluate current physical-disk health without creating an individual toast.
            try {
                $diskCandidates = @(Get-CriticalEventAlertDiskHealthCandidate)
            }
            catch {
                $scanCompleted = $false
                $diskCandidates = @()
                Write-CriticalEventAlertLog `
                    -Path $LogPath `
                    -Level Warning `
                    -Message "Physical disk health check was unavailable: $($_.Exception.Message)"
            }

            foreach ($candidate in $diskCandidates) {
                $issueCandidates += $candidate
                Invoke-CriticalEventAlertCandidate `
                    -Candidate $candidate `
                    -State $state `
                    -SuppressToast
            }

            # Advance the checkpoint only when the login scan completed.
            if ($scanCompleted) {
                $state.LastScanUtc = [datetime]::UtcNow.ToString('o')
                Save-CriticalEventAlertState -State $state -Path $StatePath
            }
        }
        catch {
            $scanCompleted = $false
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Level Error `
                -Message "Login reliability scan failed: $($_.Exception.Message)"
        }

        # Combine Kernel-Power, EventLog, and WER records that represent one reboot.
        if (@($issueCandidates).Count -gt 0) {
            $candidateCountBeforeCorrelation = @($issueCandidates).Count
            $issueCandidates = @(Get-CriticalEventAlertIncidentCandidate -Candidate $issueCandidates)
            $candidateCountAfterCorrelation = @($issueCandidates).Count

            if ($candidateCountAfterCorrelation -lt $candidateCountBeforeCorrelation) {
                Write-CriticalEventAlertLog `
                    -Path $LogPath `
                    -Message "Reboot records correlated. CandidatesBefore=$candidateCountBeforeCorrelation; CandidatesAfter=$candidateCountAfterCorrelation."
            }
        }

        $issueCount = @($issueCandidates).Count
        if (-not $scanCompleted) {
            $classification = 'Reliability check incomplete'
            $device = 'Review the alert log for details'
        }
        elseif ($issueCount -gt 0) {
            $classification = 'Reliability issues detected'
            $device = '{0} issue candidate(s) found since the previous check' -f $issueCount
        }
        else {
            $classification = 'No current reliability issues'
            $device = 'Monitored System events and physical disks are healthy'
        }

        $summary = [pscustomobject]@{
            Classification = $classification
            Description    = 'CriticalEventAlert login status summary.'
            Device         = $device
            EventId        = 0
            ProviderName   = 'CriticalEventAlert.LoginCheck'
            TimeCreated    = Get-Date
            RecordId       = 0
        }
        $failureReason = $null
        $toastShown = Show-CriticalEventAlertToast `
            -Candidate $summary `
            -LogPath $LogPath `
            -FailureReason ([ref]$failureReason)

        if ($toastShown) {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Message "Login status toast displayed. Classification=$classification."
        }
        else {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Level Error `
                -Message "Login status toast was not displayed. Reason=$failureReason"
            throw 'The login status toast did not display.'
        }
    }

    # Process qualifying event-log and physical-disk health signals.
    function Invoke-CriticalEventAlertMonitor {
        # Load or create the per-user checkpoint before querying the System log.
        $stateAlreadyExists = Test-Path -LiteralPath $StatePath
        $state = Get-CriticalEventAlertState -Path $StatePath
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message "Monitoring started. StateExists=$stateAlreadyExists; Baseline=$Baseline."

        # Establish the first-run baseline without replaying historical System events.
        if ($Baseline -or -not $stateAlreadyExists) {
            $state.LastScanUtc = [datetime]::UtcNow.ToString('o')
            Invoke-CriticalEventAlertDiskHealthCheck -State $state
            Save-CriticalEventAlertState -State $state -Path $StatePath
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Message "Baseline completed. Historical System events were skipped; checkpoint=$($state.LastScanUtc)."
            return
        }

        # Read all System events recorded since the prior completed monitor run.
        $startTime = [datetime]::Parse(
            $state.LastScanUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message "Scanning System events from $($startTime.ToUniversalTime().ToString('o'))."
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
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message "Monitoring completed. Checkpoint=$($state.LastScanUtc)."
    }

    # Write every candidate to the event log and notify only when not suppressed.
    function Invoke-CriticalEventAlertCandidate {
        param(
            [Parameter(Mandatory)]
            [psobject]$Candidate,

            [Parameter(Mandatory)]
            [hashtable]$State,

            [switch]$SuppressToast
        )

        # Retain the observed event regardless of notification suppression state.
        Write-CriticalEventAlertLog `
            -Path $LogPath `
            -Message "Candidate detected: Classification=$($Candidate.Classification); Provider=$($Candidate.ProviderName); EventId=$($Candidate.EventId); Device=$($Candidate.Device)."
        Write-CriticalEventAlertEventLog -Candidate $Candidate -Source $EventSource
        $signature = Get-CriticalEventAlertSignature -Candidate $Candidate

        if ($SuppressToast) {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Message "Toast skipped for login-only policy. Signature=$signature."
            return
        }

        # Show a toast only when this issue has not already been presented recently.
        if (Test-CriticalEventAlertSuppression -State $State -Signature $signature) {
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Message "Toast suppressed for signature=$signature."
        }
        else {
            $failureReason = $null
            $toastShown = Show-CriticalEventAlertToast `
                -Candidate $Candidate `
                -LogPath $LogPath `
                -FailureReason ([ref]$failureReason)

            if ($toastShown) {
                Set-CriticalEventAlertSuppression -State $State -Signature $signature
                Write-CriticalEventAlertLog `
                    -Path $LogPath `
                    -Message "Toast displayed and suppression recorded for signature=$signature."
            }
            else {
                Write-CriticalEventAlertLog `
                    -Path $LogPath `
                    -Level Warning `
                    -Message "Toast was not displayed for signature=$signature. Reason=$failureReason"
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
            Write-CriticalEventAlertLog `
                -Path $LogPath `
                -Level Warning `
                -Message "Physical disk health check was unavailable: $($_.Exception.Message)"
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
