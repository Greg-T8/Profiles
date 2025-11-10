# -------------------------------------------------------------------------
# Program: profile-remote.ps1
# Description: Lightweight PowerShell profile for remote development sessions
#              (version without OneDrive dependencies)
# Context: Remote Development Setup (Microsoft Azure Administrator)
# Author: Greg Tate
# -------------------------------------------------------------------------

<#
    This is a lightweight PowerShell profile for remote development environments
    where OneDrive is not available.

    The profile script does the following:
    - Configures VI mode for PSReadline
    - Sets the prompt to display the current directory in a shortened format
    - Enables Posh-Git when using VSCode or when in a git repository
    - Loads custom functions if available

    See the following link for optimizing your PowerShell profile:
    - https://devblogs.microsoft.com/powershell/optimizing-your-profile/
#>

$ErrorActionPreference = 'Stop'

# Configure PSStyle for better output formatting
if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}

# Determine the directory where this profile is located
$ProfileDir = Split-Path -Parent $PSCommandPath

# Load prompt customizations
if (Test-Path -Path "$ProfileDir/prompt.ps1") {
    . "$ProfileDir/prompt.ps1"
}

# Load custom functions
if (Test-Path -Path "$ProfileDir/functions.ps1") {
    . "$ProfileDir/functions.ps1"
}

# Define useful aliases
Set-Alias -Name ll -Value Get-ChildItem -Force
Set-Alias -Name cfj -Value ConvertFrom-Json
Set-Alias -Name tf -Value terraform
Set-Alias -Name gim -Value Get-InstalledModule
Remove-Item Alias:dir -ErrorAction SilentlyContinue

# Configure PSReadLine for enhanced editing
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -PredictionViewStyle InlineView
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineKeyHandler -Chord Tab -Function TabCompleteNext
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Configure Right Arrow to accept the current prediction
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardWord

# Configure Ctrl+Right Arrow to accept the next word of the prediction
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function AcceptSuggestion

# Configure VI mode settings
if ((Get-PSReadLineOption).EditMode -eq 'Vi') {
    Set-PSReadLineOption -ViModeIndicator 'Cursor'
    $env:EDITOR = 'nvim'
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

    # Define VI mode change handler
    function OnViModeChange {
        if ($args[0] -eq 'Command') {
            # Set the cursor to a blinking block.
            Write-Host -NoNewline "`e[1 q"
        }
        else {
            # Set the cursor to a blinking line.
            Write-Host -NoNewline "`e[5 q"
        }
    }
    Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange

    # Set initial cursor to blinking line for Insert mode
    Write-Host -NoNewline "`e[5 q"
}
