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

# Debug flag for troubleshooting prompt issues
$script:DebugPrompt = $false

# Set PSStyle formatting colors (PowerShell Core only)
if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}

# ============================================================================
# PROMPT HELPER FUNCTIONS
# ============================================================================

function Test-GitDirectory {
    # Check if current directory is a git repository
    $gitCommand = Get-Command -Name git.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($gitCommand) {
        try {
            $gitStatus = git status 2>&1
            if (-not ($gitStatus -match 'fatal: not a git repository')) {
                return $true
            }
        }
        catch {
            # Ignore errors from git command
        }
    }
    return $false
}

function Get-PromptPath {
    try {
        # Get shortened path for prompt display
        $location = "$(Get-Location)"

        # Detect platform - check for IsWindows variable (PowerShell Core) or assume Windows for older versions
        # Use Get-Variable to avoid assignment conflict with read-only variable
        $onWindows = if ($PSVersionTable.PSVersion.Major -ge 6) {
            (Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
        }
        else {
            $true
        }

        # Set path separator based on platform
        $sep = if ($onWindows) { '\' } else { '/' }

        # Remove trailing slash except for root paths
        if ($onWindows) {
            if ($location.EndsWith('\') -and -not $location.EndsWith(':\')) {
                $location = $location.TrimEnd('\\')
            }
        }
        else {
            if ($location.EndsWith('/') -and $location.Length -gt 1) {
                $location = $location.TrimEnd('/')
            }
        }

        # Get user home directory
        $userProfilePath = if ($onWindows) { $env:USERPROFILE } else { $env:HOME }

        if ($userProfilePath -and $location.StartsWith($userProfilePath)) {
            if ($location -eq $userProfilePath) {
                $promptPath = '~'
            }
            else {
                # Extract the relative path from user profile
                $relativelocation = $location.Substring($userProfilePath.Length)

                # Count folder depth (number of separators)
                $matches = [regex]::Matches($relativelocation, [regex]::Escape($sep))
                $folderDepth = $matches.Count

                # Check if the displayed path would be too long
                $displayPath = '~' + $relativelocation

                if ($displayPath.Length -le 50) {
                    $promptPath = $displayPath
                }
                elseif ($folderDepth -le 4) {
                    # Not enough folders to shorten, show full path
                    $promptPath = $displayPath
                }
                else {
                    # Path is long and has enough folders, shorten by keeping first 3 and last 2
                    $leftPath   = $relativelocation.Substring(0, $matches[2].Index)
                    $rightPath  = $relativelocation.Substring($matches[$matches.Count - 2].Index)
                    $promptPath = "~$leftPath$sep...$rightPath"
                }
            }
        }
        else {
            # Build prompt path for locations outside of user profile
            $matches = [regex]::Matches($location, [regex]::Escape($sep))
            switch ($matches.count) {
                { $_ -ge 1 -and $_ -le 4 } {
                    $promptPath = $location
                    break
                }
                default {
                    $leftPath   = $location.Substring(0, $matches[2].Index)
                    $rightPath  = $location.Substring($matches[$_ - 2].Index)
                    $promptPath = "$leftPath$sep...$rightPath"
                }
            }
        }
        return $promptPath
    }
    catch {
        # On error, fall back to current location
        if ($script:DebugPrompt) {
            Write-Host "ERROR in Get-PromptPath: $_" -ForegroundColor Red
            Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
        }
        return "$(Get-Location)"
    }
}

function Initialize-PoshGit {
    # Initialize Posh-Git module and settings
    # Only loads in PowerShell Core when in a Git directory

    if ($PSVersionTable.PSEdition -ne 'Core') {
        return $false
    }

    if (-not (Test-GitDirectory)) {
        return $false
    }

    try {
        Import-Module Posh-Git -ErrorAction Stop

        # Configure Posh-Git settings
        $GitPromptSettings.DefaultPromptPath            = ''
        $GitPromptSettings.DefaultPromptSuffix          = ''
        $GitPromptSettings.DefaultPromptDebug           = ''
        $GitPromptSettings.EnableStashStatus            = $true
        $GitPromptSettings.BeforeStatus.ForegroundColor = 0x00B3E2      # Cyan RGB(0, 179, 226)
        $GitPromptSettings.AfterStatus.ForegroundColor  = 0x00B3E2
        $GitPromptSettings.WorkingColor.ForegroundColor = 0x8A0ACC      # Purple RGB(138, 10, 204)
        $StashColor                                     = 0xAFB178      # Sage RGB(175, 177, 120)
        $GitPromptSettings.StashColor.ForegroundColor   = $StashColor
        $GitPromptSettings.BeforeStash.ForegroundColor  = $StashColor
        $GitPromptSettings.AfterStash.ForegroundColor   = $StashColor

        return $true
    }
    catch {
        # Posh-Git not available, continue without it
        return $false
    }
}

# ============================================================================
# PROMPT FUNCTION
# ============================================================================

function prompt {
    # Initialize Posh-Git if in PowerShell Core and in a Git directory
    $usingPoshGit = $false
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if (-not (Get-Module -Name Posh-Git)) {
            $usingPoshGit = Initialize-PoshGit
        }
        else {
            $usingPoshGit = $true
        }
    }

    # Use different prompt styles based on PowerShell edition
    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell Core with ANSI escape codes
        $ESC = [char]0x1b                                            # ESC character for ANSI sequences
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        $([char]0x256d) +                                            # '╭' Box Drawings Light Arc Down and Right
        $([char]0x2500) +                                            # '─' Box Drawings Light Horizontal
        '( ' +                                                       # Opening parenthesis and space
        "$ESC[3m" +                                                  # Start italic mode
        "$ESC[2m" +                                                  # Start dim/faint mode
        $(Get-PromptPath) +                                          # Display shortened path
        "$ESC[22m" +                                                 # Reset dim/faint mode
        "$(if ($usingPoshGit) { "$(& $GitPromptScriptBlock)" })" +  # Git status if in git repo
        "$ESC[23m" +                                                 # Reset italic mode
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        $([char]0x2570) +                                            # '╰' Box Drawings Light Arc Up and Right
        $([char]0x2574) +                                            # '╴' Box Drawings Light Left
        "$ESC[0m" +                                                  # Reset all ANSI formatting
        $(if (Test-Path variable:/PSDebugContext) { '[DBG]: ' } else { '' }) +  # Debug indicator
        '> '                                                         # Prompt character
    }
    else {
        # Windows PowerShell 5.1 - Cannot use ANSI, build prompt string
        "`n" +                                                       # New line
        "$([char]0x256d)" +                                          # '╭' Box Drawings Light Arc Down and Right
        "$([char]0x2500)" +                                          # '─' Box Drawings Light Horizontal
        '( ' +                                                       # Opening parenthesis and space
        "$(Get-PromptPath)" +                                        # Display shortened path
        "`n" +                                                       # New line
        "$([char]0x2570)" +                                          # '╰' Box Drawings Light Arc Up and Right
        "$([char]0x2574)" +                                          # '╴' Box Drawings Light Left with space
        $(if (Test-Path variable:/PSDebugContext) { '[DBG]: ' } else { '' }) +  # Debug indicator
        '> '                                                         # Prompt character
    }
}

# ============================================================================
# LOAD EXTERNAL SCRIPTS
# ============================================================================

# Determine the profile directory path
# For symlinked profiles, use the OneDrive path
# For remote/direct profiles, use the actual profile directory
$profileDir = if (Test-Path -Path "$env:OneDriveConsumer/Apps/Profiles/PowerShell/functions.ps1") {
    "$env:OneDriveConsumer/Apps/Profiles/PowerShell"
}
elseif (Test-Path -Path "$env:USERPROFILE/OneDrive/Apps/Profiles/PowerShell/functions.ps1") {
    "$env:USERPROFILE/OneDrive/Apps/Profiles/PowerShell"
}
else {
    # Fall back to the directory containing the profile script
    Split-Path -Parent $PROFILE.CurrentUserAllHosts
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
Set-Alias -Name rr -Value Invoke-ReloadProfile
Remove-Item Alias:dir -ErrorAction SilentlyContinue

# ============================================================================
# RELOAD PROFILE FUNCTION
# ============================================================================

function Invoke-ReloadProfile {
    # Reload the PowerShell profile
    . $profile.currentUserAllHosts
}

# ============================================================================
# PSREADLINE CONFIGURATION
# ============================================================================

# Import PSReadLine module
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }

# Basic PSReadLine options
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -ContinuationPrompt ''

# PredictionViewStyle requires PSReadLine 2.1.0+ (PowerShell Core)
if ($PSVersionTable.PSEdition -eq 'Core') {
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
}

# Configure prediction source (edition-specific)
if ($PSVersionTable.PSEdition -eq 'Core') {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
}

# Tab completion key handlers
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
    param($key, $arg)
    # Insert spaces if only whitespace precedes cursor on current line, otherwise complete
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # Find the start of the current line (last newline before cursor, or beginning)
    $lastNewline = $line.LastIndexOf("`n", $cursor - 1)
    $lineStart = if ($lastNewline -ge 0) { $lastNewline + 1 } else { 0 }
    $textBeforeCursor = $line.Substring($lineStart, $cursor - $lineStart)

    if ($textBeforeCursor -notmatch '\S') {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('    ')
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
    }
}

# Accept menu selection with Tab (after menu is open, use arrows to navigate then Tab to accept)
Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine

# Prediction navigation (PowerShell Core with newer PSReadLine)
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardWord
if ($PSVersionTable.PSEdition -eq 'Core') {
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function AcceptSuggestion -ErrorAction SilentlyContinue
}

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
    if ($PSVersionTable.PSEdition -eq 'Core') {
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