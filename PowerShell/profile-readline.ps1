# ---------------------------------------------------------------------------
# Description   : Configure interactive line editing and fuzzy finding.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region PSREADLINE CONFIGURATION

# Determine whether this process will present an interactive PowerShell prompt.
$profileStartupArguments = [Environment]::GetCommandLineArgs()
$profileHasNoExitArgument = [bool]($profileStartupArguments -match '^(?i)-NoExit$')
$profileHasNonInteractiveArgument = [bool]($profileStartupArguments -match '^(?i)-NonInteractive$')
$profileHasCommandArgument = [bool]($profileStartupArguments -match '^(?i)-(?:Command|CommandWithArgs|EncodedCommand|File)$')
$profileShouldConfigurePSReadLine = $Host.Name -eq 'ConsoleHost' -and
    -not [Console]::IsInputRedirected -and
    -not $profileHasNonInteractiveArgument -and
    (-not $profileHasCommandArgument -or $profileHasNoExitArgument)

# Configure line editing only when this process will present an interactive prompt.
if ($profileShouldConfigurePSReadLine) {

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
			[Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
		}
	}
	Set-PSReadLineKeyHandler -ViMode Insert  -Key Tab -ScriptBlock $tabKeyHandler
	Set-PSReadLineKeyHandler -ViMode Command -Key Tab -Function MenuComplete
	Set-PSReadLineKeyHandler -ViMode Insert  -Chord Shift+Tab -Function TabCompletePrevious
	Set-PSReadLineKeyHandler -ViMode Command -Chord Shift+Tab -Function TabCompletePrevious

	Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste

	# Use the arrow keys to choose a completion and Enter to accept it.
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

	# Load PSFzf after Vi mode and custom key handlers are configured.
	Write-ProfileTime 'Before PSFzf import'
	Import-Module PSFzf
	Write-ProfileTime 'After PSFzf import'
	Set-PsFzfOption `
		-PSReadlineChordProvider 'Ctrl+t' `
		-PSReadlineChordReverseHistory 'Ctrl+r'
	Write-ProfileTime 'After PSFzf configuration'
}
else {
    # Avoid loading interactive editing modules for command-only PowerShell processes.
    Write-ProfileTime 'Skipped PSReadLine and PSFzf for non-interactive session'
}
#endregion
