<#
.SYNOPSIS
Attaches interactive PowerShell consoles to existing Herdr workspaces.

.DESCRIPTION
Checks the current session snapshot before attachment and resolves explicitly
trusted project initialization for PowerShell processes running inside Herdr.

.CONTEXT
Personal Windows PowerShell profile integration with Herdr.

.AUTHOR
Greg Tate

.NOTES
Program: HerdrClient.psm1
#>

#region HOST ELIGIBILITY
# Restrict automatic attachment to supported interactive console sessions.
function Test-HerdrCommandArgument {
    # Recognize PowerShell startup-command switches, including abbreviations.
    param([string[]]$Arguments)

    # Check each switch against the supported command-bearing parameters.
    foreach ($argument in $Arguments) {
        $option = $argument.ToLowerInvariant()
        if ($option.Length -lt 2 -or -not $option.StartsWith('-')) {
            continue
        }

        # Include valid abbreviated forms of each parameter name.
        foreach ($name in @('-command', '-commandwithargs', '-file', '-encodedcommand')) {
            if ($name.StartsWith($option)) {
                return $true
            }
        }
    }

    # Treat all other arguments as safe for this particular check.
    return $false
}

function Test-HerdrNonInteractiveArgument {
    # Recognize abbreviated NonInteractive switches used by automation.
    param([string[]]$Arguments)

    # Match any supported abbreviation of the noninteractive switch.
    foreach ($argument in $Arguments) {
        $option = $argument.ToLowerInvariant()
        if ($option.Length -ge 4 -and '-noninteractive'.StartsWith($option)) {
            return $true
        }
    }

    # Leave other arguments to the remaining eligibility checks.
    return $false
}

function Test-HerdrAutostartEligibility {
    # Identify an interactive host without intercepting scripts or nested panes.
    [CmdletBinding()]
    param([switch]$Explicit)

    # Exclude unsupported hosts, noninteractive processes, and managed panes.
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7 -or $Host.Name -ne 'ConsoleHost' -or
        -not [Environment]::UserInteractive -or [Console]::IsInputRedirected -or $env:HERDR_ENV -eq '1') {
        return $false
    }
    if (-not $Explicit -and $env:HERDR_AUTOSTART -eq '0') {
        return $false
    }
    if ($env:TERM_PROGRAM -ne 'vscode' -and -not $env:WT_SESSION) {
        return $false
    }

    # Distinguish ordinary terminals from automation and explicit launchers.
    $arguments = [Environment]::GetCommandLineArgs()
    if (Test-HerdrNonInteractiveArgument -Arguments $arguments) {
        return $false
    }
    if ($Explicit) {
        return [bool]($arguments -match '^(?i)-noexit$')
    }
    $hasCommand = Test-HerdrCommandArgument -Arguments $arguments
    if (-not $hasCommand) {
        return $true
    }

    # Permit only the recognized VS Code integration command at startup.
    return $env:TERM_PROGRAM -eq 'vscode' -and $env:VSCODE_INJECTION -eq '1' -and
        [bool]($arguments -match '^(?i)-noexit$') -and
        [bool]($arguments -match '(?i)^try\s*\{\s*\.\s*"[^"]+[\\/]shellIntegration\.ps1"\s*\}\s*catch\s*\{\s*\}\s*$')
}
#endregion

#region SERVER SNAPSHOT AND ATTACHMENT
# Never attach without an authoritative, nonempty live workspace snapshot.
function Get-HerdrWorkspaceCount {
    # Return the workspace count or the specific stopped-server state.
    [CmdletBinding()]
    param()

    # Query the selected session and retain native-command output and status.
    $client = Get-Command herdr.exe -CommandType Application -ErrorAction Stop
    $prefix = if ($env:HERDR_SESSION -and $env:HERDR_SESSION -ne 'default') { @('--session', $env:HERDR_SESSION) } else { @() }
    $previousPreference = $ErrorActionPreference

    # Restore the caller's error preference even if the native command fails.
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $client.Source @prefix api snapshot 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }

    # Decode the snapshot and preserve actionable server errors.
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    try { $response = ConvertFrom-Json -InputObject $text -AsHashtable -ErrorAction Stop }
    catch { throw "Herdr snapshot could not be read: $text" }
    if ($exitCode -ne 0) {
        if ($response.error.code -eq 'server_not_running') {
            return [pscustomobject]@{ Status = 'Stopped'; Count = $null }
        }
        throw "Herdr snapshot failed: $($response.error.message)"
    }

    # Reject incomplete snapshots instead of assuming a workspace count.
    if ($response -isnot [System.Collections.IDictionary] -or $response.result -isnot [System.Collections.IDictionary] -or
        $response.result.snapshot -isnot [System.Collections.IDictionary] -or
        $response.result.snapshot.workspaces -isnot [array]) {
        throw 'Herdr returned an invalid workspace snapshot.'
    }

    # Return a count only after validating the workspace collection.
    return [pscustomobject]@{
        Status        = 'Ready'
        Count         = $response.result.snapshot.workspaces.Count
        FocusedPaneId = $response.result.snapshot.focused_pane_id
    }
}

function Get-HerdrLocationCommand {
    # Construct a literal PowerShell directory change for the existing pane.
    param([Parameter(Mandatory)] [string]$Directory)

    # Reject unavailable paths and escape embedded single quotes.
    if (-not [IO.Directory]::Exists($Directory)) {
        throw "The VS Code terminal directory is unavailable: $Directory"
    }
    $escapedDirectory = $Directory.Replace("'", "''")
    return "Set-Location -LiteralPath '$escapedDirectory'"
}

function Set-HerdrWorkspaceLocation {
    # Send the VS Code terminal directory to the existing focused pane.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PaneId,
        [Parameter(Mandatory)] [string]$Directory
    )

    # Prepare a literal command and select the same session used for the snapshot.
    $command = Get-HerdrLocationCommand -Directory $Directory
    $client = Get-Command herdr.exe -CommandType Application -ErrorAction Stop
    $prefix = if ($env:HERDR_SESSION -and $env:HERDR_SESSION -ne 'default') { @('--session', $env:HERDR_SESSION) } else { @() }

    # Submit the command and verify that Herdr accepted the input.
    $output = @(& $client.Source @prefix pane run $PaneId $command 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) {
        throw "Could not send the VS Code directory to the Herdr pane: $text"
    }
}

function Start-HerdrClient {
    # Restore a stopped server, verify its workspace count, and attach once.
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Explicit, [switch]$NoAttach)

    # Prevent recursive attachment and skip unsupported automatic launches.
    if ($env:HERDR_ENV -eq '1' -or $script:HerdrClientRunning) {
        return
    }
    if (-not $NoAttach -and -not (Test-HerdrAutostartEligibility -Explicit:$Explicit)) {
        return
    }
    $script:HerdrClientRunning = $true

    # Verify server state before starting a client or restoring a session.
    try {
        $state = Get-HerdrWorkspaceCount
        if (-not $PSCmdlet.ShouldProcess('Current Herdr session', 'Start server if needed and attach if workspaces exist')) {
            return $state
        }

        # Start a stopped server headlessly and wait for its restored snapshot.
        if ($state.Status -eq 'Stopped') {
            # A headless server restores saved workspaces without opening the TUI.
            $client = Get-Command herdr.exe -CommandType Application -ErrorAction Stop
            $serverArgs = if ($env:HERDR_SESSION -and $env:HERDR_SESSION -ne 'default') { @('--session', $env:HERDR_SESSION, 'server') } else { @('server') }
            Start-Process -FilePath $client.Source -ArgumentList $serverArgs -WindowStyle Hidden | Out-Null

            # Bound the wait so a failed server leaves PowerShell responsive.
            for ($attempt = 0; $attempt -lt 50; $attempt++) {
                Start-Sleep -Milliseconds 100
                $state = Get-HerdrWorkspaceCount
                if ($state.Status -eq 'Ready') {
                    break
                }
            }
            if ($state.Status -ne 'Ready') {
                throw 'The Herdr server did not become ready.'
            }
        }

        # Leave empty or unknown sessions at the existing PowerShell prompt.
        if ($state.Status -ne 'Ready' -or $null -eq $state.Count) {
            throw 'Herdr workspace state is unknown.'
        }
        if ($state.Count -eq 0) {
            Write-Verbose 'Herdr has no workspaces; remaining at the PowerShell prompt.'
            if ($NoAttach) {
                return $state
            }
            return
        }

        # Set the existing pane to the VS Code terminal's initial filesystem directory.
        if (-not $NoAttach -and $env:TERM_PROGRAM -eq 'vscode') {
            $location = Get-Location
            if ($location.Provider.Name -ne 'FileSystem' -or -not $state.FocusedPaneId) {
                throw 'The VS Code terminal directory or current Herdr pane is unavailable.'
            }
            Set-HerdrWorkspaceLocation -PaneId $state.FocusedPaneId -Directory $location.ProviderPath
        }

        # Inherit the console handles so the interactive client can render and accept input.
        if (-not $NoAttach) {
            $client = Get-Command herdr.exe -CommandType Application -ErrorAction Stop
            if ($env:HERDR_SESSION -and $env:HERDR_SESSION -ne 'default') {
                Start-Process -FilePath $client.Source -ArgumentList @('--session', $env:HERDR_SESSION) -NoNewWindow -Wait
            }
            else {
                Start-Process -FilePath $client.Source -NoNewWindow -Wait
            }
        }

        # Return the verified state only when attachment was explicitly skipped.
        if ($NoAttach) {
            return $state
        }
    }

    # Fail open and clear the process-local reentrancy guard.
    catch {
        Write-Warning "Herdr client: $($_.Exception.Message)"
    }
    finally {
        $script:HerdrClientRunning = $false
    }
}
#endregion

#region TRUSTED PROJECT INITIALIZATION
# Use an explicit allowlist; workspace identity and project paths are unrelated.
function Get-HerdrTrustedProjectProfile {
    # Resolve the approved ALZ loader only when the pane starts under ALZ.
    [CmdletBinding()]
    param()

    # Require a managed pane at a filesystem location.
    if ($env:HERDR_ENV -ne '1' -or (Get-Location).Provider.Name -ne 'FileSystem') {
        return
    }

    # Check the trusted root using case-insensitive directory boundaries.
    $root = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'LocalCode/Lab/ALZ')).TrimEnd('\', '/')
    $current = [IO.Path]::GetFullPath((Get-Location).ProviderPath).TrimEnd('\', '/')
    if (-not $current.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
        -not $current.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    # Return the approved initializer or warn when it is unavailable.
    $profilePath = Join-Path $root '.assets/LoadWorkspaceProfile.ps1'
    if ([IO.File]::Exists($profilePath)) {
        return $profilePath
    }
    Write-Warning "Trusted Herdr project profile is unavailable: $profilePath"
}
#endregion

Export-ModuleMember -Function Test-HerdrCommandArgument, Test-HerdrNonInteractiveArgument, Test-HerdrAutostartEligibility, Get-HerdrWorkspaceCount, Start-HerdrClient, Get-HerdrTrustedProjectProfile
