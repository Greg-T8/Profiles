# ---------------------------------------------------------------------------
# Description   : Configure the interactive PowerShell environment and prompt.
# Context       : Personal cross-host profile ($Profile.CurrentUserAllHosts).
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Resolve profile features from the dedicated Profile folder.
#   2026-11-11 - Load and measure the renamed profile functions script.
#   2026-11-11 - Show elapsed time between profile timing checkpoints.
#   2026-11-11 - Sample functions file read and parsing during timing runs.
#   2026-11-11 - Split profile features into dot-sourced scripts.
#   2026-11-11 - Create profile aliases without importing Utility.
#   2026-11-11 - Add checkpoints across profile setup before function import.
#   2026-11-11 - Write timing markers directly through the host UI.
#   2026-11-11 - Skip PSReadLine and PSFzf setup for non-interactive commands.
#   2026-11-11 - Replace Join-Path calls with System.IO.Path.Combine.
#   2026-11-11 - Show Management module state around personal path resolution.
#   2026-11-11 - Add timing checkpoints for personal path selection and Join-Path.
#   2026-11-11 - Add a checkpoint before personal configuration path resolution.
#   2026-11-11 - Add detailed startup timing checkpoints.
#   2026-11-11 - Add PSFzf provider and reverse-history shortcuts.
#   2026-11-11 - Limit automatic Herdr startup to Windows Terminal.
#   2026-11-10 - Show Tab completions in a selectable menu.
#   2026-11-09 - Preserve AllScope when setting the Neovim alias.
#   2026-11-08 - Clarify profile sections and navigation for readability.
#   2026-11-08 - Added Neovim alias and updated Git add shortcut.
# ---------------------------------------------------------------------------
# The prompt mimics Oh-My-Posh without its additional startup overhead. This
# profile configures Vi mode, shortens the displayed path, loads Posh-Git in
# Git repositories, and imports personal and work configuration when available.
# See https://devblogs.microsoft.com/powershell/optimizing-your-profile/.

#region INITIAL CONFIGURATION

$ErrorActionPreference = 'Stop'

# Track elapsed time from profile startup and between timing checkpoints.
$script:ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProfilePreviousElapsed = 0.0
function script:Write-ProfileTime {
    param([string]$Label)

    # Show cumulative and checkpoint elapsed times only during timing runs.
    if ($env:PROFILE_TIMING) {
        $elapsed = $script:ProfileTimer.Elapsed.TotalMilliseconds
        $stepElapsed = $elapsed - $script:ProfilePreviousElapsed
        $script:ProfilePreviousElapsed = $elapsed
        $Host.UI.WriteLine(('  [{0,6:N1}ms total | +{1,6:N1}ms step] {2}' -f $elapsed, $stepElapsed, $Label))
    }
}
Write-ProfileTime 'Profile start'

# Enable Herdr startup and managed-pane integration for Windows Terminal sessions.
$script:HerdrIntegrationEnabled = $false
Write-ProfileTime 'After Herdr integration setting'

# Keep Python venv activation from replacing the custom prompt function.
$env:VIRTUAL_ENV_DISABLE_PROMPT = '1'
Write-ProfileTime 'After environment variables'

# Set PSStyle formatting colors (PowerShell Core only)
if ($PSVersionTable.PSEdition -eq 'Core') {
	$PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
	$PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}
Write-ProfileTime 'After PSStyle configuration'

# Force UTF-8 encoding to avoid question marks in the prompt when using non-ASCII characters (e.g., box-drawing characters)
# See open bug: https://github.com/PowerShell/PSReadLine/issues/2866
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Write-ProfileTime 'After startup initialization'

#endregion

# Resolve feature scripts beside the profile or its OneDrive-backed target.
$profileEntryDir = [System.IO.Path]::GetDirectoryName($PSCommandPath)
$profileOneDriveDir = if (-not [string]::IsNullOrWhiteSpace($env:OneDriveConsumer)) {
    "$env:OneDriveConsumer/Apps/Profiles/PowerShell/Profile"
}
else {
    $null
}
$profileFeatureDir = if ($profileOneDriveDir -and [System.IO.File]::Exists("$profileOneDriveDir/profile-aliases.ps1")) {
    $profileOneDriveDir
}
elseif ([System.IO.File]::Exists("$profileEntryDir/profile-aliases.ps1")) {
    $profileEntryDir
}
else {
    # Resolve a linked profile when its feature files are not beside the link.
    $profileLinkTarget = (Get-Item -LiteralPath $PSCommandPath -Force).Target
    if ($profileLinkTarget) {
        [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine($profileEntryDir, [string]$profileLinkTarget)
            ))
    }
    else {
        $profileEntryDir
    }
}

# Load profile aliases into the current profile scope.
Write-ProfileTime 'Before profile aliases import'
. "$profileFeatureDir/profile-aliases.ps1"
Write-ProfileTime 'After profile aliases import'


#region DEFAULT PARAMETER VALUES
$PSDefaultParameterValues['Use-AzProfile:Name'] = 'Lab'
Write-ProfileTime 'After default parameter values'

#endregion

# Load profile prompt into the current profile scope.
Write-ProfileTime 'Before profile prompt import'
. "$profileFeatureDir/profile-prompt.ps1"
Write-ProfileTime 'After profile prompt import'


#region LOAD EXTERNAL SCRIPTS

# Keep shared modules and maintenance scripts relative to the Profile folder.
Write-ProfileTime 'Before profile directory resolution'
$profileDir = [System.IO.Path]::GetDirectoryName($profileFeatureDir)
Write-ProfileTime 'After profile directory resolution'

# Load custom functions
if ($PSVersionTable.PSEdition -eq 'Core' -and [System.IO.File]::Exists("$profileFeatureDir/profile-functions.ps1")) {
	try {
        # Sample reading and parsing separately without changing the dot-sourced script.
        if ($env:PROFILE_TIMING) {
            try {
                Write-ProfileTime 'Diagnostic sample: before profile-functions.ps1 file read'
                $functionsTimingText = [System.IO.File]::ReadAllText("$profileFeatureDir/profile-functions.ps1")
                Write-ProfileTime 'Diagnostic sample: after profile-functions.ps1 file read'
                $functionsTimingTokens = $null
                $functionsTimingErrors = $null
                Write-ProfileTime 'Diagnostic sample: before profile-functions.ps1 text parse'
                $null = [System.Management.Automation.Language.Parser]::ParseInput(
                    $functionsTimingText,
                    "$profileFeatureDir/profile-functions.ps1",
                    [ref]$functionsTimingTokens,
                    [ref]$functionsTimingErrors
                )
                Write-ProfileTime ('Diagnostic sample: after profile-functions.ps1 text parse (errors: {0})' -f $functionsTimingErrors.Count)
            }
            catch {
                # Continue with the normal import if the diagnostic sample fails.
                Write-ProfileTime 'Diagnostic sample failed; continuing with profile-functions.ps1 import'
            }
            $functionsTimingText = $null
            $functionsTimingTokens = $null
            $functionsTimingErrors = $null
        }
		Write-ProfileTime 'Before profile-functions.ps1 import'
		. "$profileFeatureDir/profile-functions.ps1"
	}
	catch {
		Write-Host "ERROR loading profile-functions.ps1: $_" -ForegroundColor Red
		Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
	}
}
Write-ProfileTime 'After custom functions'

# Load profile cloud configuration into the current profile scope.
Write-ProfileTime 'Before profile cloud configuration import'
. "$profileFeatureDir/profile-cloud.ps1"
Write-ProfileTime 'After profile cloud configuration import'
#endregion


# Load profile line editing into the current profile scope.
Write-ProfileTime 'Before profile line editing import'
. "$profileFeatureDir/profile-readline.ps1"
Write-ProfileTime 'After profile line editing import'


# Load profile prompt support into the current profile scope.
Write-ProfileTime 'Before profile prompt support import'
. "$profileFeatureDir/profile-prompt-support.ps1"
Write-ProfileTime 'After profile prompt support import'


# Load profile Herdr integration into the current profile scope.
Write-ProfileTime 'Before profile Herdr integration import'
. "$profileFeatureDir/profile-herdr.ps1"
Write-ProfileTime 'After profile Herdr integration import'

Write-ProfileTime 'Profile end'
