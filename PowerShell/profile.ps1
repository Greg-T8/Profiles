<#
    Program: profile.ps1
    Description: Configures the interactive PowerShell environment and prompt.
    Context: Personal cross-host PowerShell profile.
    Author: Greg Tate

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

#region INITIAL CONFIGURATION

$ErrorActionPreference = 'Stop'

# Record profile timing only when PROFILE_TIMING is enabled.
$script:ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
function script:Write-ProfileTime {
	param([string]$Label)

	# Emit elapsed profile time without affecting normal startup output.
	if ($env:PROFILE_TIMING) {
		$elapsed = $script:ProfileTimer.Elapsed.TotalMilliseconds
		Write-Host ('  [{0,6:N1}ms] {1}' -f $elapsed, $Label) -ForegroundColor DarkGray
	}
}
Write-ProfileTime 'Profile start'


# Keep Python venv activation from replacing the custom prompt function.
$env:VIRTUAL_ENV_DISABLE_PROMPT = '1'

# Set PSStyle formatting colors (PowerShell Core only)
if ($PSVersionTable.PSEdition -eq 'Core') {
	$PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
	$PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow
}

# Force UTF-8 encoding to avoid question marks in the prompt when using non-ASCII characters (e.g., box-drawing characters)
# See open bug: https://github.com/PowerShell/PSReadLine/issues/2866
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Write-ProfileTime 'After startup initialization'

#endregion

#region ALIASES
Set-Alias -Name ll -Value Get-ChildItem -Force
Set-Alias -Name cfj -Value ConvertFrom-Json
Set-Alias -Name gim -Value Get-InstalledModule
Set-Alias -Name rdn -Value Resolve-DNSName
Set-Alias -Name uap -Value Use-AzProfile
Set-Alias -Name ugp -Value Use-MgProfile
Set-Alias -Name gcap -Value Get-CurrentAzProfile
Set-Alias -Name gcgp -Value Get-CurrentMgProfile
Set-Alias -Name uas -Value Use-AzProfileSubscription
Set-Alias -Name uaps -Value Use-AzureProfileSubscription
Set-Alias -Name gbs -Value Get-BillingSubscriptions
Set-Alias -Name td -Value Get-TimeDifference
Set-Alias -Name tf -Value terraform


# Git aliases
Set-Alias -Name sgr -Value Set-GitRepoRoot
Set-Alias -Name ghel -Value Show-GhFailedRunLog

# Azure DevOps aliases
Set-Alias -Name adel -Value Show-AdoFailedRunLog

# Docker aliases
Set-Alias -Name dex -Value DockerExec
Set-Alias -Name dil -Value DockerImageList
Set-Alias -Name dcl -Value DockerContainerList
Set-Alias -Name regctl -Value RegCtlCmd

#endregion

#region Default Parameter Values
$PSDefaultParameterValues['Use-AzProfile:Name'] = 'Lab'

#endregion

#region PROMPT FUNCTION
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( [az:Lab] [mg:Lab] (venv) ~/path/to/directory [git-status]
#   ╰╴>
function prompt {
	Initialize-PromptPoshGit

	$pythonVenvPromptText = Get-PythonVenvPromptText

	# Use different prompt styles based on PowerShell edition
	if ($PSVersionTable.PSEdition -eq 'Core') {
		# PowerShell Core with ANSI escape codes
		$ESC = [char]0x1b                                            # ESC character for ANSI sequences
		$azProfilePromptText = Get-AzProfilePromptText
		$mgProfilePromptText = Get-MgProfilePromptText
		$azProfilePromptStyledText = if ([string]::IsNullOrWhiteSpace($azProfilePromptText)) {
			''
		}
		else {
			"$ESC[38;2;0;120;212m$azProfilePromptText$ESC[38;2;0;179;226m"
		}
		$mgProfilePromptStyledText = if ([string]::IsNullOrWhiteSpace($mgProfilePromptText)) {
			''
		}
		else {
			"$ESC[38;2;76;220;100m$mgProfilePromptText$ESC[38;2;0;179;226m"
		}
		$pythonVenvPromptStyledText = if ([string]::IsNullOrWhiteSpace($pythonVenvPromptText)) {
			''
		}
		else {
			"$ESC[38;2;76;220;100m$pythonVenvPromptText$ESC[0m$ESC[38;2;0;179;226m"
		}
		"`n" +                                                       # New line
		"$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
		'╭─( ' +                                                     # Box drawing characters and opening parenthesis
		"$ESC[3m" +                                                  # Start italic mode
		"$ESC[2m" +                                                  # Start dim/faint mode
		"$azProfilePromptStyledText$mgProfilePromptStyledText$pythonVenvPromptStyledText$(Get-MyPromptPath)" + # Display optional context labels and shortened path
		"$ESC[22m" +                                                 # Reset dim/faint mode
		"$(if ($script:PoshGitLoaded) { "$(Get-GitPromptStatusText)" })" +   # Git status if in git repo
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

#endregion

#region LOAD EXTERNAL SCRIPTS

# Prefer the known OneDrive profile root and resolve the script path only when it is unavailable.
$profileDir = if (-not [string]::IsNullOrWhiteSpace($env:OneDriveConsumer)) {
	"$env:OneDriveConsumer/Apps/Profiles/PowerShell"
}
else {
	Split-Path -Parent $PSCommandPath
}

# Load custom functions
if ($PSVersionTable.PSEdition -eq 'Core' -and [System.IO.File]::Exists("$profileDir/functions.ps1")) {
	try {
		. "$profileDir/functions.ps1"
	}
	catch {
		Write-Host "ERROR loading functions.ps1: $_" -ForegroundColor Red
		Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
	}
}
Write-ProfileTime 'After custom functions'

# Load personal configuration
$personalConfigPath = "$env:OneDriveConsumer/Apps/PowerShell/PersonalConfig.psd1"
if ([System.IO.File]::Exists($personalConfigPath)) {
	$Personal = Import-PowerShellDataFile -Path $personalConfigPath
}

# Load work configuration
$workConfigPath = "$env:OneDriveCommercial/Code/PowerShell/Config/WorkConfig.psd1"
if ([System.IO.File]::Exists($workConfigPath)) {
	$Work = Import-PowerShellDataFile -Path $workConfigPath
}
Write-ProfileTime 'After profile configuration'

# Define immediate-use profile commands while deferring the complete MSCloudProfile module import.
if ($PSVersionTable.PSEdition -eq 'Core') {
	function Import-MSCloudProfile {
		# Load the complete module the first time a profile-switching command is invoked.
		if (Get-Module -Name MSCloudProfile) {
			return
		}

		$msCloudProfileManifest = "$profileDir/Modules/MSCloudProfile.psd1"
		if (-not [System.IO.File]::Exists($msCloudProfileManifest)) {
			throw "MSCloudProfile module manifest was not found: $msCloudProfileManifest"
		}

		Import-Module -Name $msCloudProfileManifest -Global -ErrorAction Stop
	}

	function Use-AzProfile {
		# Import and invoke the Azure profile-switching command on first use.
		[CmdletBinding()]
		param(
			[Parameter(Mandatory, Position = 0)]
			[string]$Name,

			[Parameter()]
			[switch]$Force,

			[Parameter()]
			[switch]$SelectAccount
		)

		Import-MSCloudProfile
		& MSCloudProfile\Use-AzProfile @PSBoundParameters
	}

	function Get-AzProfiles {
		# Import and invoke Azure profile discovery on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-AzProfiles @PSBoundParameters
	}

	function Get-CurrentAzProfile {
		# Import and invoke Azure current-profile inspection on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-CurrentAzProfile @PSBoundParameters
	}

	function Use-MgProfile {
		# Import and invoke the Microsoft Graph profile-switching command on first use.
		[CmdletBinding()]
		param(
			[Parameter(Mandatory, Position = 0)]
			[string]$Name,

			[Parameter()]
			[string[]]$Scopes,

			[Parameter()]
			[string]$ClientId,

			[Parameter()]
			[string]$LoginHint,

			[Parameter()]
			[switch]$NoWelcome,

			[Parameter()]
			[switch]$Force
		)

		Import-MSCloudProfile
		& MSCloudProfile\Use-MgProfile @PSBoundParameters
	}

	function Get-MgProfiles {
		# Import and invoke Microsoft Graph profile discovery on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-MgProfiles @PSBoundParameters
	}

	function Get-CurrentMgProfile {
		# Import and invoke Microsoft Graph current-profile inspection on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-CurrentMgProfile @PSBoundParameters
	}

}
#endregion


#region PSREADLINE CONFIGURATION

# Import PSReadLine module
Write-ProfileTime 'Before PSReadLine import'
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }
Write-ProfileTime 'After PSReadLine import'

# Basic PSReadLine options
Set-PSReadLineOption -EditMode Vi
Write-ProfileTime 'After Vi edit mode'
Set-PSReadLineOption -ContinuationPrompt ''

# Avoids question marks when prompt spans multiple lines
Set-PSReadLineOption -ExtraPromptLineCount 1

# PredictionViewStyle requires PSReadLine 2.1.0+ (PowerShell Core)
if ($PSVersionTable.PSEdition -eq 'Core') {
	Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
}

# Configure prediction source (edition-specific)
if ($PSVersionTable.PSEdition -eq 'Core') {
	Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
}
Write-ProfileTime 'After PSReadLine options'

# Tab completion key handlers
$tabKeyHandler = {
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
		[Microsoft.PowerShell.PSConsoleReadLine]::Complete()
	}
}
Set-PSReadLineKeyHandler -ViMode Insert  -Key Tab -ScriptBlock $tabKeyHandler
Set-PSReadLineKeyHandler -ViMode Command -Key Tab -Function Complete
Set-PSReadLineKeyHandler -ViMode Insert  -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -ViMode Command -Chord Shift+Tab -Function TabCompletePrevious

Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste

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
		Set-PSReadLineKeyHandler -Chord Shift+Enter -Function AddLine -ViMode $mode
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
Write-ProfileTime 'After PSReadLine key handlers'

#endregion

#region PROMPT HELPER FUNCTIONS

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
		$expectedProfileDirectory = Join-Path (Join-Path $HOME '.azure') 'profiles'

		# Display only directories created for named profiles under ~/.azure/profiles.
		if (
			[string]::IsNullOrWhiteSpace($profileName) -or
			[string]::IsNullOrWhiteSpace($profileDirectory) -or
			[System.IO.Path]::GetFullPath($profileDirectory).TrimEnd($trimCharacters) -ine
			[System.IO.Path]::GetFullPath($expectedProfileDirectory).TrimEnd($trimCharacters)
		) {
			return ''
		}

		return "[az:$profileName] "
	}
	catch {
		# Keep invalid profile paths from interrupting prompt rendering.
		return ''
	}
}

function Get-MgProfilePromptText {
	# Resolve the active named Microsoft Graph profile from process-local session state.
	try {
		$stateVariable = Get-Variable -Name MSCloudMgProfileName -Scope Global -ErrorAction SilentlyContinue
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
	# Resolve active Python venv label exactly as set by Activate.ps1 when present.
	$venvPrompt = $null
	$promptLabels = @()

	if (Get-Variable -Name '_PYTHON_VENV_PROMPT_PREFIX' -Scope Global -ErrorAction SilentlyContinue) {
		$venvPrompt = (Get-Variable -Name '_PYTHON_VENV_PROMPT_PREFIX' -Scope Global -ValueOnly)
	}
	elseif (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV_PROMPT)) {
		$venvPrompt = $env:VIRTUAL_ENV_PROMPT
	}
	elseif (-not [string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
		$venvPrompt = Split-Path -Path $env:VIRTUAL_ENV -Leaf
	}

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

	if (-not [string]::IsNullOrWhiteSpace($condaPrompt)) {
		$promptLabels += $condaPrompt
	}

	if ($promptLabels.Count -eq 0) {
		return ''
	}

	($promptLabels -join ' ') + ' '
}

function Test-GitDirectory {
	# Check the current directory without scanning the working tree.
	if (-not $script:GitCommandChecked) {
		$script:GitCommand = Get-Command -Name git.exe -CommandType Application -ErrorAction SilentlyContinue
		$script:GitCommandChecked = $true
	}

	if (-not $script:GitCommand) {
		return $false
	}

	try {
		$insideWorkTree = & $script:GitCommand.Path rev-parse --is-inside-work-tree 2>$null
		return $LASTEXITCODE -eq 0 -and $insideWorkTree -contains 'true'
	}
	catch {
		# Ignore errors from Git when the location is not a file-system repository.
		return $false
	}
}

function Initialize-PromptPoshGit {
	# Load Posh-Git only after entering a repository that has not been checked.
	if ($script:PoshGitLoaded -or $PSVersionTable.PSEdition -ne 'Core') {
		return
	}

	$locationPath = (Get-Location).Path
	if ($script:GitProbePath -eq $locationPath) {
		return
	}

	$script:GitProbePath = $locationPath
	if (Test-GitDirectory) {
		$script:PoshGitLoaded = Initialize-PoshGit
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

	$cacheKey = "$(Get-Location)"
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
	# Called only after the prompt has confirmed the current directory is a Git repository.

	if ($PSVersionTable.PSEdition -ne 'Core') {
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

#endregion
Write-ProfileTime 'Profile end'
