# -------------------------------------------------------------------------
# Program: ProfileConfiguration.ps1
# Description: Defines shared Personal and Work Azure profile configuration helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PRIVATE PROFILE CONFIGURATION
# Defines shared Personal and Work Azure profile configuration helpers.

function Get-AzureProfilesFromConfig {
    <#
    .SYNOPSIS
        Extracts Azure profile entries from a loaded config hashtable.
    .DESCRIPTION
        Returns profile records from top-level config keys. For backward compatibility,
        this also supports legacy configs that still nest profiles under AzureProfiles.
    .PARAMETER Config
        The loaded config hashtable from PersonalConfig.psd1 or WorkConfig.psd1.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [hashtable]$Config
    )

    $profiles = @{}
    if (-not $Config) {
        return $profiles
    }

    $profileTable = if ($Config.ContainsKey('AzureProfiles') -and $Config.AzureProfiles -is [hashtable]) {
        $Config.AzureProfiles
    }
    else {
        $Config
    }

    foreach ($entry in $profileTable.GetEnumerator()) {
        $profileName = [string]$entry.Key
        $profileValue = $entry.Value

        if (
            $profileName -ne 'AzureProfiles' -and
            $profileValue -is [hashtable] -and
            (
                $profileValue.ContainsKey('TenantId') -or
                $profileValue.ContainsKey('Account') -or
                $profileValue.ContainsKey('PrimarySub') -or
                $profileValue.ContainsKey('SubscriptionId') -or
                $profileValue.ContainsKey('Description')
            )
        ) {
            $profiles[$profileName] = $profileValue
        }
    }

    return $profiles
}

function Get-AllAzureProfileConfigs {
    <#
    .SYNOPSIS
        Returns a merged hashtable of Azure profiles from Personal and Work configs.
    .DESCRIPTION
        Combines top-level profile entries from $Personal and $Work configurations.
        Personal profiles take precedence if there's a name conflict.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $merged = @{}
    $workProfiles = Get-AzureProfilesFromConfig -Config $global:Work
    $personalProfiles = Get-AzureProfilesFromConfig -Config $global:Personal

    # Add Work profiles first (lower precedence)
    if ($workProfiles.Count -gt 0) {
        foreach ($key in $workProfiles.Keys) {
            $merged[$key] = $workProfiles[$key]
        }
    }

    # Add Personal profiles (higher precedence, overwrites Work if conflict)
    if ($personalProfiles.Count -gt 0) {
        foreach ($key in $personalProfiles.Keys) {
            $merged[$key] = $personalProfiles[$key]
        }
    }

    return $merged
}

#endregion
