# -------------------------------------------------------------------------
# Program: Use-AzProfileSubscription.ps1
# Description: Defines the public MSCloudProfile command Use-AzProfileSubscription.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Use-AzProfileSubscription.

function Use-AzProfileSubscription {
    <#
    .SYNOPSIS
        Switches the active Azure subscription for the current profile.
    .DESCRIPTION
        Changes the active Azure CLI subscription in the current AZURE_CONFIG_DIR
        context without modifying configured profile defaults in PersonalConfig
        or WorkConfig.
    .PARAMETER SubscriptionID
        Subscription ID or subscription name.
    .EXAMPLE
        Use-AzProfileSubscription -SubscriptionID '00000000-0000-0000-0000-000000000000'
        Switches the current profile/session to the specified subscription.
    .EXAMPLE
        Use-AzProfileSubscription -SubscriptionID 'Contoso-Prod'
        Switches the current profile/session to a subscription by name.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Subscription')]
        [string]$SubscriptionID
    )


    $accountInfo = $null
    try {
        $accountJson = az account show -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $accountJson) {
            $accountInfo = $accountJson | ConvertFrom-Json
        }
    }
    catch {
        $accountInfo = $null
    }

    if (-not $accountInfo) {
        Write-Error "Not logged in to Azure CLI for the current profile. Run 'Use-AzProfile <name>' or 'az login' first."
        return
    }

    $setOutput = az account set --subscription $SubscriptionID 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($setOutput | Out-String).Trim()
        if ($details) {
            Write-Error "Could not switch to subscription '$SubscriptionID'. $details"
        }
        else {
            Write-Error "Could not switch to subscription '$SubscriptionID'."
        }
        return
    }

    $updatedAccountInfo = $null
    try {
        $updatedAccountJson = az account show -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $updatedAccountJson) {
            $updatedAccountInfo = $updatedAccountJson | ConvertFrom-Json
        }
    }
    catch {
        $updatedAccountInfo = $null
    }

    if (-not $updatedAccountInfo) {
        Write-Error "Subscription switched, but current account context could not be read."
        return
    }

    $profileName = (Get-CurrentAzProfile).ProfileName
    $accountId = if ($updatedAccountInfo.user) { $updatedAccountInfo.user.name } else { $null }
    $azModuleContext = Sync-AzModuleContext -ProfileName $profileName -TenantId $updatedAccountInfo.tenantId -SubscriptionId $updatedAccountInfo.id -AccountId $accountId

    if ($azModuleContext.HasAzModule -and $azModuleContext.SubscriptionId -ne $updatedAccountInfo.id) {
        $setAzContextCommand = Get-Command -Name Set-AzContext -ErrorAction SilentlyContinue

        if ($setAzContextCommand) {
            try {
                $setAzContextParams = @{
                    Subscription = $updatedAccountInfo.id
                    Tenant = $updatedAccountInfo.tenantId
                    ErrorAction = 'Stop'
                }

                $supportsAccountId = $setAzContextCommand.Parameters.ContainsKey('AccountId')
                if ($accountId -and $supportsAccountId) {
                    $setAzContextParams.AccountId = $accountId
                }

                Set-AzContext @setAzContextParams | Out-Null
            }
            catch {
                Write-Warning "Failed to set Az module context to subscription '$($updatedAccountInfo.id)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Az PowerShell module is available but Set-AzContext was not found."
        }

        $azModuleContext = Get-AzModuleCurrentContext
        if ($azModuleContext.LoggedIn -and $azModuleContext.SubscriptionId -ne $updatedAccountInfo.id) {
            Write-Warning "Az module context is still on subscription '$($azModuleContext.SubscriptionId)' while Azure CLI is on '$($updatedAccountInfo.id)'."
        }
    }

    [PSCustomObject][ordered]@{
        AzCliIsLoggedIn = $true
        AzCliUser = $updatedAccountInfo.user.name
        AzCliTenantId = $updatedAccountInfo.tenantId
        AzCliSubscription = $updatedAccountInfo.name
        AzCliSubscriptionId = $updatedAccountInfo.id
        HasAzModule = $azModuleContext.HasAzModule
        AzModuleContextName = $azModuleContext.ContextName
        AzModuleUser = $azModuleContext.Account
        AzModuleTenantId = $azModuleContext.TenantId
        AzModuleSubscription = $azModuleContext.Subscription
        AzModuleSubscriptionId = $azModuleContext.SubscriptionId
    }
}

#endregion
