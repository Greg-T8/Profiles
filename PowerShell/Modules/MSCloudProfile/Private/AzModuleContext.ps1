# -------------------------------------------------------------------------
# Program: AzModuleContext.ps1
# Description: Defines private Az PowerShell context discovery and synchronization helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PRIVATE AZ MODULE CONTEXT
# Defines private Az PowerShell context discovery and synchronization helpers.

function Get-AzModuleCurrentContext {
    <#
    .SYNOPSIS
        Gets the current Az PowerShell module context, if available.
    .DESCRIPTION
        Returns details about the current Az module context and login state.
        If Az module cmdlets are not available, HasAzModule is false.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    if (-not $getAzContextCommand) {
        return [PSCustomObject][ordered]@{
            HasAzModule     = $false
            LoggedIn        = $false
            ContextName     = $null
            Account         = $null
            TenantId        = $null
            Subscription    = $null
            SubscriptionId  = $null
        }
    }

    $currentContext = $null
    try {
        $currentContext = Get-AzContext -ErrorAction Stop
    }
    catch {
        # No active Az context
    }

    return [PSCustomObject][ordered]@{
        HasAzModule     = $true
        LoggedIn        = ($null -ne $currentContext)
        ContextName     = $currentContext.Name
        Account         = $currentContext.Account.Id
        TenantId        = $currentContext.Tenant.Id
        Subscription    = $currentContext.Subscription.Name
        SubscriptionId  = $currentContext.Subscription.Id
    }
}

function Sync-AzModuleContext {
    <#
    .SYNOPSIS
        Aligns Az PowerShell module context with the selected profile.
    .DESCRIPTION
        Selects an existing Az context when one matches the provided tenant,
        subscription, or account. If no match exists, attempts Connect-AzAccount
        to register/select a context for the same identity scope.
    .PARAMETER ProfileName
        Friendly profile name being activated.
    .PARAMETER TenantId
        Target tenant ID.
    .PARAMETER SubscriptionId
        Target subscription ID.
    .PARAMETER AccountId
        Optional account UPN/email to constrain context matching.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$AccountId
    )

    $syncOverallTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $syncStepTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $syncSlowestStepName = $null
    $syncSlowestStepMs = 0.0
    $writeSyncStepTiming = {
        param([string]$Step)
        $elapsedMs = $syncStepTimer.Elapsed.TotalMilliseconds
        if ($elapsedMs -gt $syncSlowestStepMs) {
            $syncSlowestStepMs = $elapsedMs
            $syncSlowestStepName = $Step
        }
        Write-Verbose ("Sync-AzModuleContext: {0,-35} {1,8:N1} ms (total {2,8:N1} ms)" -f $Step, $elapsedMs, $syncOverallTimer.Elapsed.TotalMilliseconds)
        $syncStepTimer.Restart()
    }

    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    $selectAzContextCommand = Get-Command -Name Select-AzContext -ErrorAction SilentlyContinue
    $connectAzAccountCommand = Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue
    & $writeSyncStepTiming "Discovered Az cmdlets"

    if (-not $getAzContextCommand -or -not $selectAzContextCommand -or -not $connectAzAccountCommand) {
        Write-Warning "Az PowerShell module is not available. Install/import Az.Accounts to enable module context switching."
        if ($syncSlowestStepName) {
            Write-Verbose ("Sync-AzModuleContext slowest step: {0} ({1:N1} ms)" -f $syncSlowestStepName, $syncSlowestStepMs)
        }
        Write-Verbose ("Sync-AzModuleContext total duration: {0:N1} ms" -f $syncOverallTimer.Elapsed.TotalMilliseconds)
        return [PSCustomObject][ordered]@{
            HasAzModule      = $false
            Switched         = $false
            ContextName      = $null
            Account          = $null
            TenantId         = $null
            Subscription     = $null
            SubscriptionId   = $null
        }
    }

    $allContexts = @()
    try {
        $allContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue)
    }
    catch {
        $allContexts = @()
    }
    & $writeSyncStepTiming "Loaded available Az contexts"

    $matchingContext = $null
    if ($allContexts.Count -gt 0) {
        $subscriptionMatches = @($allContexts | Where-Object {
            $_.Subscription -and $_.Subscription.Id -eq $SubscriptionId
        })

        if ($AccountId) {
            $subscriptionMatches = @($subscriptionMatches | Where-Object {
                $_.Account -and $_.Account.Id -eq $AccountId
            })
        }

        if ($subscriptionMatches.Count -gt 0) {
            $matchingContext = $subscriptionMatches | Where-Object {
                $_.Name -ieq $ProfileName
            } | Select-Object -First 1

            if (-not $matchingContext) {
                $matchingContext = $subscriptionMatches | Select-Object -First 1
            }
        }

        if (-not $matchingContext) {
            $tenantMatches = @($allContexts | Where-Object {
                $_.Tenant -and $_.Tenant.Id -eq $TenantId -and
                (
                    -not $AccountId -or
                    ($_.Account -and $_.Account.Id -eq $AccountId)
                )
            })

            if ($tenantMatches.Count -gt 0) {
                $matchingContext = $tenantMatches | Where-Object {
                    $_.Name -ieq $ProfileName
                } | Select-Object -First 1

                if (-not $matchingContext) {
                    $matchingContext = $tenantMatches | Select-Object -First 1
                }
            }
        }
    }
    & $writeSyncStepTiming "Matched context by subscription/tenant"

    if ($matchingContext) {
        Select-AzContext -Name $matchingContext.Name -ErrorAction Stop | Out-Null
        & $writeSyncStepTiming "Selected existing Az context"
    }
    else {
        Write-Host "Connecting Az PowerShell context for profile '$ProfileName'..." -ForegroundColor Yellow

        $connectParams = @{
            Tenant          = $TenantId
            Subscription    = $SubscriptionId
            ErrorAction     = 'Stop'
        }

        if ($AccountId) {
            $connectParams.AccountId = $AccountId
        }

        Connect-AzAccount @connectParams | Out-Null
        & $writeSyncStepTiming "Connected new Az context"
    }

    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
    & $writeSyncStepTiming "Read current Az context"
    if ($syncSlowestStepName) {
        Write-Verbose ("Sync-AzModuleContext slowest step: {0} ({1:N1} ms)" -f $syncSlowestStepName, $syncSlowestStepMs)
    }
    Write-Verbose ("Sync-AzModuleContext total duration: {0:N1} ms" -f $syncOverallTimer.Elapsed.TotalMilliseconds)

    return [PSCustomObject][ordered]@{
        HasAzModule      = $true
        Switched         = ($null -ne $currentContext)
        ContextName      = $currentContext.Name
        Account          = $currentContext.Account.Id
        TenantId         = $currentContext.Tenant.Id
        Subscription     = $currentContext.Subscription.Name
        SubscriptionId   = $currentContext.Subscription.Id
    }
}

#endregion
