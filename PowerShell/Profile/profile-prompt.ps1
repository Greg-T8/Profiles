# ---------------------------------------------------------------------------
# Description   : Define the interactive PowerShell prompt.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Share the Git worktree check during each prompt.
#   2026-11-11 - Pass first prompt timing into Python label diagnostics.
#   2026-11-11 - Avoid module imports for cursor output and debug detection.
#   2026-11-11 - Pass first prompt timing into Posh-Git diagnostics.
#   2026-11-11 - Add first prompt calculation timing checkpoints.
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region PROMPT FUNCTION
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( [az:Lab] [mg:Lab] (venv) ~/path/to/directory [git-status]
#   ╰╴>
# Track prompt diagnostics once per profile load when timing is enabled.
$script:ProfilePromptTimingRecorded = $false
function prompt {
	# Limit prompt checkpoints to the first calculation in a timing session.
	$tracePrompt = [bool]$env:PROFILE_TIMING -and -not $script:ProfilePromptTimingRecorded
	if ($tracePrompt) {
		$script:ProfilePromptTimingRecorded = $true
		Write-ProfileTime 'First prompt: start'
	}
	# Restore the PSReadLine Vi insert cursor after terminal applications exit.
	if ($PSVersionTable.PSEdition -eq 'Core') {
        $Host.UI.Write("`e[5 q")
	}
	if ($tracePrompt) { Write-ProfileTime 'First prompt: after cursor restore' }
	$promptGitProbe = @{}
	Initialize-PromptPoshGit -TraceTiming:$tracePrompt -ProbeCache $promptGitProbe
	if ($tracePrompt) { Write-ProfileTime 'First prompt: after Posh-Git initialization' }
	Initialize-AICommitEnvironment -TraceTiming:$tracePrompt -ProbeCache $promptGitProbe
	if ($tracePrompt) { Write-ProfileTime 'First prompt: after AI commit initialization' }

	$pythonVenvPromptText = Get-PythonVenvPromptText -TraceTiming:$tracePrompt
	if ($tracePrompt) { Write-ProfileTime 'First prompt: after Python environment label' }

	# Use different prompt styles based on PowerShell edition
	if ($PSVersionTable.PSEdition -eq 'Core') {
		# PowerShell Core with ANSI escape codes
		$ESC = [char]0x1b                                            # ESC character for ANSI sequences
		$azProfilePromptText = Get-AzProfilePromptText
		if ($tracePrompt) { Write-ProfileTime 'First prompt: after Azure profile label' }
		$mgProfilePromptText = Get-MgProfilePromptText
		if ($tracePrompt) { Write-ProfileTime 'First prompt: after Graph profile label' }
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
		"$azProfilePromptStyledText$mgProfilePromptStyledText$pythonVenvPromptStyledText$(if ($tracePrompt) { Write-ProfileTime 'First prompt: before path' }; Get-MyPromptPath; if ($tracePrompt) { Write-ProfileTime 'First prompt: after path' })" + # Display optional context labels and shortened path
		"$ESC[22m" +                                                 # Reset dim/faint mode
		"$(if ($tracePrompt) { Write-ProfileTime 'First prompt: before Git status' }; if ($script:PoshGitLoaded) { "$(Get-GitPromptStatusText)" }; if ($tracePrompt) { Write-ProfileTime 'First prompt: after Git status' })" +   # Git status if in git repo
		"$ESC[23m" +                                                 # Reset italic mode
		"`n" +                                                       # New line
		"$ESC[38;2;0;179;226m" +                                     # Set foreground color to cyan RGB(0,179,226)
		'╰╴' +                                                       # Box drawing characters
		"$ESC[0m" +                                                  # Reset all ANSI formatting
		$(if ($null -ne $ExecutionContext.SessionState.PSVariable.Get('PSDebugContext')) { '[DBG]: ' } else { '' }) +  # Debug indicator
		'> '                                                         # Prompt character
	}
	else {
		# Windows PowerShell 5.1 - Cannot use ANSI, build prompt string
		"`n" +                                                       # New line
		'╭─( ' +                                                     # Box drawing characters and opening parenthesis
		"$(if ($tracePrompt) { Write-ProfileTime 'First prompt: before path' }; Get-MyPromptPath; if ($tracePrompt) { Write-ProfileTime 'First prompt: after path' })" + # Display shortened path
		"`n" +                                                       # New line
		'╰╴' +                                                       # Box drawing characters
		$(if ($null -ne $ExecutionContext.SessionState.PSVariable.Get('PSDebugContext')) { '[DBG]: ' } else { '' }) +  # Debug indicator
		'> '                                                         # Prompt character
	}
}
Write-ProfileTime 'After prompt function definition'

#endregion
