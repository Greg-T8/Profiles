# -------------------------------------------------------------------------
# Program: Get-MgProfiles.ps1
# Description: Defines the public MSCloudProfile command Get-MgProfiles.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Get-MgProfiles.

function Get-MgProfiles {
    <#
    .SYNOPSIS
        Lists Microsoft Graph / Entra profiles from configs and from the on-disk profile cache.
    .DESCRIPTION
        Returns one record per known profile, combining entries from PersonalConfig.psd1,
        WorkConfig.psd1, and any cached profile directories under ~/.mg/profiles/.
        ConfigSource is one of: PersonalConfig, WorkConfig, Both, DiskOnly.
    .EXAMPLE
        Get-MgProfiles
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()


    # Pull entries from each loaded config and tag their source.
    $personalProfiles = Get-AzureProfilesFromConfig -Config $global:Personal
    $workProfiles     = Get-AzureProfilesFromConfig -Config $global:Work

    $combined = @{}

    foreach ($entry in $personalProfiles.GetEnumerator()) {
        $combined[$entry.Key] = @{ Config = $entry.Value; Source = 'PersonalConfig' }
    }

    foreach ($entry in $workProfiles.GetEnumerator()) {
        if ($combined.ContainsKey($entry.Key)) {
            $combined[$entry.Key].Source = 'Both'
        }
        else {
            $combined[$entry.Key] = @{ Config = $entry.Value; Source = 'WorkConfig' }
        }
    }

    # Add disk-only profiles (directories without a matching config entry).
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $combined.ContainsKey($_.Name)) {
                $combined[$_.Name] = @{ Config = $null; Source = 'DiskOnly' }
            }
        }
    }

    $activeName = Get-MgActiveProfileName

    # Project to output records sorted by name.
    $combined.Keys | Sort-Object | ForEach-Object {
        $name   = $_
        $entry  = $combined[$name]
        $cfg    = $entry.Config
        $cached = Get-MgProfileCachedContext -ProfileName $name

        [PSCustomObject][ordered]@{
            Name         = $name
            IsActive     = ($name -ieq $activeName)
            ConfigSource = $entry.Source
            Account      = if ($cfg) { $cfg.Account } else { $cached.Account }
            TenantId     = if ($cfg) { $cfg.TenantId } else { $cached.TenantId }
            MgClientId   = if ($cfg -and $cfg.ContainsKey('MgClientId')) { $cfg.MgClientId } else { $cached.ClientId }
            MgScopes     = if ($cfg -and $cfg.ContainsKey('MgScopes')) { $cfg.MgScopes } else { $cached.Scopes }
            Description  = if ($cfg) { $cfg.Description } else { $null }
            HasCache     = ($null -ne $cached)
        }
    }
}

#endregion
