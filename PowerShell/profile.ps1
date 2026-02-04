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

# Store the actual profile script path for reloading
$script:ProfilePath = $PSCommandPath

# Set PSStyle formatting colors (PowerShell Core only)
if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}

# ============================================================================
# PROMPT FUNCTION
# ============================================================================
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( ~/path/to/directory [git-status]
#   ╰╴>

function prompt {
    # Use different prompt styles based on PowerShell edition
    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell Core with ANSI escape codes
        $ESC = [char]0x1b                                            # ESC character for ANSI sequences
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        '╭─( ' +                                                     # Box drawing characters and opening parenthesis
        "$ESC[3m" +                                                  # Start italic mode
        "$ESC[2m" +                                                  # Start dim/faint mode
        $(Get-MyPromptPath) +                                        # Display shortened path
        "$ESC[22m" +                                                 # Reset dim/faint mode
        "$(if ($script:PoshGitLoaded) { "$(& $GitPromptScriptBlock)" })" +  # Git status if in git repo
        "$ESC[23m" +                                                 # Reset italic mode
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        '╰╴' +                                                       # Box drawing characters
        "$ESC[0m" +                                                  # Reset all ANSI formatting
        $(if (Test-Path variable:/PSDebugContext) { '[DBG]: ' } else { '' }) +  # Debug indicator
        '> '                                                         # Prompt character
    }
    else {
        # Windows PowerShell 5.1 - Cannot use ANSI, build prompt string
        "`n" +                                                       # New line
        '╭─( ' +                                                     # Box drawing characters and opening parenthesis
        "$(Get-MyPromptPath)" +                                      # Display shortened path
        "`n" +                                                       # New line
        '╰╴' +                                                       # Box drawing characters
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

# Load personal configuration
$personalConfigPath = "$env:OneDriveConsumer/Documents/PowerShell/Config/PersonalConfig.psd1"
if (Test-Path -Path $personalConfigPath) {
    $Personal = Import-PowerShellDataFile -Path $personalConfigPath
}

# Load work configuration
$workConfigPath = "$env:OneDriveCommercial/Code/PowerShell/Config/WorkConfig.psd1"
if (Test-Path -Path $workConfigPath) {
    $Work = Import-PowerShellDataFile -Path $workConfigPath
}

# ============================================================================
# ALIASES
# ============================================================================

Set-Alias -Name ll -Value Get-ChildItem -Force
Set-Alias -Name cfj -Value ConvertFrom-Json
Set-Alias -Name tf -Value terraform
Set-Alias -Name gim -Value Get-InstalledModule
Set-Alias -Name tnc -Value Test-NetConnection
Set-Alias -Name rdn -Value Resolve-DNSName
Remove-Item Alias:dir -ErrorAction SilentlyContinue

# Docker aliases
function DockerExec { docker exec -it @args }
function DockerImageList { docker image ls -a --no-trunc @args }
function DockerContainerList { docker container ls -a --no-trunc @args }
function RegCtlCmd { docker run --rm regclient/regctl @args }

Set-Alias -Name dex -Value DockerExec
Set-Alias -Name dil -Value DockerImageList
Set-Alias -Name dcl -Value DockerContainerList
Set-Alias -Name regctl -Value RegCtlCmd

# ============================================================================
# RELOAD PROFILE
# ============================================================================
# Note: Due to PowerShell scoping rules, profile reload cannot be wrapped in a
# function and have changes persist. You must dot-source the profile directly:
#   . $script:ProfilePath
# Or define an alias/function as a reminder, but you'll still need to manually
# dot-source for function definition changes to take effect.#

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

function Get-MyPromptPath {
    <#
    .SYNOPSIS
        Get shortened path for prompt display

    .DESCRIPTION
        Returns a shortened version of the current path for display in the prompt.
        Paths under the user profile are displayed with ~ prefix.
        Long paths are shortened by keeping the first 3 folders and last 2 folders.
        Works on both Windows and Linux systems.

    .NOTES
        Debug mode: Set $DebugPrompt = $true at the start of the function to see detailed path processing
    #>

    $DebugPrompt = $false

    # Detect OS and set path separator
    $onWindows = if ($PSVersionTable.PSEdition -eq 'Core') {
        (Get-Variable -Name 'IsWindows' -ValueOnly -ErrorAction SilentlyContinue) -ne $false
    }
    else {
        $true  # Windows PowerShell 5.1 is always Windows
    }
    $pathSep = if ($onWindows) { '\' } else { '/' }
    $pathSepRegex = if ($onWindows) { '\\' } else { '/' }

    # Get shortened path for prompt display
    $location = "$(Get-Location)"

    if ($DebugPrompt) {
        Write-Host "[DEBUG] location: $location" -ForegroundColor Magenta
        Write-Host "[DEBUG] onWindows: $onWindows" -ForegroundColor Magenta
        Write-Host "[DEBUG] pathSep: $pathSep" -ForegroundColor Magenta
    }

    # Remove trailing slash except for root paths (e.g., 'C:\' or '/')
    $isRootPath = if ($onWindows) {
        $location.EndsWith(':\')
    }
    else {
        $location -eq '/'
    }

    if ($location.EndsWith($pathSep) -and -not $isRootPath) {
        $location = $location.TrimEnd($pathSep)
        if ($DebugPrompt) {
            Write-Host "[DEBUG] location (trimmed): $location" -ForegroundColor Magenta
        }
    }

    # Get user profile path (cross-platform)
    $userProfilePath = if ($onWindows) { $env:USERPROFILE } else { $env:HOME }

    if ($DebugPrompt) {
        Write-Host "[DEBUG] userProfilePath: $userProfilePath" -ForegroundColor Magenta
        Write-Host "[DEBUG] location.Contains(userProfilePath): $($location.Contains($userProfilePath))" -ForegroundColor Magenta
    }

    if ($location.Contains($userProfilePath)) {
        if ($location.Equals($userProfilePath)) {
            $promptPath = '~'
            if ($DebugPrompt) {
                Write-Host "[DEBUG] At home directory, promptPath: $promptPath" -ForegroundColor Magenta
            }
        }
        else {
            # Extract the relative path from user profile
            # The -split operator uses regex, so escape the path separator for regex
            $escapedProfilePath = $userProfilePath -replace ([regex]::Escape($pathSep)), ([regex]::Escape($pathSep))
            $relativelocation = ($location -split $escapedProfilePath)[1]

            if ($DebugPrompt) {
                Write-Host "[DEBUG] relativelocation: $relativelocation" -ForegroundColor Magenta
                Write-Host "[DEBUG] relativelocation.Length: $($relativelocation.Length)" -ForegroundColor Magenta
            }

            if ($relativelocation.Length -le 50) {
                $promptPath = '~' + $relativelocation
                if ($DebugPrompt) {
                    Write-Host "[DEBUG] Short path, promptPath: $promptPath" -ForegroundColor Magenta
                }
            }
            else {
                # Path is long, so shorten it by keeping first 3 folders and last 2 folders
                $matches = [regex]::matches($relativelocation, $pathSepRegex)

                if ($DebugPrompt) {
                    Write-Host "[DEBUG] Long path detected, matches.count: $($matches.count)" -ForegroundColor Magenta
                }

                switch ($matches.count) {
                    # Display full relative path if 4 or fewer folders
                    { $_ -ge 1 -and $_ -le 4 } {
                        $promptPath = '~' + $relativelocation
                        if ($DebugPrompt) {
                            Write-Host "[DEBUG] 4 or fewer folders, promptPath: $promptPath" -ForegroundColor Magenta
                        }
                        break
                    }
                    # Path is long, so add '...' in the middle
                    default {
                        $leftPath   = $relativelocation.Substring(0, $matches[2].index)
                        $rightPath  = $relativelocation.Substring($matches[$matches.count - 2].index)
                        $promptPath = '~' + $leftPath + $pathSep + '...' + $rightPath
                        if ($DebugPrompt) {
                            Write-Host '[DEBUG] Shortened path:' -ForegroundColor Magenta
                            Write-Host "[DEBUG]   leftPath: $leftPath" -ForegroundColor Magenta
                            Write-Host "[DEBUG]   rightPath: $rightPath" -ForegroundColor Magenta
                            Write-Host "[DEBUG]   promptPath: $promptPath" -ForegroundColor Magenta
                        }
                    }
                }
            }
        }
    }
    else {
        # Build prompt path for locations outside of user profile (e.g., 'C:\Windows\System32' or '/etc/nginx')
        if ($DebugPrompt) {
            Write-Host '[DEBUG] Outside user profile' -ForegroundColor Magenta
        }

        $matches = [regex]::matches($location, $pathSepRegex)

        if ($DebugPrompt) {
            Write-Host "[DEBUG] matches.count: $($matches.count)" -ForegroundColor Magenta
        }

        switch ($matches.count) {
            { $_ -ge 1 -and $_ -le 4 } {
                $promptPath = $location
                if ($DebugPrompt) {
                    Write-Host "[DEBUG] Short outside path, promptPath: $promptPath" -ForegroundColor Magenta
                }
                break
            }
            default {
                $leftPath   = $location.Substring(0, $matches[2].index)
                $rightPath  = $location.Substring($matches[$_ - 2].index)
                $promptPath = $leftPath + $pathSep + '...' + $rightPath
                if ($DebugPrompt) {
                    Write-Host '[DEBUG] Long outside path:' -ForegroundColor Magenta
                    Write-Host "[DEBUG]   leftPath: $leftPath" -ForegroundColor Magenta
                    Write-Host "[DEBUG]   rightPath: $rightPath" -ForegroundColor Magenta
                    Write-Host "[DEBUG]   promptPath: $promptPath" -ForegroundColor Magenta
                }
            }
        }
    }

    if ($DebugPrompt) {
        Write-Host "[DEBUG] Final promptPath: $promptPath" -ForegroundColor Magenta
    }

    $promptPath
}

function Initialize-PoshGit {
    # Initialize Posh-Git module and settings
    # Only loads in PowerShell Core when in a Git directory
    # Should be called once during profile load, not in the prompt function

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
# INITIALIZE POSH-GIT
# ============================================================================

# Try to initialize Posh-Git once during profile load if in PowerShell Core and in a git directory
# Store result in script-scoped variable to avoid Get-Module calls in prompt
$script:PoshGitLoaded = $false
if ($PSVersionTable.PSEdition -eq 'Core') {
    $script:PoshGitLoaded = Initialize-PoshGit
}