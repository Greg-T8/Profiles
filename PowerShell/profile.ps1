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

if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow

    # Enable PSReadline prediction
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
}

if (Test-Path -Path ./functions.ps1) {
    . ./functions.ps1
}

if (Test-Path -Path $env:OneDriveCommercial/Code/WorkConfig.psd1) {
    $Work = Import-PowerShellDataFile -Path $env:OneDriveCommercial/Code/WorkConfig.psd1

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


# Aliases
Set-Alias -Name ll -Value Get-ChildItem -Force

function touch {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        # Update last modified time
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        # Create the file
        New-Item -ItemType File -Path $Path | Out-Null
    }
}



# Enable keyboard shortcuts
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -ViModeIndicator 'Cursor'
Set-PSReadLineKeyHandler -Chord Tab -Function TabCompleteNext
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste

$PoshGitSettings = {
    $GitPromptSettings.DefaultPromptPath            = ''
    $GitPromptSettings.DefaultPromptSuffix          = ''
    $GitPromptSettings.DefaultPromptDebug           = ''
    $GitPromptSettings.EnableStashStatus            = $true
    $GitPromptSettings.BeforeStatus.ForegroundColor = 0x00B3E2      # 0x00B3E2 is rgb color (0, 179, 226)
    $GitPromptSettings.AfterStatus.ForegroundColor  = 0x00B3E2
    $GitPromptSettings.WorkingColor.ForegroundColor = 0x8A0ACC      # 0x8A0ACC is rgb color (138, 10, 204)
    $StashColor                                     = 0xAFB178      # 0xAFB178 is rgb color (175, 177, 120)
    $GitPromptSettings.StashColor.ForegroundColor   = $StashColor
    $GitPromptSettings.BeforeStash.ForegroundColor  = $StashColor
    $GitPromptSettings.AfterStash.ForegroundColor   = $StashColor
}

# Import Posh-Git module if running in VSCode and apply Posh-Git settings
if ($Profile -match 'VSCode') {
    Import-Module Posh-Git
    & $PoshGitSettings
    $UsingPoshGit = $true
    $EstablishedPoshGitSettings = $true
}

function ep {
    code -n --profile 'PowerShell' $PROFILE.CurrentUserAllHosts
}

function CleanUpSnagitFolder {
    $folderPath = 'C:\Users\gregt\OneDrive\Snagit'
    $cutoffDate = (Get-Date).AddMonths(-1)
    Get-ChildItem -Path $folderPath -File | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force
}

function GetMicrosoftLicenseCatalog {
    [OutputType([PSCustomObject[]])]
    $url = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
    $response = Invoke-WebRequest -Uri $Url
    $csvLink = $response.Links | Select-Object href | Where-Object { $_ -match 'csv' } |
        Select-Object -ExpandProperty href
    $licenseCatalog = Invoke-RestMethod -Uri $csvLink
    $licenseCatalog = $licenseCatalog | ConvertFrom-Csv
    Write-Output $licenseCatalog
}

function tempcode {
    param (
        [switch]$Clean
    )
    $tempDir = "$env:TEMP/tempvscode"
    if (-not $Clean) {
        # Open a new VSCode window with the current directory as the working directory
        & code --user-data-dir=$tempDir --extensions-dir="$tempDir/extensions"
        return
    }
    else {
        # Remove the temp VSCode user data and extensions directories
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}


function prompt {
    # Apply Posh-Git settings if module is loaded or if current directory is a git repository
    if (Get-Module -Name Posh-Git) {
        $UsingPoshGit = $true
        if (-not $script:EstablishedPoshGitSettings) {
            & $PoshGitSettings
            $EstablishedPoshGitSettings = $true
        }
    }
    else {
        if (IsGitDirectory) {
            Import-Module Posh-Git
            & $PoshGitSettings
            $UsingPoshGit               = $true
            $EstablishedPoshGitSettings = $true
        }
    }

    # Hard-code prompt colors and styles using ANSI escape codes
    # See here for list of ANSI escape references:
    # - https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
    # - https://en.wikipedia.org/wiki/ANSI_escape_code

    $ESC = [char]0x1b           # Define the escape character used for specifying colors and styles
    # Prompt starts here
    "`n" + # New line
    "$ESC[38;2;0;179;226m" +    # Set foreground color (38) using rgb mode (2) with rgb colors (0, 179, 226)
    $([char]0x256d) +           # The '╭' character, i.e. Box Drawings Light Arc Down and Right
    $([char]0x2500) +           # The '─' character, i.e. Box Drawings Light Horizontal
    '( ' +
    "$ESC[3m" +                 # Start italic mode
    "$ESC[2m" +                 # Start dim/faint mode
    $(GetPromptPath) +
    "$ESC[22m" +                # Reset dim/faint mode
    "$(if ($usingPoshGit) { "$(& $GitPromptScriptBlock)" })" +
    "$ESC[23m" +                # Reset italic mode
    "`n" +
    "$ESC[38;2;0;179;226m" +    # Set foreground color (38) using rgb mode (2) with rgb colors (0, 179, 226)
    $([char]0x2570) +           # The '╰' character, i.e. Box Drawings Light Arc Up and Right
    $([char]0x2574) +           # The '─' character, i.e. Box Drawings Light Right
    "$ESC[0m" +                 # Reset all modes (styles and colors)
    $(
        if (Test-Path variable:/PSDebugContext) { '[DBG]: ' } else { '' }
    ) +
    $(
        if ($NestedPromptLevel -ge 1) { '>>' }
    ) +
    '> '
}

# Prompt Helpers

function IsGitDirectory {
    $gitCommand = Get-Command -Name git.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitStatus = git status 2>&1
        if (-not ($gitStatus -match 'fatal: not a git repository')) {
            return $true
        }
    }
}

function GetPromptPath {
    $location = "$(Get-Location)"

    # Get rid of trailing slash except for 'C:\'.  For example, HKLM:\...\ has a trailing slash
    if ($location.EndsWith('\') -and -not $location.EndsWith(':\')) {
        $location = $location.TrimEnd('\')
    }

    $userProfilePath = $env:USERPROFILE
    if ($location.Contains($userProfilePath)) {
        if ($location.Equals($userProfilePath)) {
            $promptPath = '~'
        }
        else {
            # The -split operator uses regex. Since the string has a regex escape character, '\', you must replace
            # each '\' with a '\\' (second part of the -replace function). The first part of the replace function
            # searches for any single instance of '\', using '\\' as an escape sequence.  The -split function
            # returns an array of two elements.  The first element is blank. The second element, [1], has the
            # string we need.
            $relativelocation = ($location -split ($userProfilePath -replace ('\\', '\\')))[1]

            if ($relativelocation.Length -le 50) {
                $promptPath = '~' + $relativelocation
            }
            else {
                $matches = [regex]::matches($relativelocation, '\\')
                switch ($matches.count) {
                    # Display full relative for given range of matches
                    { $_ -in 1..4 } {
                        $promptPath = '~' + $relativelocation
                        break
                    }
                    # Path is long, so break up the relative path with '...' in the middle.
                    # Left portion of the path keeps first n+1 folders
                    # Right portion of the path keeps the last n folders
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
        # Build prompt path for locations outside of user profile path, e.g. 'C:\Windows\System32'
        $matches = [regex]::matches($location, '\\')
        switch ($matches.count) {
            { $_ -in 1..4 } {
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
