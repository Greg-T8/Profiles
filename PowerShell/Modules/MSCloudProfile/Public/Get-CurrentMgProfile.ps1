# -------------------------------------------------------------------------
# Program: Get-CurrentMgProfile.ps1
# Description: Defines the public MSCloudProfile command Get-CurrentMgProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Get-CurrentMgProfile.

function Get-CurrentMgProfile {
    <#
    .SYNOPSIS
        Shows the currently active Microsoft Graph / Entra profile and live context.
    .DESCRIPTION
        Reports the active profile name (tracked under ~/.mg/profiles/.active) and
        the live Microsoft.Graph and Microsoft.Entra contexts, if those modules are
        loaded and connected.
    .EXAMPLE
        Get-CurrentMgProfile
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()


    # Resolve names and gather live contexts from each SDK.
    $activeName   = Get-MgActiveProfileName
    $mgContext    = Get-MgModuleCurrentContext
    $entraContext = Get-EntraModuleCurrentContext

    [PSCustomObject][ordered]@{
        ProfileName        = $activeName
        HasMgModule        = $mgContext.HasMgModule
        MgLoggedIn         = $mgContext.LoggedIn
        MgAccount          = $mgContext.Account
        MgTenantId         = $mgContext.TenantId
        MgClientId         = $mgContext.ClientId
        MgScopes           = $mgContext.Scopes
        MgAuthType         = $mgContext.AuthType
        HasEntraModule     = $entraContext.HasEntraModule
        EntraLoggedIn      = $entraContext.LoggedIn
        EntraAccount       = $entraContext.Account
        EntraTenantId      = $entraContext.TenantId
        EntraClientId      = $entraContext.ClientId
        ContextSynchronized = (
            $mgContext.LoggedIn -and $entraContext.LoggedIn -and
            $mgContext.TenantId -eq $entraContext.TenantId
        )
    }
}

#endregion
