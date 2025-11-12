# ============================================================================
# POSH-GIT CONFIGURATION
# ============================================================================

$PoshGitSettings = {
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
}

# Import Posh-Git if running in VSCode
if ($Profile -match 'VSCode') {
    try {
        Import-Module Posh-Git -ErrorAction Stop
        & $PoshGitSettings
        $UsingPoshGit = $true
        $EstablishedPoshGitSettings = $true
    }
    catch {
        # Posh-Git not available, continue without it
    }
}

# ============================================================================
# PROMPT FUNCTION
# ============================================================================

function prompt {
    # Load Posh-Git if module is available or if in a git repository
    if (Get-Module -Name Posh-Git) {
        $UsingPoshGit = $true
        if (-not $script:EstablishedPoshGitSettings) {
            & $PoshGitSettings
            $EstablishedPoshGitSettings = $true
        }
    }
    else {
        if (IsGitDirectory) {
            try {
                Import-Module Posh-Git -ErrorAction Stop
                & $PoshGitSettings
                $UsingPoshGit               = $true
                $EstablishedPoshGitSettings = $true
            }
            catch {
                # Posh-Git not available, continue without it
            }
        }
    }

    # Use different prompt styles based on PowerShell version
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # PowerShell 7+ with ANSI escape codes
        $ESC = [char]0x1b                                            # ESC character for ANSI sequences
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        $([char]0x256d) +                                            # '╭' Box Drawings Light Arc Down and Right
        $([char]0x2500) +                                            # '─' Box Drawings Light Horizontal
        '( ' +                                                       # Opening parenthesis and space
        "$ESC[3m" +                                                  # Start italic mode
        "$ESC[2m" +                                                  # Start dim/faint mode
        $(GetPromptPath) +                                           # Display shortened path
        "$ESC[22m" +                                                 # Reset dim/faint mode
        "$(if ($usingPoshGit) { "$(& $GitPromptScriptBlock)" })" +  # Git status if in git repo
        "$ESC[23m" +                                                 # Reset italic mode
        "`n" +                                                       # New line
        "$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
        $([char]0x2570) +                                            # '╰' Box Drawings Light Arc Up and Right
        $([char]0x2574) +                                            # '╴' Box Drawings Light Left
        "$ESC[0m" +                                                  # Reset all ANSI formatting
        $(if (Test-Path variable:/PSDebugContext) { '[DBG]: ' } else { '' }) +  # Debug indicator
        $(if ($NestedPromptLevel -ge 1) { '>>' }) +                  # Nested prompt indicator
        '> '                                                         # Prompt character
    }
    else {
        # Windows PowerShell 5.1 - Use Write-Host with colors
        try {
            $pathText = GetPromptPath
            Write-Host "$pathText" -NoNewline -ForegroundColor DarkGray
            Write-Host ""
            if (Test-Path variable:/PSDebugContext) {
                Write-Host "[DBG]: " -NoNewline
            }
            if ($NestedPromptLevel -ge 1) {
                Write-Host ">>" -NoNewline
            }
            return "PS> "
            Write-Host "" # New line
        }
        catch {
            # If there's an error, return a simple prompt so we can see what went wrong
            Write-Host "Error in prompt: $_" -ForegroundColor Red
            return "PS> "
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function IsGitDirectory {
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
}

function GetPromptPath {
    $location = "$(Get-Location)"

    # Remove trailing slash except for root paths like 'C:\'
    if ($location.EndsWith('\') -and -not $location.EndsWith(':\')) {
        $location = $location.TrimEnd('\')
    }

    $userProfilePath = $env:USERPROFILE
    if ($location.Contains($userProfilePath)) {
        if ($location.Equals($userProfilePath)) {
            $promptPath = '~'
        }
        else {
            # Extract the relative path from user profile
            # The -split operator uses regex, so we must escape backslashes
            $relativelocation = ($location -split ($userProfilePath -replace ('\\', '\\')))[1]

            if ($relativelocation.Length -le 50) {
                $promptPath = '~' + $relativelocation
            }
            else {
                # Path is long, so shorten it by keeping first 3 folders and last 2 folders
                $matches = [regex]::matches($relativelocation, '\\')
                switch ($matches.count) {
                    # Display full relative path if 4 or fewer folders
                    { $_ -ge 1 -and $_ -le 4 } {
                        $promptPath = '~' + $relativelocation
                        break
                    }
                    # Path is long, so add '...' in the middle
                    default {
                        $leftPath   = $relativelocation.Substring(0, $matches[2].index)
                        $rightPath  = $relativelocation.Substring($matches[$matches.count - 2].index)
                        $promptPath = '~' + $leftPath + '\...' + $rightPath
                    }
                }
            }
        }
    }
    else {
        # Build prompt path for locations outside of user profile (e.g., 'C:\Windows\System32')
        $matches = [regex]::matches($location, '\\')
        switch ($matches.count) {
            { $_ -ge 1 -and $_ -le 4 } {
                $promptPath = $location
                break
            }
            default {
                $leftPath   = $location.Substring(0, $matches[2].index)
                $rightPath  = $location.Substring($matches[$_ - 2].index)
                $promptPath = $leftPath + '\...' + $rightPath
            }
        }
    }
    $promptPath
}
