# -------------------------------------------------------------------------
# Program: Get-CurrentAzProfile.ps1
# Description: Defines the public MSCloudProfile command Get-CurrentAzProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Get-CurrentAzProfile.

function Get-CurrentAzProfile {
    <#
    .SYNOPSIS
        Shows the current Azure CLI context and profile.
    .DESCRIPTION
        Displays which Azure profile is currently active based on AZURE_CONFIG_DIR,
        and shows the current account/subscription information.
    .EXAMPLE
        Get-CurrentAzProfile
        Shows the current Azure context.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()


    # Get current CLI config directory
    $currentConfigDir = $env:AZURE_CONFIG_DIR
    if (-not $currentConfigDir) {
        $currentConfigDir = Join-Path $HOME ".azure"
    }

    # Determine profile name from config dir
    $profileName = Split-Path -Leaf $currentConfigDir
    if ($profileName -eq ".azure") {
        $profileName = "(default)"
    }

    # Try to get current Azure CLI account info
    $cliAccountInfo = $null
    try {
        $accountJson = az account show 2>$null
        if ($accountJson) {
            $cliAccountInfo = $accountJson | ConvertFrom-Json
        }
    }
    catch {
        # Not logged in or az CLI not available
    }

    # Get current Az module context info
    $moduleContext = Get-AzModuleCurrentContext

    # Determine whether CLI and Az module are aligned
    $isSynchronized = $false
    if ($cliAccountInfo -and $moduleContext.LoggedIn) {
        $isSynchronized = (
            $cliAccountInfo.tenantId -eq $moduleContext.TenantId -and
            $cliAccountInfo.id -eq $moduleContext.SubscriptionId
        )
    }

    # Return current context
    [PSCustomObject][ordered]@{
        ProfileName    = $profileName
        ConfigDir      = $currentConfigDir
        LoggedIn       = ($null -ne $cliAccountInfo)
        User           = $cliAccountInfo.user.name
        TenantId       = $cliAccountInfo.tenantId
        Subscription   = $cliAccountInfo.name
        SubscriptionId = $cliAccountInfo.id
        ContextSynchronized = $isSynchronized
        AzCliConfigDir = $currentConfigDir
        AzCliIsLoggedIn = ($null -ne $cliAccountInfo)
        AzCliLoggedIn  = ($null -ne $cliAccountInfo)
        AzCliCurrentUser = $cliAccountInfo.user.name
        AzCliUser      = $cliAccountInfo.user.name
        AzCliTenantId  = $cliAccountInfo.tenantId
        AzCliSubscription = $cliAccountInfo.name
        AzCliSubscriptionId = $cliAccountInfo.id
        HasAzModule    = $moduleContext.HasAzModule
        AzModuleLoggedIn = $moduleContext.LoggedIn
        AzModuleContextName = $moduleContext.ContextName
        AzModuleUser   = $moduleContext.Account
        AzModuleTenantId = $moduleContext.TenantId
        AzModuleSubscription = $moduleContext.Subscription
        AzModuleSubscriptionId = $moduleContext.SubscriptionId
    }
}

#endregion
