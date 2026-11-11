# ---------------------------------------------------------------------------
# Description   : Provide prompt, Git, and environment support functions.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Share each prompt's Git worktree check across initializers.
#   2026-11-11 - Resolve prompt variables without importing Utility.
#   2026-11-11 - Trace Python environment label resolution.
#   2026-11-11 - Resolve prompt locations without importing Management.
#   2026-11-11 - Trace Management module state around prompt location lookup.
#   2026-11-11 - Trace Git discovery and Posh-Git initialization during first prompt.
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region PROMPT AND GIT SUPPORT FUNCTIONS

Write-ProfileTime 'Before prompt and Git support functions'

function Get-AzProfilePromptText {
	# Resolve the active named Azure CLI profile without invoking Azure commands.
	$configDir = $env:AZURE_CONFIG_DIR
	if ([string]::IsNullOrWhiteSpace($configDir)) {
		return ''
	}

	try {
		# Accept native or alternate directory separators and ignore a trailing separator.
		$trimCharacters = [char[]]@('\', '/')
		$trimmedConfigDir = $configDir.TrimEnd($trimCharacters)
		$profileName = [System.IO.Path]::GetFileName($trimmedConfigDir)
		$profileDirectory = [System.IO.Path]::GetDirectoryName($trimmedConfigDir)
		$expectedProfileDirectory = [System.IO.Path]::Combine([string[]]@($HOME, '.azure', 'profiles'))

		# Display only directories created for named profiles under ~/.azure/profiles.
		if (
			[string]::IsNullOrWhiteSpace($profileName) -or
			[string]::IsNullOrWhiteSpace($profileDirectory) -or
			[System.IO.Path]::GetFullPath($profileDirectory).TrimEnd($trimCharacters) -ine
			[System.IO.Path]::GetFullPath($expectedProfileDirectory).TrimEnd($trimCharacters)
		) {
			return ''
		}

		# Read the Azure CLI's active subscription from the named profile's local state.
		$subscriptionSuffix = ''
		$azureProfilePath = [System.IO.Path]::Combine([string[]]@($trimmedConfigDir, 'azureProfile.json'))
		if ([System.IO.File]::Exists($azureProfilePath)) {
			try {
				$azureProfile = [System.IO.File]::ReadAllText($azureProfilePath) | ConvertFrom-Json
				$currentSubscription = @($azureProfile.subscriptions | Where-Object { $_.isDefault })[0]
				if ($currentSubscription -and -not [string]::IsNullOrWhiteSpace($currentSubscription.name)) {
					$subscriptionSuffix = " - $($currentSubscription.name)"
				}
			}
			catch {
				# Keep unavailable local Azure CLI state from interrupting prompt rendering.
			}
		}

		return "[az:$profileName$subscriptionSuffix] "
	}
	catch {
		# Keep invalid profile paths from interrupting prompt rendering.
		return ''
	}
}

function Get-MgProfilePromptText {
	# Resolve the active named Microsoft Graph profile from process-local session state.
	try {
		$stateVariable = $ExecutionContext.SessionState.PSVariable.Get('global:MSCloudMgProfileName')
		if (-not $stateVariable) {
			return ''
		}

		$profileName = [string]$stateVariable.Value
		if (
			[string]::IsNullOrWhiteSpace($profileName) -or
			$profileName -ieq '(default)' -or
			$profileName -ieq 'default'
		) {
			return ''
		}

		return "[mg:$profileName] "
	}
	catch {
		# Keep unavailable session state from interrupting prompt rendering.
		return ''
	}
}

function Get-PythonVenvPromptText {
	param([switch]$TraceTiming)
	# Resolve active Python venv label exactly as set by Activate.ps1 when present.
	$venvPrompt = $null
	$promptLabels = @()

	# Isolate the first global variable lookup and any Utility module import.
	if ($TraceTiming) {
		Write-ProfileTime ('First prompt: before Python prefix lookup (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
	}
	$venvPrefixVariable = $ExecutionContext.SessionState.PSVariable.Get('global:_PYTHON_VENV_PROMPT_PREFIX')
	if ($TraceTiming) { Write-ProfileTime 'First prompt: after Python prefix lookup' }
	if ($TraceTiming) {
		Write-ProfileTime ('First prompt: after Python prefix module check (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
	}
	if ($venvPrefixVariable) {
		$venvPrompt = $venvPrefixVariable.Value
		if ($TraceTiming) { Write-ProfileTime 'First prompt: after Python prefix value lookup' }
	}
	elseif (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV_PROMPT)) {
		$venvPrompt = $env:VIRTUAL_ENV_PROMPT
	}
	elseif (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
		if ($TraceTiming) { Write-ProfileTime 'First prompt: before Python environment path lookup' }
		$venvPrompt = Split-Path -Path $env:VIRTUAL_ENV -Leaf
		if ($TraceTiming) { Write-ProfileTime 'First prompt: after Python environment path lookup' }
	}
	if ($TraceTiming) { Write-ProfileTime 'First prompt: after Python environment selection' }

	if ([string]::IsNullOrWhiteSpace($venvPrompt)) {
		$venvPrompt = $null
	}

	if (-not [string]::IsNullOrWhiteSpace($venvPrompt)) {
		$promptLabels += "($venvPrompt)"
	}

	$condaPrompt = $null
	if (-not [string]::IsNullOrWhiteSpace($env:CONDA_PROMPT_MODIFIER)) {
		$condaPrompt = $env:CONDA_PROMPT_MODIFIER.Trim()
	}
	elseif (-not [string]::IsNullOrWhiteSpace($env:CONDA_DEFAULT_ENV)) {
		$condaPrompt = "($($env:CONDA_DEFAULT_ENV))"
	}
	if ($TraceTiming) { Write-ProfileTime 'First prompt: after Conda environment selection' }

	if (-not [string]::IsNullOrWhiteSpace($condaPrompt)) {
		$promptLabels += $condaPrompt
	}

	if ($promptLabels.Count -eq 0) {
		return ''
	}

	($promptLabels -join ' ') + ' '
}

function Test-GitDirectory {
	param([switch]$TraceTiming, [hashtable]$ProbeCache)
	# Check the current directory without scanning the working tree.
	$probeLocation = $ExecutionContext.SessionState.Path.CurrentLocation.Path
	if ($null -ne $ProbeCache -and $ProbeCache.ContainsKey('IsWorkTree') -and $ProbeCache.Location -eq $probeLocation) {
		if ($TraceTiming) { Write-ProfileTime 'First prompt: reused Git worktree check' }
		return $ProbeCache.IsWorkTree
	}
	if (-not $script:GitCommandChecked) {
		if ($TraceTiming) { Write-ProfileTime 'First prompt: before Git command discovery' }
		$script:GitCommand = Get-Command -Name git.exe -CommandType Application -ErrorAction SilentlyContinue
		$script:GitCommandChecked = $true
		if ($TraceTiming) { Write-ProfileTime 'First prompt: after Git command discovery' }
	}

	if (-not $script:GitCommand) {
		$isWorkTree = $false
	}
	else {
		try {
			if ($TraceTiming) { Write-ProfileTime 'First prompt: before Git worktree check' }
			$insideWorkTree = & $script:GitCommand.Path rev-parse --is-inside-work-tree 2>$null
			$isWorkTree = $LASTEXITCODE -eq 0 -and $insideWorkTree -contains 'true'
			if ($TraceTiming) { Write-ProfileTime 'First prompt: after Git worktree check' }
		}
		catch {
			# Ignore errors from Git when the location is not a file-system repository.
			$isWorkTree = $false
		}
	}
	# Share the result only within this prompt and only for the same location.
	if ($null -ne $ProbeCache) {
		$ProbeCache.Location = $probeLocation
		$ProbeCache.IsWorkTree = $isWorkTree
	}
	return $isWorkTree
}

function Initialize-AICommitEnvironment {
	param([switch]$TraceTiming, [hashtable]$ProbeCache)
	# Load the commit-hook key once when entering a Git worktree and clear it on exit.
	$locationPath = $ExecutionContext.SessionState.Path.CurrentLocation.Path
	if ($script:AICommitProbePath -eq $locationPath) {
		return
	}

	$script:AICommitProbePath = $locationPath
	$insideGitWorktree = Test-GitDirectory -TraceTiming:$TraceTiming -ProbeCache $ProbeCache
	if (-not $insideGitWorktree) {
		[Environment]::SetEnvironmentVariable('AI_COMMIT_BASE_URL', $null, 'Process')
		[Environment]::SetEnvironmentVariable('AI_COMMIT_MODEL', $null, 'Process')
		[Environment]::SetEnvironmentVariable('AI_COMMIT_API_KEY', $null, 'Process')
		return
	}

	$env:AI_COMMIT_BASE_URL = 'https://openrouter.ai/api/v1'
	$env:AI_COMMIT_MODEL = 'google/gemini-2.5-flash'

	if (-not $script:AICommitKeyLoadAttempted) {
		$script:AICommitKeyLoadAttempted = $true
		try {
			$script:AICommitApiKey = Get-Secret -Name AI_COMMIT_API_KEY -AsPlainText -ErrorAction Stop
		}
		catch {
			$script:AICommitApiKey = $null
		}
	}

	if ([string]::IsNullOrWhiteSpace($script:AICommitApiKey)) {
		[Environment]::SetEnvironmentVariable('AI_COMMIT_API_KEY', $null, 'Process')
		Write-Warning 'Git commit message key unavailable; unlock SecretStore or verify AI_COMMIT_API_KEY.'
		return
	}

	$env:AI_COMMIT_API_KEY = $script:AICommitApiKey
}

function Initialize-PromptPoshGit {
	param([switch]$TraceTiming, [hashtable]$ProbeCache)
	# Load Posh-Git only after entering a repository that has not been checked.
	if ($TraceTiming) { Write-ProfileTime 'First prompt: Posh-Git initialization started' }
	if ($script:PoshGitLoaded -or $PSVersionTable.PSEdition -ne 'Core') {
		return
	}

	# Identify whether resolving the current location loads the Management module.
	if ($TraceTiming) {
		Write-ProfileTime ('First prompt: before Posh-Git location lookup (Management loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Management))
	}
	$locationPath = $ExecutionContext.SessionState.Path.CurrentLocation.Path
	if ($TraceTiming) { Write-ProfileTime 'First prompt: after Posh-Git location lookup' }
	if ($TraceTiming) {
		Write-ProfileTime ('First prompt: after Posh-Git location check (Management loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Management))
	}
	if ($script:GitProbePath -eq $locationPath) {
		return
	}

	$script:GitProbePath = $locationPath
	if (Test-GitDirectory -TraceTiming:$TraceTiming -ProbeCache $ProbeCache) {
		if ($TraceTiming) { Write-ProfileTime 'First prompt: Git worktree detected' }
		$script:PoshGitLoaded = Initialize-PoshGit -TraceTiming:$TraceTiming
	}
	elseif ($TraceTiming) {
		Write-ProfileTime 'First prompt: no Git worktree detected'
	}
}

function Get-GitPromptStatusText {
	# Get prompt status and include upstream tracking branch when available.
	if (-not $script:PoshGitLoaded) {
		return ''
	}

	# Create prompt metadata only when a loaded Posh-Git prompt needs it.
	if ($null -eq $script:GitPromptMetaCache) {
		$script:GitPromptMetaCache = @{}
	}

	$cacheKey = $ExecutionContext.SessionState.Path.CurrentLocation.Path
	$cacheNow = [datetime]::UtcNow
	$cacheTtlSeconds = 5
	$cache = if ($script:GitPromptMetaCache.ContainsKey($cacheKey)) { $script:GitPromptMetaCache[$cacheKey] } else { $null }

	$gitStatusText = & $GitPromptScriptBlock
	if ([string]::IsNullOrWhiteSpace($gitStatusText)) {
		return $gitStatusText
	}

	$branchMatch = [regex]::Match($gitStatusText, '^\s*(?:\x1b\[[0-9;]*m)*\[(?<branch>[^\s\]]+)')
	if (-not $branchMatch.Success) {
		return $gitStatusText
	}
	$branchName = $branchMatch.Groups['branch'].Value

	if (-not $cache) {
		$cache = @{}
	}
	if (-not $cache.ContainsKey('RemoteCheckedAt')) {
		$cache.RemoteCheckedAt = [datetime]::MinValue
	}
	if (-not $cache.ContainsKey('RemoteCount')) {
		$cache.RemoteCount = $null
	}
	if (-not $cache.ContainsKey('UpstreamByBranch') -or $null -eq $cache.UpstreamByBranch) {
		$cache.UpstreamByBranch = @{}
	}
	if (-not $cache.ContainsKey('UpstreamCheckedAtByBranch') -or $null -eq $cache.UpstreamCheckedAtByBranch) {
		$cache.UpstreamCheckedAtByBranch = @{}
	}

	$remoteCount = $null
	if ($cache.RemoteCount -ne $null -and (($cacheNow - $cache.RemoteCheckedAt).TotalSeconds -lt $cacheTtlSeconds)) {
		$remoteCount = [int]$cache.RemoteCount
	}
	else {
		$remoteNames = @()
		try {
			$remoteNames = @(git remote 2>$null)
		}
		catch {
			$remoteNames = @()
		}

		$remoteCount = @($remoteNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
	}

	$cache.RemoteCheckedAt = $cacheNow
	$cache.RemoteCount = $remoteCount
	$script:GitPromptMetaCache[$cacheKey] = $cache

	if ($remoteCount -le 1) {
		return $gitStatusText
	}

	$upstream = if ($cache.UpstreamByBranch.ContainsKey($branchName)) { $cache.UpstreamByBranch[$branchName] } else { $null }
	$upstreamCheckedAt = if ($cache.UpstreamCheckedAtByBranch.ContainsKey($branchName)) { $cache.UpstreamCheckedAtByBranch[$branchName] } else { [datetime]::MinValue }
	if ([string]::IsNullOrWhiteSpace($upstream) -or (($cacheNow - $upstreamCheckedAt).TotalSeconds -ge $cacheTtlSeconds)) {
		try {
			$upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
		}
		catch {
			$upstream = $null
		}

		$cache.UpstreamByBranch[$branchName] = $upstream
		$cache.UpstreamCheckedAtByBranch[$branchName] = $cacheNow
		$script:GitPromptMetaCache[$cacheKey] = $cache
	}

	if ([string]::IsNullOrWhiteSpace($upstream)) {
		return $gitStatusText
	}

	$statusPrefix = $gitStatusText.Substring(0, $branchMatch.Index)
	$statusSuffix = $gitStatusText.Substring($branchMatch.Index + $branchMatch.Length)
	"$statusPrefix [$($branchMatch.Groups['branch'].Value) -> $upstream$statusSuffix"
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
		$ExecutionContext.SessionState.PSVariable.GetValue('IsWindows') -ne $false
	}
	else {
		$true  # Windows PowerShell 5.1 is always Windows
	}
	$pathSep = if ($onWindows) { '\' } else { '/' }
	$pathSepRegex = if ($onWindows) { '\\' } else { '/' }

	# Get shortened path for prompt display
	$location = $ExecutionContext.SessionState.Path.CurrentLocation.Path

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
	param([switch]$TraceTiming)
	# Initialize Posh-Git module and settings
	# Called only after the prompt has confirmed the current directory is a Git repository.

	if ($PSVersionTable.PSEdition -ne 'Core') {
		return $false
	}

	try {
		if ($TraceTiming) { Write-ProfileTime 'First prompt: before Posh-Git import' }
		Import-Module Posh-Git -ErrorAction Stop
		if ($TraceTiming) { Write-ProfileTime 'First prompt: after Posh-Git import' }

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
		if ($TraceTiming) { Write-ProfileTime 'First prompt: after Posh-Git settings' }

		return $true
	}
	catch {
		# Posh-Git not available, continue without it
		if ($TraceTiming) { Write-ProfileTime 'First prompt: Posh-Git initialization failed' }
		return $false
	}
}

#endregion
Write-ProfileTime 'After prompt and Git support functions'
