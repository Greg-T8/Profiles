# ---------------------------------------------------------------------------
# Description   : Configure interactive line editing and fuzzy finding.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Write Vi cursor sequences without loading Utility.
#   2026-11-11 - Trace Utility module state around initial cursor output.
#   2026-11-11 - Trace Vi cursor handler setup and initial cursor output.
#   2026-11-11 - Add checkpoints within PSReadLine key setup.
#   2026-11-11 - Defer PSFzf loading until a shortcut is used.
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
	Write-ProfileTime 'After Tab handler definition'
	Set-PSReadLineKeyHandler -ViMode Insert  -Key Tab -ScriptBlock $tabKeyHandler
	Write-ProfileTime 'After first PSReadLine key handler'
	Set-PSReadLineKeyHandler -ViMode Command -Key Tab -Function MenuComplete
	Set-PSReadLineKeyHandler -ViMode Insert  -Chord Shift+Tab -Function TabCompletePrevious
	Set-PSReadLineKeyHandler -ViMode Command -Chord Shift+Tab -Function TabCompletePrevious
	Write-ProfileTime 'After Tab key handlers'

	Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste

	# Use the arrow keys to choose a completion and Enter to accept it.
	Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine

	# Prediction navigation (PowerShell Core with newer PSReadLine)
	Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardWord
	if ($PSVersionTable.PSEdition -eq 'Core') {
		Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function AcceptSuggestion -ErrorAction SilentlyContinue
	}
	Write-ProfileTime 'After general and prediction key handlers'

	# Vi mode configuration
	if ((Get-PSReadLineOption).EditMode -eq 'Vi') {
		Set-PSReadLineOption -ViModeIndicator 'Cursor'
		$env:EDITOR = 'nvim'
		Write-ProfileTime 'After Vi mode option and editor setting'

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
			Write-ProfileTime "After Vi $mode key handlers"
		}

		# Custom cursor styles (PowerShell Core only - uses VT100 escape sequences)
		if ($PSVersionTable.PSEdition -eq 'Core') {
			Write-ProfileTime 'Before Vi cursor handler definition'
			function OnViModeChange {
				if ($args[0] -eq 'Command') {
					# Set the cursor to a blinking block
					$Host.UI.Write("`e[1 q")
				}
				else {
					# Set the cursor to a blinking line
					$Host.UI.Write("`e[5 q")
				}
			}
			Write-ProfileTime 'After Vi cursor handler definition'
			Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange
			Write-ProfileTime 'After Vi cursor handler registration'

			# Set initial cursor to blinking line for Insert mode
			Write-ProfileTime 'Before initial Vi cursor output'
			if ($env:PROFILE_TIMING) {
				Write-ProfileTime ('Before initial Vi cursor write (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
			}
			$Host.UI.Write("`e[5 q")
			Write-ProfileTime 'After Vi cursor configuration'
			if ($env:PROFILE_TIMING) {
				Write-ProfileTime ('After initial Vi cursor write (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
			}
		}

	}
	Write-ProfileTime 'After PSReadLine key handlers'

    # Load and configure PSFzf in the session when a deferred shortcut is used.
    $script:ProfilePSFzfInitialized = $false
    function Initialize-ProfilePSFzf {
        # Initialize once and expose the module commands to the session.
        if (-not $script:ProfilePSFzfInitialized) {
            Import-Module PSFzf -Global -ErrorAction Stop
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
            $script:ProfilePSFzfInitialized = $true
        }
    }

    # Register the configured shortcuts in both Vi modes without importing PSFzf.
    Write-ProfileTime 'Before deferred PSFzf shortcut registration'
    $profileFzfProvider = { Initialize-ProfilePSFzf; Invoke-FzfPsReadlineHandlerProvider }
    $profileFzfHistory = { Initialize-ProfilePSFzf; Invoke-FzfPsReadlineHandlerHistory }
    foreach ($mode in 'Insert', 'Command') {
        Set-PSReadLineKeyHandler -ViMode $mode -Chord 'Ctrl+t' -ScriptBlock $profileFzfProvider
        Set-PSReadLineKeyHandler -ViMode $mode -Chord 'Ctrl+r' -ScriptBlock $profileFzfHistory
    }

    # Preserve PSFzf's optional shortcuts only when their keys are unbound.
    $profileFzfOptional = @(
        @{ Chord = 'Alt+c'; Handler = { Initialize-ProfilePSFzf; Invoke-FzfPsReadlineHandlerSetLocation } }
        @{ Chord = 'Alt+a'; Handler = { Initialize-ProfilePSFzf; Invoke-FzfPsReadlineHandlerHistoryArgs } }
    )
    foreach ($shortcut in $profileFzfOptional) {
        $boundHandler = Get-PSReadLineKeyHandler -Bound | Where-Object { $_.Key -eq $shortcut.Chord }
        if (-not $boundHandler) {
            foreach ($mode in 'Insert', 'Command') {
                Set-PSReadLineKeyHandler -ViMode $mode -Chord $shortcut.Chord -ScriptBlock $shortcut.Handler
            }
        }
    }
    Write-ProfileTime 'After deferred PSFzf shortcut registration'
}
else {
    # Avoid loading interactive editing modules for command-only PowerShell processes.
    Write-ProfileTime 'Skipped PSReadLine and PSFzf for non-interactive session'
}
#endregion
