<#
    This is my PowerShell profile script I use in the context of $Profile.CurrentUserAllHosts.

    The prompt function mimmics the behavior of the Oh-My-Posh prompt for PowerShell, but without requiring the
    additional overhead and loading time of Oh-My-Posh.

    The profile script does the following:
    - Configures VI mode for PSReadline
    - Sets the prompt to display the current directory in a shortened format
    - Enables Posh-Git when using VSCode or when in a git repository
    - Imports a configuration file for work-related settings

    See the following link for optimizing your PowerShell profile:
    - https://devblogs.microsoft.com/powershell/optimizing-your-profile/
#>

# ============================================================================
# INITIAL CONFIGURATION
# ============================================================================

$ErrorActionPreference = 'Stop'

# Set PSStyle formatting colors (PowerShell Core only)
if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}

# ============================================================================
# LOAD EXTERNAL SCRIPTS
# ============================================================================

# Determine the profile directory path
# For symlinked profiles, use the OneDrive path
# For remote/direct profiles, use the actual profile directory
$profileDir = if (Test-Path -Path "$env:OneDriveConsumer/Apps/Profiles/PowerShell/prompt.ps1") {
    "$env:OneDriveConsumer/Apps/Profiles/PowerShell"
} elseif (Test-Path -Path "$env:USERPROFILE/OneDrive/Apps/Profiles/PowerShell/prompt.ps1") {
    "$env:USERPROFILE/OneDrive/Apps/Profiles/PowerShell"
} else {
    # Fall back to the directory containing the profile script
    Split-Path -Parent $PROFILE.CurrentUserAllHosts
}

# Load custom prompt
if (Test-Path -Path "$profileDir/prompt.ps1") {
    try {
        . "$profileDir/prompt.ps1"
    }
    catch {
        Write-Host "ERROR loading prompt.ps1: $_" -ForegroundColor Red
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "At: $($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow
    }
}

# Load custom functions
if (Test-Path -Path "$profileDir/functions.ps1") {
    try {
        . "$profileDir/functions.ps1"
    }
    catch {
        Write-Host "ERROR loading functions.ps1: $_" -ForegroundColor Red
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Load work configuration
if (Test-Path -Path $env:OneDriveCommercial/Code/PowerShell/WorkConfig.psd1) {
    $Work = Import-PowerShellDataFile -Path $env:OneDriveCommercial/Code/PowerShell/WorkConfig.psd1

    # Sort work configuration keys
    $orderedAccounts = [ordered]@{}
    foreach ($key in $Work.Accounts.Keys | Sort-Object) {
        $orderedAccounts[$key] = $Work.Accounts[$key]
    }
    $Work.Accounts = $orderedAccounts

    $orderedTenantIds = [ordered]@{}
    foreach ($key in $Work.TenantIds.Keys | Sort-Object) {
        $orderedTenantIds[$key] = $Work.TenantIds[$key]
    }
    $Work.TenantIds = $orderedTenantIds

    $orderedSubscriptionIds = [ordered]@{}
    foreach ($key in $Work.SubscritpionIds.Keys | Sort-Object) {
        $orderedSubscriptionIds[$key] = $Work.SubscritpionIds[$key]
    }
    $Work.SubscritpionIds = $orderedSubscriptionIds
}

# ============================================================================
# ALIASES
# ============================================================================

Set-Alias -Name ll -Value Get-ChildItem -Force
Set-Alias -Name cfj -Value ConvertFrom-Json
Set-Alias -Name tf -Value terraform
Set-Alias -Name gim -Value Get-InstalledModule
Remove-Item Alias:dir -ErrorAction SilentlyContinue

# ============================================================================
# PSREADLINE CONFIGURATION
# ============================================================================

# Import PSReadLine module
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }

# Basic PSReadLine options
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -PredictionViewStyle InlineView

# Configure prediction source (version-specific)
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
}
elseif ($PSVersionTable.PSVersion.Major -ge 7) {
    Set-PSReadLineOption -PredictionSource History
}

# Tab completion key handlers
Set-PSReadLineKeyHandler -Chord Tab -Function TabCompleteNext
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Prediction navigation
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardWord
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function AcceptSuggestion

# Vi mode configuration
if ((Get-PSReadLineOption).EditMode -eq 'Vi') {
    Set-PSReadLineOption -ViModeIndicator 'Cursor'
    $env:EDITOR = 'nvim'

    # Vi mode key handlers for both Command and Insert modes
    foreach ($mode in 'Command', 'Insert') {
        Set-PSReadLineKeyHandler -Chord Ctrl+p -Function PreviousHistory -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+n -Function NextHistory -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Alt+b -Function BackwardWord -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Alt+f -Function ForwardWord -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+e -Function EndOfLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+a -Function BeginningOfLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+k -Function KillLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+u -Function BackwardKillInput -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+w -Function BackwardKillWord -ViMode $mode
    }

    # Custom cursor styles (PowerShell Core only - uses VT100 escape sequences)
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        function OnViModeChange {
            if ($args[0] -eq 'Command') {
                # Set the cursor to a blinking block
                Write-Host -NoNewline "`e[1 q"
            }
            else {
                # Set the cursor to a blinking line
                Write-Host -NoNewline "`e[5 q"
            }
        }
        Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange

        # Set initial cursor to blinking line for Insert mode
        Write-Host -NoNewline "`e[5 q"
    }
}