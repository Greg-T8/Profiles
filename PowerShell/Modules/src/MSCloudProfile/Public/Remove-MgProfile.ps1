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
        Removes Microsoft Graph profile metadata and optionally its config entry.
    .DESCRIPTION
        Deletes non-secret metadata under ~/.mg/profiles/<name>/ and, unless
        KeepConfig is specified, removes matching in-memory Personal and Work entries.
        The config psd1 files and shared WAM/MSAL credential cache are not modified.
        Removing the reserved default profile resets its metadata but does not remove
        default from profile discovery.
    .PARAMETER Name
        Profile name to remove or reset.
    .PARAMETER KeepConfig
        Leaves the in-memory config entries intact.
    .PARAMETER KeepCache
        Leaves the on-disk ~/.mg/profiles/<name>/ directory intact.
    .EXAMPLE
        Remove-MgProfile lab
    .EXAMPLE
        Remove-MgProfile default
        Resets the captured default-profile metadata without signing out.
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

    $normalizedName = if ($Name -ieq '(default)' -or $Name -ieq 'default') { 'default' } else { $Name }
    $activeName = Get-MgActiveProfileName

    # Move an active named profile to default without clearing the shared credential cache.
    if ($normalizedName -ne 'default' -and $normalizedName -ieq $activeName) {
        if (-not $PSCmdlet.ShouldProcess("active Mg profile '$normalizedName'", 'Switch to default profile')) {
            return
        }

        Use-MgProfile -Name default -NoWelcome | Out-Null
    }

    # Remove the profile metadata directory unless explicitly preserved.
    if (-not $KeepCache.IsPresent) {
        $cacheDir = Get-MgGraphProfileDir -ProfileName $normalizedName
        if (Test-Path -LiteralPath $cacheDir) {
            if ($PSCmdlet.ShouldProcess($cacheDir, 'Remove profile metadata directory')) {
                Remove-Item -LiteralPath $cacheDir -Recurse -Force
                Write-Host "Removed profile metadata: $cacheDir" -ForegroundColor Green
            }
        }
    }

    # Remove named profiles from loaded configuration without editing their source files.
    if (-not $KeepConfig.IsPresent -and $normalizedName -ne 'default') {
        $removed = $false
        foreach ($varName in @('Personal', 'Work')) {
            $configVar = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
            if ($configVar -and $configVar.Value -is [hashtable] -and $configVar.Value.ContainsKey($normalizedName)) {
                if ($PSCmdlet.ShouldProcess("`$$varName[$normalizedName]", 'Remove in-memory profile entry')) {
                    $configVar.Value.Remove($normalizedName)
                    Write-Host "Removed in-memory entry: `$$varName[$normalizedName]" -ForegroundColor Green
                    $removed = $true
                }
            }
        }

        if (-not $removed) {
            Write-Host "Profile '$normalizedName' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completion for the reserved default and all configured or cached profiles.
$mgProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $results = @(
        [System.Management.Automation.CompletionResult]::new(
            'default',
            'default',
            'ParameterValue',
            'Default Microsoft Graph profile'
        )
    )
    $allProfiles = Get-AllAzureProfileConfigs

    # Add configured named profiles without shadowing the reserved default.
    if ($allProfiles.Count -gt 0) {
        $results += $allProfiles.Keys |
            Where-Object { $_ -ine 'default' -and $_ -like "$wordToComplete*" } |
            ForEach-Object {
                $description = $allProfiles[$_].Description
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
            }
    }

    # Add disk-only profile metadata directories without duplicating known names.
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ine 'default' -and
                $_.Name -like "$wordToComplete*" -and
                -not $allProfiles.ContainsKey($_.Name)
            } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    'ParameterValue',
                    'Disk-only Mg profile metadata'
                )
            }
    }

    $results | Where-Object { $_.CompletionText -like "$wordToComplete*" }
}

Register-ArgumentCompleter -CommandName Use-MgProfile, ugp -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName Remove-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName New-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter

#endregion
