# -------------------------------------------------------------------------
# Program: CriticalEventAlert.psm1
# Description: Shared detection, alerting, and state functions for Windows reliability monitoring
# Context: Personal PowerShell profile - Windows reliability monitoring
# Author: Greg Tate
# -------------------------------------------------------------------------

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
            'Ntfs' {
                if ($eventId -eq 55) {
                    $classification = 'NTFS file-system corruption detected'
                }
            }
            'Microsoft-Windows-WHEA-Logger' {
                $classification = switch ($eventId) {
                    1 { 'Fatal hardware error reported by WHEA' }
                    18 { 'Fatal hardware error reported by WHEA' }
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

        # Extract a stable device identity when the event description contains one.
        $device = Get-CriticalEventAlertDeviceIdentity -Description $description

        [pscustomobject]@{
            Classification = $classification
            Description    = $description
            Device          = $device
            EventId         = $eventId
            ProviderName    = $providerName
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

        [string]$LogPath
    )

    # Skip toast delivery when the task runs outside an interactive user session.
    if (-not [Environment]::UserInteractive) {
        if ($PSBoundParameters.ContainsKey('FailureReason')) {
            $FailureReason.Value = 'The PowerShell process is not running in an interactive user session.'
        }

        return $false
    }

    # Escape event text before inserting it into the toast XML document.
    $title = [Security.SecurityElement]::Escape('Critical Windows reliability event')
    $detail = [Security.SecurityElement]::Escape(
        ('{0}: {1}' -f $Candidate.Classification, $Candidate.Device)
    )
    $reference = [Security.SecurityElement]::Escape(
        ('Event Viewer - System / {0} / ID {1}' -f `
            $Candidate.ProviderName, $Candidate.EventId
        )
    )
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
            TimeCreated    = Get-Date
            RecordId       = 0
        }
    }
}
#endregion

Export-ModuleMember -Function `
    ConvertTo-CriticalEventAlertCandidate, `
    Get-CriticalEventAlertDiskHealthCandidate, `
    Get-CriticalEventAlertSignature, `
    Get-CriticalEventAlertState, `
    Save-CriticalEventAlertState, `
    Set-CriticalEventAlertSuppression, `
    Show-CriticalEventAlertToast, `
    Test-CriticalEventAlertSuppression, `
    Write-CriticalEventAlertLog, `
    Write-CriticalEventAlertEventLog
