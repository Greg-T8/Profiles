# ---------------------------------------------------------------------------
# Description   : Configure the interactive PowerShell environment and prompt.
# Context       : Personal cross-host profile ($Profile.CurrentUserAllHosts).
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
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

# Record profile timing only when PROFILE_TIMING is enabled.
$script:ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
function script:Write-ProfileTime {
	param([string]$Label)

	# Emit elapsed profile time without affecting normal startup output.
	if ($env:PROFILE_TIMING) {
		$elapsed = $script:ProfileTimer.Elapsed.TotalMilliseconds
		$Host.UI.WriteLine(('  [{0,6:N1}ms] {1}' -f $elapsed, $Label))
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
    "$env:OneDriveConsumer/Apps/Profiles/PowerShell"
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

# Prefer the known OneDrive profile root and resolve the script path only when it is unavailable.
Write-ProfileTime 'Before profile directory resolution'
$profileDir = if (-not [string]::IsNullOrWhiteSpace($env:OneDriveConsumer)) {
	"$env:OneDriveConsumer/Apps/Profiles/PowerShell"
}
else {
	Split-Path -Parent $PSCommandPath
}
Write-ProfileTime 'After profile directory resolution'

# Load custom functions
if ($PSVersionTable.PSEdition -eq 'Core' -and [System.IO.File]::Exists("$profileDir/functions.ps1")) {
	try {
		Write-ProfileTime 'Before functions.ps1 import'
		. "$profileDir/functions.ps1"
	}
	catch {
		Write-Host "ERROR loading functions.ps1: $_" -ForegroundColor Red
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
