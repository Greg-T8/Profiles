<#
.SYNOPSIS
    Updates WinGet packages with indexed logs for login automation.

.DESCRIPTION
    Runs WinGet upgrades using the Microsoft.WinGet.Client module and writes
    structured, date-indexed log files under a script-local logs\ folder.
    Each run receives a unique log file. After a successful update pass, the
    log is opened automatically. Old log files are pruned according to the
    configured retention policy.

.PARAMETER RetentionDays
    Number of days to retain indexed WinGet log files. Accepts 0 (delete all
    existing logs before the current run) through 3650. A value of -1 (the
    default) uses the retention period defined in $LogRetentionConfig (30 days).

.PARAMETER TestToast
    Displays a sample WinGet failure toast without running WinGet or changing
    the 24-hour failure-notification suppression state.

.PARAMETER Register
    Creates or updates the current-user logon task for WinGet updates.

.PARAMETER Unregister
    Removes only this maintenance task.

.PARAMETER PinWinGetClient
    Downgrades the WinGet utility and Microsoft.WinGet.Client module to 1.29.280,
    then pins both maintenance paths without updating other packages.

.PARAMETER UnpinWinGetClient
    Removes the WinGet utility pin and allows future PowerShell module
    maintenance to update Microsoft.WinGet.Client again.

.PARAMETER TaskPath
    Task Scheduler folder path used with -Register or -Unregister. Defaults to \Custom Tasks\.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -Register

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -Unregister

.EXAMPLE
    .\Invoke-WingetUpdates.ps1
    Runs WinGet updates using the default 30-day log retention policy.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -RetentionDays 7
    Runs WinGet updates and retains only logs from the past 7 days.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -RetentionDays 0
    Runs WinGet updates and deletes all existing logs before the run.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -TestToast
    Displays a sample failure toast without running WinGet.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -PinWinGetClient
    Downgrades and pins the WinGet utility and PowerShell client at 1.29.280.

.EXAMPLE
    .\Invoke-WingetUpdates.ps1 -UnpinWinGetClient
    Removes the temporary WinGet pins after a verified upstream fix.

.CONTEXT
    User login maintenance automation (Windows Task Scheduler)

.AUTHOR
    Greg Tate

.NOTES
    Program: Invoke-WingetUpdates.ps1
#>

[CmdletBinding(DefaultParameterSetName = 'Maintenance')]
param(
    [Parameter(ParameterSetName = 'Maintenance')]
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = -1,

    [Parameter(ParameterSetName = 'Maintenance')]
    [switch]$TestToast,

    [Parameter(Mandatory, ParameterSetName = 'PinWinGetClient')]
    [switch]$PinWinGetClient,

    [Parameter(Mandatory, ParameterSetName = 'UnpinWinGetClient')]
    [switch]$UnpinWinGetClient,

    [Parameter(Mandatory, ParameterSetName = 'Register')]
    [switch]$Register,

    [Parameter(Mandatory, ParameterSetName = 'Unregister')]
    [switch]$Unregister,

    [Parameter(ParameterSetName = 'Register')]
    [Parameter(ParameterSetName = 'Unregister')]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath = '\Custom Tasks\'
)

# Configure log retention for indexed update log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}
$WinGetToastStatePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GregTate\WinGetUpdateAlert\state.json'
$WinGetClientConfig = @{
    ModuleName      = 'Microsoft.WinGet.Client'
    PackageId       = 'Microsoft.AppInstaller'
    AppxPackageName = 'Microsoft.DesktopAppInstaller'
    RequiredVersion = '1.29.280'
    InstallerUrl    = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.280/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
    InstallerSha256 = '0809FA9F52E395D6E7DE692331DCE847AC991952675116BB4D8AAE2DDCC20946'
    PinStatePath    = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GregTate\WinGetClientPin\state.json'
}

# Capture input values for the Main orchestration block.
$ConfiguredRetentionDays = $RetentionDays
$RunToastTest = $TestToast.IsPresent
$SetWinGetClientPin = $PinWinGetClient.IsPresent
$RemoveWinGetClientPin = $UnpinWinGetClient.IsPresent

# Task identity and parameters used only when registering or unregistering this maintenance task.
$TaskName = 'Update WinGet Apps At Logon'
$InvokeScriptName = 'Invoke-WingetUpdates.ps1'
$TaskArguments = ''
$RegisterTask = $Register.IsPresent
$UnregisterTask = $Unregister.IsPresent
$Main = {
    . $Helpers

    # Route task lifecycle requests away from the normal WinGet update flow.
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

    $logContext = New-UpdateLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $ConfiguredRetentionDays

    # Apply an explicit pin or recovery request without updating unrelated packages.
    if ($SetWinGetClientPin) {
        Set-WinGetClientPin -WinGetLogPath $logContext.WinGetLogPath
        return
    }

    if ($RemoveWinGetClientPin) {
        Remove-WinGetClientPin -WinGetLogPath $logContext.WinGetLogPath
        return
    }

    # Run a delivery-only sample when requested; normal invocations continue to update packages.
    if ($RunToastTest) {
        Invoke-WinGetToastTest -WinGetLogPath $logContext.WinGetLogPath
    }
    else {
        $wingetChanged = Invoke-WinGetUpdate -WinGetLogPath $logContext.WinGetLogPath
        Open-UpdateLog -WinGetLogPath $logContext.WinGetLogPath -WingetChanged:$wingetChanged
    }
}

$Helpers = {
    function New-UpdateLogContext {
        <#
        .SYNOPSIS
            Creates a dated, indexed log-file context for a WinGet update run.

        .DESCRIPTION
            Ensures the script-local logs\ directory exists, applies the log
            retention policy, then generates a unique log file path using a
            yyyy-MM-dd-NNN naming scheme where NNN increments per run per day.

        .PARAMETER LogRetentionConfig
            Hashtable with Enabled (bool) and RetentionDays (int) keys that
            control whether old log files are pruned and how old they must be.

        .PARAMETER RetentionDaysOverride
            When >= 0, overrides the RetentionDays value from LogRetentionConfig.
            Defaults to -1 (use LogRetentionConfig.RetentionDays).

        .OUTPUTS
            PSCustomObject with LogDirectory and WinGetLogPath properties.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        # Create and return update log path under the shared AppData log folder used by Invoke-PowerShellModuleUpdates.
        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            if ($PSCmdlet.ShouldProcess($logDirectory, 'Create log directory')) {
                New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
            }
        }

        # Apply retention policy before determining the next same-day index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) { $RetentionDaysOverride } else { [int]$LogRetentionConfig.RetentionDays }
            if ($effectiveRetentionDays -gt 0) {
                Remove-OldUpdateLog -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
            }
        }

        # Prefix log file names with the run date.
        $datePrefix = Get-Date -Format 'yyyy-MM-dd'

        # Derive next same-day index so each run gets a unique log.
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-WinGetUpdates.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-WinGetUpdates$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        # Return log file context.
        [PSCustomObject]@{
            LogDirectory  = $logDirectory
            WinGetLogPath = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-WinGetUpdates.log"
        }
    }

    function Remove-OldUpdateLog {
        <#
        .SYNOPSIS
            Removes indexed WinGet log files older than the retention threshold.

        .DESCRIPTION
            Scans LogDirectory for files matching the yyyy-MM-dd-NNN-WinGetUpdates.log
            pattern and deletes any whose LastWriteTime predates the computed cutoff.

        .PARAMETER LogDirectory
            Full path to the directory that contains the indexed log files.

        .PARAMETER RetentionDays
            Age threshold in days. Log files older than this value are deleted.
            Must be between 1 and 3650.
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        # Remove indexed winget log files older than the configured retention period.
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        $logsToRemove = Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-WinGetUpdates\.log$' -and
                $_.LastWriteTime -lt $cutoff
            }

        foreach ($logFile in $logsToRemove) {
            if ($PSCmdlet.ShouldProcess($logFile.FullName, 'Remove old WinGet log')) {
                Remove-Item -Path $logFile.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Show an in-session toast without requiring a third-party PowerShell module.
    function Show-WinGetFailureNotification {
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

    # Display a WinGet failure toast and suppress repeats for 24 hours after successful delivery.
    function Show-WinGetFailureToast {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$FailureSummary,

            [Parameter(Mandatory)]
            [string]$WinGetLogPath,

            [switch]$Force
        )

        # Suppress repeated failure notifications while the prior alert is less than 24 hours old.
        if (-not $Force -and (Test-Path -LiteralPath $WinGetToastStatePath -PathType Leaf)) {
            try {
                $toastState = Get-Content -LiteralPath $WinGetToastStatePath -Raw | ConvertFrom-Json -ErrorAction Stop
                $lastToastUtc = [datetime]::new(
                    [long]$toastState.LastFailureToastUtcTicks,
                    [DateTimeKind]::Utc
                )

                $hoursSinceLastToast = ([datetime]::UtcNow - $lastToastUtc).TotalHours

                # Suppress only timestamps within the cooldown window, not future clock values.
                if ($hoursSinceLastToast -ge 0 -and $hoursSinceLastToast -lt 24) {
                    "WinGet failure toast suppressed; previous toast was displayed at $($lastToastUtc.ToString('o'))." | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    return $false
                }
            }
            catch {
                "WinGet failure toast suppression state could not be read; notification will be attempted. Reason=$($_.Exception.Message)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
            }
        }

        # Keep long exception text out of the toast while preserving the complete error in the run log.
        if ($FailureSummary.Length -gt 180) {
            $FailureSummary = $FailureSummary.Substring(0, 177) + '...'
        }

        # Use the self-contained toast transport with WinGet-specific title and repair guidance.
        try {
            $candidate = [pscustomobject]@{
                Classification = 'WinGet update failed'
                Device         = $FailureSummary
            }
            $failureReason = $null
            $toastParameters = @{
                Candidate     = $candidate
                FailureReason = [ref]$failureReason
                LogPath       = $WinGetLogPath
                Title         = 'WinGet update needs attention'
                Reference     = 'Suggested repair: Repair-WinGetPackageManager -Force -Latest'
            }
            $toastShown = Show-WinGetFailureNotification @toastParameters

            if (-not $toastShown) {
                "WinGet failure toast was not displayed. Reason=$failureReason" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return $false
            }
        }
        catch {
            "WinGet failure toast delivery failed. Reason=$($_.Exception.Message)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
            return $false
        }

        # Persist the cooldown only after Windows reports that the toast was displayed.
        if (-not $Force) {
            try {
                $stateDirectory = Split-Path -Path $WinGetToastStatePath -Parent
                if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
                    New-Item -Path $stateDirectory -ItemType Directory -Force | Out-Null
                }

                @{
                    LastFailureToastUtcTicks = [datetime]::UtcNow.Ticks
                } | ConvertTo-Json | Set-Content -LiteralPath $WinGetToastStatePath -Encoding UTF8
            }
            catch {
                "WinGet failure toast was displayed, but suppression state could not be saved. Reason=$($_.Exception.Message)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
            }
        }

        'WinGet failure toast displayed.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        return $true
    }

    # Display a sample WinGet failure toast without invoking WinGet or changing suppression state.
    function Invoke-WinGetToastTest {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        'WinGet toast test started; WinGet package operations were skipped.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        $toastParameters = @{
            FailureSummary = 'Manual toast test; no WinGet operation was attempted.'
            WinGetLogPath  = $WinGetLogPath
            Force          = $true
        }
        $toastShown = Show-WinGetFailureToast @toastParameters

        # Fail explicit toast tests when Windows could not display the notification.
        if (-not $toastShown) {
            throw 'The WinGet toast test did not display a notification.'
        }

        'WinGet toast test completed.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
    }

    function Get-WinGetClientPinState {
        # Read the durable recovery state; an absent state defaults to the temporary safety pin.
        $defaultState = [pscustomobject]@{
            PinEnabled      = $true
            RequiredVersion = $WinGetClientConfig.RequiredVersion
        }

        if (-not (Test-Path -LiteralPath $WinGetClientConfig.PinStatePath -PathType Leaf)) {
            return $defaultState
        }

        try {
            $state = Get-Content -LiteralPath $WinGetClientConfig.PinStatePath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop

            if ($null -eq $state.PSObject.Properties['PinEnabled']) {
                throw 'The PinEnabled property is missing.'
            }

            return $state
        }
        catch {
            throw "WinGet client pin state could not be read: $($_.Exception.Message)"
        }
    }

    function Set-WinGetClientPinState {
        param(
            [Parameter(Mandatory)]
            [bool]$PinEnabled
        )

        # Persist the selected pin mode so the separate module maintenance task honors recovery.
        $stateDirectory = Split-Path -Path $WinGetClientConfig.PinStatePath -Parent
        if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
            New-Item -Path $stateDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        [pscustomobject]@{
            PinEnabled      = $PinEnabled
            RequiredVersion = $WinGetClientConfig.RequiredVersion
            UpdatedAtUtc    = [datetime]::UtcNow.ToString('o')
        } |
            ConvertTo-Json |
            Set-Content -LiteralPath $WinGetClientConfig.PinStatePath -Encoding UTF8 -ErrorAction Stop
    }

    function Set-MaintenanceClientPinCatalogEntry {
        param(
            [Parameter(Mandatory)]
            [bool]$PinEnabled
        )

        # Keep the generic pin catalog aligned so the separate module updater honors this client pin.
        $catalogPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GregTate\MaintenancePins\pins.json'
        $catalogDirectory = Split-Path -Path $catalogPath -Parent
        if (-not (Test-Path -LiteralPath $catalogDirectory -PathType Container)) {
            New-Item -Path $catalogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
            $catalog = Get-Content -LiteralPath $catalogPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
        }
        else {
            $catalog = [pscustomobject]@{
                ModulePins  = @()
                PackagePins = @()
            }
        }

        $catalog.ModulePins = @($catalog.ModulePins |
                Where-Object { $_.Name -ne $WinGetClientConfig.ModuleName })
        $catalog.PackagePins = @($catalog.PackagePins |
                Where-Object { $_.Id -ne $WinGetClientConfig.PackageId })
        if ($PinEnabled) {
            $catalog.ModulePins += [pscustomobject]@{
                Name    = $WinGetClientConfig.ModuleName
                Version = $WinGetClientConfig.RequiredVersion
            }
            $catalog.PackagePins += [pscustomobject]@{
                Id      = $WinGetClientConfig.PackageId
                Version = '{0}.0' -f $WinGetClientConfig.RequiredVersion
                Source  = 'winget'
            }
        }

        [pscustomobject]@{
            ModulePins   = @($catalog.ModulePins)
            PackagePins  = @($catalog.PackagePins)
            UpdatedAtUtc = [datetime]::UtcNow.ToString('o')
        } |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $catalogPath -Encoding UTF8 -ErrorAction Stop
    }

    function Get-InstalledWinGetUtility {
        # Return the current App Installer package, which supplies winget.exe.
        return Get-AppxPackage -Name $WinGetClientConfig.AppxPackageName -ErrorAction SilentlyContinue |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
    }

    function Confirm-WinGetUtilityVersion {
        # Verify that App Installer resolves to the required 1.29.280 servicing version.
        $package = Get-InstalledWinGetUtility
        $expectedVersion = '{0}.0' -f $WinGetClientConfig.RequiredVersion

        if (-not $package -or "$($package.Version)" -ne $expectedVersion) {
            $actualVersion = if ($package) { "$($package.Version)" } else { 'not installed' }
            throw "WinGet utility version is '$actualVersion'; required version is '$expectedVersion'."
        }
    }

    function Install-RequiredWinGetUtility {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Install the source-verified App Installer release only when the current package differs.
        $package = Get-InstalledWinGetUtility
        $expectedVersion = '{0}.0' -f $WinGetClientConfig.RequiredVersion
        if ($package -and "$($package.Version)" -eq $expectedVersion) {
            "WinGet utility already uses required version $expectedVersion." |
                Tee-Object -FilePath $WinGetLogPath -Append |
                Out-Null
            return
        }

        $wingetCommand = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            throw 'winget.exe was not found; the App Installer package cannot be downgraded automatically.'
        }

        "Installing WinGet utility version $expectedVersion." |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
        $wingetArguments = @(
            'install'
            '--id'
            $WinGetClientConfig.PackageId
            '--version'
            $expectedVersion
            '--exact'
            '--source'
            'winget'
            '--force'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
        )
        $installOutput = & $wingetCommand.Source @wingetArguments 2>&1
        $installOutput |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null

        if ($LASTEXITCODE -ne 0) {
            "WinGet utility installation returned exit code $LASTEXITCODE; using the verified bundle fallback." |
                Tee-Object -FilePath $WinGetLogPath -Append |
                Out-Null
            Install-RequiredWinGetUtilityFromBundle -WinGetLogPath $WinGetLogPath
        }

        Confirm-WinGetUtilityVersion
    }

    function Install-RequiredWinGetUtilityFromBundle {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Stage and hash the official release before replacing the installed App Installer package.
        $bundlePath = Join-Path -Path $env:TEMP -ChildPath 'Microsoft.DesktopAppInstaller_1.29.280.0.msixbundle'
        Invoke-WebRequest `
            -Uri $WinGetClientConfig.InstallerUrl `
            -OutFile $bundlePath `
            -ErrorAction Stop
        $actualHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -ne $WinGetClientConfig.InstallerSha256) {
            throw "Downloaded App Installer bundle hash did not match the WinGet manifest. Actual=$actualHash"
        }

        $currentPackage = Get-InstalledWinGetUtility
        $currentVersion = if ($currentPackage) { "$($currentPackage.Version)" } else { 'not installed' }
        "Replacing App Installer $currentVersion with the verified 1.29.280.0 bundle." |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
        Add-AppxPackage `
            -Path $bundlePath `
            -ForceTargetApplicationShutdown `
            -ForceUpdateFromAnyVersion `
            -ErrorAction Stop
    }

    function Install-RequiredWinGetClientModule {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Install the required client release into the CurrentUser module scope used by maintenance.
        $requiredVersion = [version]$WinGetClientConfig.RequiredVersion
        $installedModule = Get-Module -ListAvailable -Name $WinGetClientConfig.ModuleName -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -eq $requiredVersion } |
            Select-Object -First 1

        if (-not $installedModule) {
            "Installing PowerShell module $($WinGetClientConfig.ModuleName) $requiredVersion." |
                Tee-Object -FilePath $WinGetLogPath -Append |
                Out-Null
            Install-Module `
                -Name $WinGetClientConfig.ModuleName `
                -RequiredVersion $WinGetClientConfig.RequiredVersion `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop
        }

        $userModuleRoots = @(
            (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules'),
            (Join-Path -Path $HOME -ChildPath 'Documents\WindowsPowerShell\Modules')
        )
        $unwantedModules = Get-Module -ListAvailable -Name $WinGetClientConfig.ModuleName -ErrorAction SilentlyContinue |
            Where-Object {
                $module = $_
                $moduleBase = "$($module.ModuleBase)"
                $isCurrentUserModule = $false
                foreach ($userModuleRoot in $userModuleRoots) {
                    if ($moduleBase -like "$userModuleRoot*") {
                        $isCurrentUserModule = $true
                        break
                    }
                }

                $module.Version -ne $requiredVersion -and $isCurrentUserModule
            } |
            Sort-Object -Property Version -Descending

        # Remove other CurrentUser client releases so implicit module discovery cannot select the regression.
        foreach ($module in $unwantedModules) {
            "Removing PowerShell module $($WinGetClientConfig.ModuleName) $($module.Version)." |
                Tee-Object -FilePath $WinGetLogPath -Append |
                Out-Null
            Uninstall-Module `
                -Name $WinGetClientConfig.ModuleName `
                -RequiredVersion $module.Version `
                -Force `
                -ErrorAction Stop
        }

        $verifiedModule = Get-Module -ListAvailable -Name $WinGetClientConfig.ModuleName -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -eq $requiredVersion } |
            Select-Object -First 1
        if (-not $verifiedModule) {
            throw "PowerShell module $($WinGetClientConfig.ModuleName) $requiredVersion was not found after installation."
        }
    }

    function Add-WinGetUtilityPin {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Replace any prior App Installer pin with the exact required servicing version.
        $wingetCommand = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            throw 'winget.exe was not found; the App Installer package cannot be pinned.'
        }

        $removeArguments = @(
            'pin'
            'remove'
            '--id'
            $WinGetClientConfig.PackageId
            '--exact'
            '--disable-interactivity'
        )
        $null = & $wingetCommand.Source @removeArguments 2>$null

        $pinVersion = '{0}.0' -f $WinGetClientConfig.RequiredVersion
        $addArguments = @(
            'pin'
            'add'
            '--id'
            $WinGetClientConfig.PackageId
            '--version'
            $pinVersion
            '--exact'
            '--source'
            'winget'
            '--accept-source-agreements'
            '--disable-interactivity'
            '--force'
        )
        $pinOutput = & $wingetCommand.Source @addArguments 2>&1
        $pinOutput |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet utility pinning failed with exit code $LASTEXITCODE."
        }

        $pinListOutput = & $wingetCommand.Source pin list --disable-interactivity 2>&1
        $pinIsPresent = @($pinListOutput | Where-Object {
                "$_" -match [regex]::Escape($WinGetClientConfig.PackageId) -and
                "$_" -match [regex]::Escape($pinVersion)
            }).Count -gt 0
        if (-not $pinIsPresent) {
            throw "WinGet utility pin for $($WinGetClientConfig.PackageId) $pinVersion was not found after creation."
        }
    }

    function Set-WinGetClientPin {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Establish both client-version controls before package maintenance starts.
        "Applying WinGet client pin $($WinGetClientConfig.RequiredVersion)." |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
        Install-RequiredWinGetUtility -WinGetLogPath $WinGetLogPath
        Install-RequiredWinGetClientModule -WinGetLogPath $WinGetLogPath
        Add-WinGetUtilityPin -WinGetLogPath $WinGetLogPath
        Set-WinGetClientPinState -PinEnabled $true
        Set-MaintenanceClientPinCatalogEntry -PinEnabled $true
        "WinGet client pin $($WinGetClientConfig.RequiredVersion) is active." |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
    }

    function Remove-WinGetClientPin {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Remove the temporary App Installer pin and allow module maintenance to resume normal updates.
        $wingetCommand = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if (-not $wingetCommand) {
            throw 'winget.exe was not found; the App Installer pin cannot be removed.'
        }

        $removeOutput = & $wingetCommand.Source pin remove --id $WinGetClientConfig.PackageId --exact --disable-interactivity 2>&1
        $removeOutput |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
        if ($LASTEXITCODE -ne 0 -and "$removeOutput" -notmatch 'No pins found') {
            throw "WinGet utility unpinning failed with exit code $LASTEXITCODE."
        }

        Set-WinGetClientPinState -PinEnabled $false
        Set-MaintenanceClientPinCatalogEntry -PinEnabled $false
        'WinGet client pins are removed; the next module maintenance run may update Microsoft.WinGet.Client.' |
            Tee-Object -FilePath $WinGetLogPath -Append |
            Out-Null
    }

    function Invoke-WinGetUpdate {
        <#
        .SYNOPSIS
            Runs WinGet package upgrades via Microsoft.WinGet.Client and logs results.

        .DESCRIPTION
            Imports the Microsoft.WinGet.Client module, discovers all installed
            packages that have updates available, applies each upgrade silently,
            and records structured output to the provided log file. Returns $true
            when at least one package was successfully updated, $false otherwise.

        .PARAMETER WinGetLogPath
            Full path to the log file where run output should be appended.

        .OUTPUTS
            System.Boolean - $true if one or more packages were updated; otherwise $false.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Write a run header for this WinGet update pass.
        $runHeader = "`n===== WinGet update started: $(Get-Date -Format s) ====="
        $runHeader | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        'Scope: All installed WinGet packages' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

        # Enforce the temporary client pin before attempting any package discovery or update.
            $originalProgressPreference = $ProgressPreference
            $successfulUpdates = 0
            $installedPackageCount = 0
            $updatedPackageLines = [System.Collections.Generic.List[string]]::new()
            $pinnedPackageLines = [System.Collections.Generic.List[string]]::new()
            $skippedPackageLines = [System.Collections.Generic.List[string]]::new()
            try {
                # Suppress progress records so logs remain text/object focused.
                $ProgressPreference = 'SilentlyContinue'

                # Apply the requested pin unless the explicit recovery mode has disabled it.
                $pinState = Get-WinGetClientPinState
                $importParameters = @{
                    Name        = $WinGetClientConfig.ModuleName
                    ErrorAction = 'Stop'
                }
                if ($pinState.PinEnabled) {
                    Set-WinGetClientPin -WinGetLogPath $WinGetLogPath
                    $importParameters.RequiredVersion = $WinGetClientConfig.RequiredVersion
                }

                # Load the pinned client when active, then verify the package manager is ready.
                Import-Module @importParameters
                Assert-WinGetPackageManager -ErrorAction Stop | Out-Null

                # Discover all installed packages and compute pending updates from that set.
                $installedPackages = @(Get-WinGetPackage -ErrorAction Stop)
                $installedPackageCount = $installedPackages.Count
                $availableUpdates = @($installedPackages | Where-Object { $_.IsUpdateAvailable })

                # Read pinned package metadata from winget CLI output.
                if (Get-Command -Name winget -ErrorAction SilentlyContinue) {
                    $pinListOutput = @(winget pin list --disable-interactivity 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $pinListOutput) {
                        $pinListOutput | ForEach-Object {
                            $line = "$($_)".Trim()
                            if (-not $line) {
                                return
                            }

                            if ($line -match '^Name\s+Id\s+Version\s+Source\s+Pin type$') {
                                return
                            }

                            if ($line -match '^-{3,}$') {
                                return
                            }

                            $columns = @($line -split '\s{2,}')
                            if ($columns.Count -ge 2) {
                                $pinnedPackageLines.Add("  - $($columns[0]) [$($columns[1])] (pinned)")
                            }
                        }
                    }
                }

                # Record up-to-date packages in a compact, line-oriented format.
                $installedPackages |
                    Where-Object { -not $_.IsUpdateAvailable } |
                    ForEach-Object {
                        $skippedPackageLines.Add("  - $($_.Name) [$($_.Id)] (up-to-date)")
                    }

                # Exit cleanly when there are no upgrades to apply.
                if (-not $availableUpdates) {
                    "Summary: $installedPackageCount packages checked, 0 updated, $($skippedPackageLines.Count) skipped." | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    return $false
                }

                # Apply upgrades one package at a time to preserve per-package status logging.
                foreach ($package in $availableUpdates) {
                    try {
                        $package | Update-WinGetPackage -Mode Silent -Confirm:$false -ErrorAction Stop | Out-Null
                        $successfulUpdates += 1

                        if ($package.AvailableVersions -and $package.AvailableVersions.Count -gt 0) {
                            $availableVersion = $package.AvailableVersions[0]
                        }
                        else {
                            $availableVersion = '?'
                        }

                        $updatedPackageLines.Add("  - $($package.Name) [$($package.Id)] ($($package.InstalledVersion) -> $availableVersion)")
                    }
                    catch {
                        # Continue processing remaining packages while capturing update failures.
                        $skippedPackageLines.Add("  - $($package.Name) [$($package.Id)] (error: $($_.Exception.Message))")
                    }
                }

                # Write compact summary and grouped package result lines.
                "Summary: $installedPackageCount packages checked, $successfulUpdates updated, $($skippedPackageLines.Count) skipped." | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

                if ($updatedPackageLines.Count -gt 0) {
                    'Updated packages:' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                    $updatedPackageLines | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

                "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return ($successfulUpdates -gt 0)
            }
            catch {
                $failureSummary = $_.Exception.Message
                "WinGet module update failed: $failureSummary" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                Show-WinGetFailureToast -FailureSummary $failureSummary -WinGetLogPath $WinGetLogPath | Out-Null
                "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return $false
            }
            finally {
                $ProgressPreference = $originalProgressPreference
            }

        $failureSummary = 'Microsoft.WinGet.Client module was not found.'
        $failureSummary | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        Show-WinGetFailureToast -FailureSummary $failureSummary -WinGetLogPath $WinGetLogPath | Out-Null
        "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        return $false
    }

    function Open-UpdateLog {
        <#
        .SYNOPSIS
            Opens the WinGet log file when package updates were applied.

        .DESCRIPTION
            Invokes the default handler for WinGetLogPath only when WingetChanged
            is set and the log file exists, so the log is surfaced after a run
            that produced actual changes.

        .PARAMETER WinGetLogPath
            Full path to the WinGet log file to open.

        .PARAMETER WingetChanged
            Switch indicating that at least one WinGet package was updated during
            the current run. The log is opened only when this switch is present.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath,

            [switch]$WingetChanged
        )

        # Launch WinGet log only when package updates were actually applied.
        if ($WingetChanged -and (Test-Path -Path $WinGetLogPath)) {
            Invoke-Item -Path $WinGetLogPath
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


try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
