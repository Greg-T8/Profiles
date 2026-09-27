<#
.SYNOPSIS
Monitors focused Windows reliability events and notifies the signed-in user.

.DESCRIPTION
Reads new qualifying System events and current physical-disk health, writes an
Application event-log record for every detected issue, and suppresses repeated
toast notifications for 24 hours. Use -Register from an elevated session to
install the monitor and register its logon task.

.PARAMETER Baseline
Establishes the initial event checkpoint.

.PARAMETER TestToast
Displays a sample toast without running the monitor.

.PARAMETER LoginCheck
Runs the sign-in summary check used by the scheduled task.

.PARAMETER Register
Installs the standalone monitor payload and creates or updates its logon task.

.EXAMPLE
.\Monitor-CriticalEventAlert.ps1 -Register

.CONTEXT
Personal PowerShell profile - Windows reliability monitoring

.AUTHOR
Greg Tate

.NOTES
Program: Monitor-CriticalEventAlert.ps1
#>

[CmdletBinding(DefaultParameterSetName = 'Monitor')]
param(
    [Parameter(ParameterSetName = 'Monitor')]
    [switch]$Baseline,

    [Parameter(ParameterSetName = 'Monitor')]
    [switch]$TestToast,

    [Parameter(ParameterSetName = 'Monitor')]
    [switch]$LoginCheck,

    [Parameter(Mandatory, ParameterSetName = 'Register')]
    [switch]$Register
)

# Monitoring configuration
$ApplicationName  = 'GregTate\CriticalEventAlert'
$EventSource      = 'CriticalEventAlert'
$InstallationPath = Join-Path $env:LOCALAPPDATA $ApplicationName
$TaskName         = 'CriticalEventAlert'
$TaskPath         = '\Custom Tasks\'
$RegisterTask = $Register.IsPresent
$StatePath    = Join-Path $env:LOCALAPPDATA "$ApplicationName\state.json"
$LogPath      = Join-Path $env:LOCALAPPDATA "$ApplicationName\CriticalEventAlert.log"

$Main = {
    . $Helpers

    # Install the standalone monitor payload and task only when requested.
    if ($RegisterTask) {
        . $RegistrationHelpers
        Confirm-CriticalEventAlertAdministrator
        Initialize-CriticalEventAlertInstallation
        Register-CriticalEventAlertEventSource
        Initialize-CriticalEventAlertBaseline
        Register-CriticalEventAlertTask
        return
    }

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

    #region EVENT CLASSIFICATION
    # Functions that identify actionable Windows storage and hardware events.
    function ConvertTo-CriticalEventAlertCandidate {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, ValueFromPipeline)]
            [object]$EventRecord
        )

        process {
            # Read the event description without allowing a malformed record to stop monitoring.
            try {
                $description = $EventRecord.FormatDescription()
            }
            catch {
                $description = [string]$EventRecord.Message
            }

            # Classify only the focused storage, file-system, hardware, and Critical event set.
            $providerName = [string]$EventRecord.ProviderName
            $eventId = [int]$EventRecord.Id
            $classification = $null

            switch ($providerName) {
                'Disk' {
                    $classification = switch ($eventId) {
                        7 { 'Disk bad block detected' }
                        11 { 'Disk controller error' }
                        15 { 'Disk device not ready' }
                        51 { 'Disk paging I/O failure' }
                        153 { 'Disk I/O operation retried' }
                        154 { 'Disk I/O operation failed due to hardware error' }
                        157 { 'Disk unexpectedly removed' }
                    }
                }
                'storahci' {
                    $classification = switch ($eventId) {
                        11 { 'Storage controller error' }
                        129 { 'Storage device reset' }
                        153 { 'Storage I/O operation retried' }
                        157 { 'Storage device unexpectedly removed' }
                    }
                }
                'storport' {
                    $classification = switch ($eventId) {
                        11 { 'Storage controller error' }
                        129 { 'Storage device reset' }
                        153 { 'Storage I/O operation retried' }
                        157 { 'Storage device unexpectedly removed' }
                    }
                }
                'stornvme' {
                    $classification = switch ($eventId) {
                        11 { 'NVMe storage controller error' }
                        129 { 'NVMe storage device reset' }
                        153 { 'NVMe storage I/O operation retried' }
                        157 { 'NVMe storage device unexpectedly removed' }
                    }
                }
                'Ntfs' {
                    if ($eventId -eq 55) {
                        $classification = 'NTFS file-system corruption detected'
                    }
                }
                'Microsoft-Windows-WHEA-Logger' {
                    $classification = switch ($eventId) {
                        1 { 'Fatal hardware error reported by WHEA' }
                        18 { 'Fatal hardware error reported by WHEA' }
                        20 { 'Uncorrectable hardware error reported by WHEA' }
                    }
                }
                'Microsoft-Windows-Kernel-Power' {
                    if ($eventId -eq 41) {
                        $classification = 'Unexpected system reboot detected'
                    }
                }
                'EventLog' {
                    if ($eventId -eq 6008) {
                        $classification = 'Unexpected system shutdown detected'
                    }
                }
                'Microsoft-Windows-WER-SystemErrorReporting' {
                    if ($eventId -eq 1001) {
                        $classification = 'System bugcheck recorded'
                    }
                }
                'Microsoft-Windows-Resource-Exhaustion-Detector' {
                    if ($eventId -eq 2004) {
                        $classification = 'Low virtual memory condition detected'
                    }
                }
            }

            # Preserve visibility for any remaining Windows Critical System event.
            if (-not $classification -and [int]$EventRecord.Level -eq 1) {
                $classification = 'Windows Critical system event'
            }

            # Ignore events that are outside the focused alert policy.
            if (-not $classification) {
                return
            }

            # Mark only retry and reset conditions as warnings; these additions alert on one event.
            $severity = if ($eventId -in @(129, 153, 41, 6008, 2004)) {
                'Warning'
            }
            else {
                'Critical'
            }

            # Extract a stable device identity when the event description contains one.
            $device = Get-CriticalEventAlertDeviceIdentity -Description $description

            [pscustomobject]@{
                Classification = $classification
                Description    = $description
                Device          = $device
                EventId         = $eventId
                ProviderName    = $providerName
                Severity        = $severity
                TimeCreated     = $EventRecord.TimeCreated
                RecordId        = $EventRecord.RecordId
            }
        }
    }

    # Extract the most useful disk or device token from an event description.
    function Get-CriticalEventAlertDeviceIdentity {
        [CmdletBinding()]
        param(
            [AllowEmptyString()]
            [string]$Description
        )

        # Prefer Windows device paths because they distinguish otherwise identical events.
        if ($Description -match '(?i)\\Device\\Harddisk\d+(?:\\DR\d+)?') {
            return $Matches[0]
        }

        # Use a numbered disk reference when a device path is unavailable.
        if ($Description -match '(?i)\bDisk\s+\d+\b') {
            return $Matches[0]
        }

        return 'UnspecifiedDevice'
    }

    # Build a stable key used to suppress repeat notifications for the same issue.
    function Get-CriticalEventAlertSignature {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$Candidate
        )

        return ('{0}|{1}|{2}' -f `
            $Candidate.ProviderName, `
            $Candidate.EventId, `
            $Candidate.Device).ToLowerInvariant()
    }

    # Collapse matching reboot records into one incident while preserving their source events in the log.
    function Get-CriticalEventAlertIncidentCandidate {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object[]]$Candidate
        )

        $rebootCandidates = @($Candidate |
            Where-Object {
                ($_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.EventId -eq 41) -or
                ($_.ProviderName -eq 'EventLog' -and $_.EventId -eq 6008) -or
                ($_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' -and $_.EventId -eq 1001)
            } |
            Sort-Object -Property TimeCreated, RecordId)
        $otherCandidates = @($Candidate |
            Where-Object {
                -not (
                    ($_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.EventId -eq 41) -or
                    ($_.ProviderName -eq 'EventLog' -and $_.EventId -eq 6008) -or
                    ($_.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' -and $_.EventId -eq 1001)
                )
            })
        $rebootGroups = @()

        # Group reboot records that occur within five minutes of one another.
        foreach ($candidateItem in $rebootCandidates) {
            $eventTime = ([datetime]$candidateItem.TimeCreated).ToUniversalTime()
            $matchingGroup = @($rebootGroups |
                Where-Object { $eventTime -le $_.EndTime.AddMinutes(5) } |
                Select-Object -First 1)

            if ($matchingGroup.Count -gt 0) {
                $group = $matchingGroup[0]
                $group.Candidates = @($group.Candidates) + $candidateItem
                if ($eventTime -gt $group.EndTime) {
                    $group.EndTime = $eventTime
                }
            }
            else {
                $rebootGroups += [pscustomobject]@{
                    Candidates = @($candidateItem)
                    EndTime    = $eventTime
                }
            }
        }

        $mergedCandidates = @($otherCandidates)

        # Emit one synthetic reboot incident while retaining each original event for diagnostics.
        foreach ($group in $rebootGroups) {
            $groupCandidates = @($group.Candidates |
                Sort-Object -Property TimeCreated, RecordId)
            $relatedEvents = ($groupCandidates |
                ForEach-Object { '{0}/{1}' -f $_.ProviderName, $_.EventId }) -join ', '
            $mergedCandidates += [pscustomobject]@{
                Classification = 'Unexpected reboot incident'
                Description    = 'Matching reboot records: {0}' -f $relatedEvents
                Device         = 'System reboot'
                EventId        = 0
                ProviderName   = 'CriticalEventAlert.Reboot'
                Severity       = 'Critical'
                TimeCreated    = $groupCandidates[0].TimeCreated
                RecordId       = $groupCandidates[0].RecordId
            }
        }

        return $mergedCandidates |
            Sort-Object -Property TimeCreated, RecordId
    }
    #endregion

    #region STATE MANAGEMENT
    # Functions that persist alert checkpoints and repeat-notification history.
    function Get-CriticalEventAlertState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        # Initialize the state store without retrospectively alerting on old events.
        if (-not (Test-Path -LiteralPath $Path)) {
            return @{
                AlertHistory  = @{}
                InitializedAt = [datetime]::UtcNow.ToString('o')
                LastScanUtc   = [datetime]::UtcNow.ToString('o')
                SchemaVersion = 1
            }
        }

        return Get-Content -LiteralPath $Path -Raw |
            ConvertFrom-Json -AsHashtable
    }

    # Save the alert state atomically so interrupted runs do not corrupt it.
    function Save-CriticalEventAlertState {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable]$State,

            [Parameter(Mandatory)]
            [string]$Path
        )

        # Create the parent folder before writing the state checkpoint.
        $stateDirectory = Split-Path -Path $Path -Parent
        New-Item -ItemType Directory -Path $stateDirectory -Force |
            Out-Null

        # Replace the previous state only after the next JSON document is complete.
        $temporaryPath = '{0}.tmp' -f $Path
        $State |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $temporaryPath -Encoding utf8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }

    # Determine whether this issue has already been shown during the suppression window.
    function Test-CriticalEventAlertSuppression {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable]$State,

            [Parameter(Mandatory)]
            [string]$Signature,

            [datetime]$Now = [datetime]::UtcNow,

            [timespan]$Window = (New-TimeSpan -Hours 24)
        )

        # Do not suppress a signature that has never been presented to the user.
        if (-not $State.AlertHistory.ContainsKey($Signature)) {
            return $false
        }

        $lastAlert = [datetime]::Parse(
            $State.AlertHistory[$Signature],
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )

        return (($Now.ToUniversalTime() - $lastAlert.ToUniversalTime()) -lt $Window)
    }

    # Record an alert notification and discard suppression data that is no longer useful.
    function Set-CriticalEventAlertSuppression {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable]$State,

            [Parameter(Mandatory)]
            [string]$Signature,

            [datetime]$Now = [datetime]::UtcNow
        )

        # Keep recent alert timestamps for the 24-hour suppression calculation.
        $State.AlertHistory[$Signature] = $Now.ToUniversalTime().ToString('o')

        # Trim stale keys to keep the local state compact over long-running use.
        foreach ($key in @($State.AlertHistory.Keys)) {
            $timestamp = [datetime]::Parse(
                $State.AlertHistory[$key],
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind
            )

            if (($Now.ToUniversalTime() - $timestamp.ToUniversalTime()) -gt (New-TimeSpan -Days 30)) {
                $State.AlertHistory.Remove($key)
            }
        }
    }
    #endregion

    #region ALERT DELIVERY
    # Functions that persist alert history and display native Windows notifications.
    # Write a durable diagnostic entry without allowing logging failure to stop monitoring.
    function Write-CriticalEventAlertLog {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [ValidateSet('Information', 'Warning', 'Error')]
            [string]$Level = 'Information',

            [Parameter(Mandatory)]
            [string]$Message
        )

        $entry = '{0} [{1}] {2}' -f `
            [datetime]::Now.ToString('o'), `
            $Level, `
            ($Message -replace '[\r\n]+', ' ')

        try {
            $logDirectory = Split-Path -Path $Path -Parent
            New-Item -ItemType Directory -Path $logDirectory -Force |
                Out-Null
            Add-Content -LiteralPath $Path -Value $entry -Encoding utf8
        }
        catch {
            Write-Verbose "Unable to write CriticalEventAlert log: $($_.Exception.Message)"
        }
    }

    function Write-CriticalEventAlertEventLog {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$Candidate,

            [Parameter(Mandatory)]
            [string]$Source
        )

        # Preserve every observed actionable event in the Application event log.
        $message = @(
            "Classification: $($Candidate.Classification)",
            "Provider: $($Candidate.ProviderName)",
            "Event ID: $($Candidate.EventId)",
            "Device: $($Candidate.Device)",
            "Severity: $($Candidate.Severity)",
            "Observed: $($Candidate.TimeCreated)",
            "Description: $($Candidate.Description)"
        ) -join [Environment]::NewLine

        Write-EventLog `
            -LogName Application `
            -Source $Source `
            -EventId 1001 `
            -EntryType Error `
            -Message $message
    }

    # Show an in-session toast without requiring a third-party PowerShell module.
    function Show-CriticalEventAlertToast {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [psobject]$Candidate,

            [ref]$FailureReason,

            [string]$LogPath,

            [string]$Title = 'Critical Windows reliability event',

            [string]$Reference
        )

        # Skip toast delivery when the task runs outside an interactive user session.
        if (-not [Environment]::UserInteractive) {
            if ($PSBoundParameters.ContainsKey('FailureReason')) {
                $FailureReason.Value = 'The PowerShell process is not running in an interactive user session.'
            }

            return $false
        }

        # Escape event text before inserting it into the toast XML document.
        $title = [Security.SecurityElement]::Escape($Title)
        $detail = [Security.SecurityElement]::Escape(
            ('{0}: {1}' -f $Candidate.Classification, $Candidate.Device)
        )
        if ($PSBoundParameters.ContainsKey('Reference')) {
            $referenceText = $Reference
        }
        else {
            $referenceText = 'Event Viewer - System / {0} / ID {1}' -f $Candidate.ProviderName, $Candidate.EventId
        }
        $reference = [Security.SecurityElement]::Escape($referenceText)
        $logAction = ''

        if ($LogPath) {
            $logUri = 'file:///' + ($LogPath -replace '\\', '/')
            $escapedLogUri = [Security.SecurityElement]::Escape($logUri)
            $logAction = @"
  <actions>
    <action content="Open alert log" activationType="protocol" arguments="$escapedLogUri" />
  </actions>
"@
        }

        $toastMarkup = @"
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>$title</text>
      <text>$detail</text>
      <text>$reference</text>
    </binding>
  </visual>
  $logAction
</toast>
"@

        # Use Windows PowerShell 5.1 as the WinRT bridge because PowerShell 7 does not
        # project the built-in Windows.Data and Windows.UI.Notifications types.
        try {
            $windowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

            if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
                throw "Windows PowerShell 5.1 was not found: $windowsPowerShellPath"
            }

            $encodedMarkup = [Convert]::ToBase64String(
                [Text.Encoding]::UTF8.GetBytes($toastMarkup)
            )
            $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
            $toastScript = @'
$ErrorActionPreference = 'Stop'
$toastMarkup = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String('__TOAST_MARKUP__')
)
$appId = '__APP_ID__'
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data, ContentType = WindowsRuntime]
$toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
$toastXml.LoadXml($toastMarkup)
$toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
'@
            $toastScript = $toastScript.Replace('__TOAST_MARKUP__', $encodedMarkup)
            $toastScript = $toastScript.Replace('__APP_ID__', $appId)
            $encodedCommand = [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($toastScript)
            )
            $processArguments = @(
                '-NoLogo'
                '-NoProfile'
                '-WindowStyle'
                'Hidden'
                '-ExecutionPolicy'
                'Bypass'
                '-EncodedCommand'
                $encodedCommand
            )
            $childOutput = & $windowsPowerShellPath @processArguments 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw (($childOutput | Out-String).Trim())
            }

            return $true
        }
        catch {
            if ($PSBoundParameters.ContainsKey('FailureReason')) {
                $FailureReason.Value = $_.Exception.Message
            }

            return $false
        }
    }
    #endregion

    #region DISK HEALTH
    # Functions that detect current unhealthy physical-disk status at sign-in.
    function Get-CriticalEventAlertDiskHealthCandidate {
        [CmdletBinding()]
        param()

        # Exit quietly when the Windows Storage cmdlets are unavailable on this device.
        if (-not (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
            return
        }

        # Alert only for physical disks that explicitly fail to report healthy status.
        foreach ($disk in Get-PhysicalDisk -ErrorAction Stop) {
            $operationalStatus = @($disk.OperationalStatus)
            $isOperational = $operationalStatus -contains 'OK' -or
                $operationalStatus -contains 'Healthy'
            $isHealthy = [string]$disk.HealthStatus -eq 'Healthy'

            if ($isOperational -and $isHealthy) {
                continue
            }

            [pscustomobject]@{
                Classification = 'Physical disk health status is not healthy'
                Description    = 'HealthStatus={0}; OperationalStatus={1}' -f `
                    $disk.HealthStatus, ($operationalStatus -join ', ')
                Device         = if ($disk.FriendlyName) { $disk.FriendlyName } else { $disk.UniqueId }
                EventId        = 0
                ProviderName   = 'WindowsStorageHealth'
                Severity       = 'Critical'
                TimeCreated    = Get-Date
                RecordId       = 0
            }
        }
    }
    #endregion
}

$RegistrationHelpers = {
    # Ensure event-log source registration occurs only from an elevated session.
    function Confirm-CriticalEventAlertAdministrator {
        # Stop before making partial changes when the installer is not elevated.
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Run Monitor-CriticalEventAlert.ps1 -Register from an elevated PowerShell session.'
        }
    }

    # Copy the maintained monitor implementation into its stable task execution location.
    function Initialize-CriticalEventAlertInstallation {
        # Create the application folder before copying task dependencies.
        New-Item -ItemType Directory -Path $InstallationPath -Force |
            Out-Null

        # Copy only the task payload files so the task does not depend on the repository path.
        foreach ($fileName in @('Monitor-CriticalEventAlert.ps1')) {
            $sourcePath = Join-Path $PSScriptRoot $fileName
            $destinationPath = Join-Path $InstallationPath $fileName

            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Required task payload file was not found: $sourcePath"
            }

            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }
        # Remove the retired module from prior installations so the runtime payload stays standalone.
        $legacyModulePath = Join-Path $InstallationPath 'CriticalEventAlert.psm1'
        if (Test-Path -LiteralPath $legacyModulePath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyModulePath -Force
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

    # Create the task folder and register the login status trigger.
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
            $folderName = $TaskPath.Trim('\')
            $null = $schedulerService.GetFolder('\').CreateFolder($folderName, $null)
        }

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
    <Description>Checks focused Windows reliability signals and reports status at user sign-in.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT30S</Delay>
    </LogonTrigger>
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
      <Arguments>-NoLogo -NoProfile -NonInteractive -WindowStyle Minimized -ExecutionPolicy Bypass -File &quot;$escapedMonitorPath&quot; -LoginCheck</Arguments>
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
