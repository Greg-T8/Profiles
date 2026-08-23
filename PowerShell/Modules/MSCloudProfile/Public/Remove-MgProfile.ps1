# -------------------------------------------------------------------------
# Program: Remove-MgProfile.ps1
# Description: Defines the public MSCloudProfile command Remove-MgProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Remove-MgProfile.

function Remove-MgProfile {
    <#
    .SYNOPSIS
        Removes a Microsoft Graph / Entra profile cache and optionally its config entry.
    .DESCRIPTION
        Deletes the on-disk cache directory under ~/.mg/profiles/<name>/ and, unless
        -KeepConfig is specified, removes the matching in-memory entries from
        $Personal and $Work. The config psd1 files are NOT edited (matching the
        behavior of Remove-AzProfile). If the profile is currently active, the live
        Mg/Entra sessions are disconnected first.
    .PARAMETER Name
        Profile name to remove.
    .PARAMETER KeepConfig
        Leaves the in-memory config entries intact.
    .PARAMETER KeepCache
        Leaves the on-disk ~/.mg/profiles/<name>/ directory intact.
    .EXAMPLE
        Remove-MgProfile lab
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig,

        [Parameter()]
        [switch]$KeepCache
    )


    $activeName = Get-MgActiveProfileName

    # If the target is the active profile, disconnect live sessions first.
    if ($Name -ieq $activeName) {
        if (-not $PSCmdlet.ShouldProcess("active Mg/Entra session for '$Name'", 'Disconnect')) { return }

        $disconnectMgCommand = Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue
        if ($disconnectMgCommand) {
            try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
        }

        $disconnectEntraCommand = Get-Command -Name Disconnect-Entra -ErrorAction SilentlyContinue
        if ($disconnectEntraCommand) {
            try { Disconnect-Entra -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-Entra failed: $_" }
        }

        Clear-MgGraphLiveCache
        Set-MgActiveProfileName -ProfileName '(default)'
    }

    # Remove on-disk cache directory unless told otherwise.
    if (-not $KeepCache.IsPresent) {
        $cacheDir = Get-MgGraphProfileDir -ProfileName $Name
        if (Test-Path -LiteralPath $cacheDir) {
            if ($PSCmdlet.ShouldProcess($cacheDir, 'Remove profile cache directory')) {
                Remove-Item -LiteralPath $cacheDir -Recurse -Force
                Write-Host "Removed cache: $cacheDir" -ForegroundColor Green
            }
        }
    }

    # Remove from in-memory configs unless told otherwise.
    if (-not $KeepConfig.IsPresent) {
        $removed = $false
        foreach ($varName in @('Personal','Work')) {
            $configVar = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
            if ($configVar -and $configVar.Value -is [hashtable] -and $configVar.Value.ContainsKey($Name)) {
                if ($PSCmdlet.ShouldProcess("`$$varName[$Name]", 'Remove in-memory profile entry')) {
                    $configVar.Value.Remove($Name)
                    Write-Host "Removed in-memory entry: `$$varName[$Name]" -ForegroundColor Green
                    $removed = $true
                }
            }
        }
        if (-not $removed) {
            Write-Host "Profile '$Name' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completer for Mg profile names (shared across commands).
$mgProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)


    $results = @()

    $allProfiles = Get-AllAzureProfileConfigs
    if ($allProfiles.Count -gt 0) {
        $results += $allProfiles.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $description = $allProfiles[$_].Description
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
        }
    }

    # Also include disk-only profiles for completion.
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" -and -not $allProfiles.ContainsKey($_.Name) } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', 'Disk-only Mg profile cache')
            }
    }

    $results
}

Register-ArgumentCompleter -CommandName Use-MgProfile, ugp -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName Remove-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName New-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter

#endregion
