# ---------------------------------------------------------------------------
# Description   : Initialize optional Herdr client integration.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region HERDR CLIENT INTEGRATION
# Load the client integration only when the current PowerShell edition supports it.
Write-ProfileTime 'Before Herdr integration'
if ($script:HerdrIntegrationEnabled -and $PSVersionTable.PSEdition -eq 'Core' -and $IsWindows) {
	$herdrModulePath = [System.IO.Path]::Combine([string[]]@($profileDir, 'HerdrClient.psm1'))

	# Leave the existing profile available if the helper is not installed.
	if ([IO.File]::Exists($herdrModulePath)) {
		try {
			Write-ProfileTime 'Before Herdr module import'
			Import-Module $herdrModulePath -ErrorAction Stop
			Write-ProfileTime 'After Herdr module import'

			# Identify interactive shells and recognized Herdr pane startup.
			$herdrArgs = [Environment]::GetCommandLineArgs()
			$herdrInteractive = [Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost' -and
				-not [Console]::IsInputRedirected -and -not (Test-HerdrNonInteractiveArgument -Arguments $herdrArgs)
			$herdrCommand = Test-HerdrCommandArgument -Arguments $herdrArgs
			$herdrNoExit = [bool]($herdrArgs -match '^(?i)-noexit$')
			$herdrManagedStartup = $herdrNoExit -and [bool]($herdrArgs -match '(?i)^\s*if\s*\(\s*\$null\s+-eq\s+\$global:__HerdrOriginalPrompt\s*\)')

			# Initialize trusted projects inside managed interactive panes.
			if ($herdrInteractive -and $env:HERDR_ENV -eq '1' -and
				(-not $herdrCommand -or $herdrManagedStartup) -and -not $global:HerdrProjectProfileLoaded) {
				# Load the approved project script in this shell's persistent scope.
				$global:HerdrProjectProfileLoaded = $true
				$herdrProjectScript = Get-HerdrTrustedProjectProfile
				if ($herdrProjectScript) {
					. $herdrProjectScript
				}
			}

			# Attach eligible outer consoles after their startup commands complete.
			elseif ($env:WT_SESSION -and $env:TERM_PROGRAM -ne 'vscode' -and (Test-HerdrAutostartEligibility)) {
				if ($env:TERM_PROGRAM -eq 'vscode' -and $env:VSCODE_INJECTION -eq '1' -and $herdrCommand) {
					# Wait until VS Code's injected shell integration has finished.
					$global:HerdrOriginalPrompt = $function:prompt
					$global:HerdrAttachPending = $true

					# Preserve the prompt while deferring attachment until its first invocation.
					function global:prompt {
						# Attach once and then preserve the original prompt.
						if ($global:HerdrAttachPending) {
							$global:HerdrAttachPending = $false
							if (Test-HerdrAutostartEligibility) {
								Start-HerdrClient
							}
						}

						# Render the original prompt after the one-time attachment.
						& $global:HerdrOriginalPrompt
					}
				}

				# Attach directly when no injected startup command needs to finish.
				else {
					Start-HerdrClient
				}
			}
		}

		# Keep the PowerShell prompt usable if integration initialization fails.
		catch {
			Write-Warning "Herdr profile: $($_.Exception.Message)"
		}
	}
}
#endregion
Write-ProfileTime 'After Herdr integration'
