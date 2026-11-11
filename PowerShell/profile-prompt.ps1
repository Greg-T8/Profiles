# ---------------------------------------------------------------------------
# Description   : Define the interactive PowerShell prompt.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region PROMPT FUNCTION
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( [az:Lab] [mg:Lab] (venv) ~/path/to/directory [git-status]
#   ╰╴>
function prompt {
	# Restore the PSReadLine Vi insert cursor after terminal applications exit.
	if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Host -NoNewline "`e[5 q"
	}
	Initialize-PromptPoshGit
	Initialize-AICommitEnvironment

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
Write-ProfileTime 'After prompt function definition'

#endregion
