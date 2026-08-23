# -------------------------------------------------------------------------
# Program: MgModuleContext.ps1
# Description: Defines private Microsoft Graph and Entra context discovery and matching helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PRIVATE MG MODULE CONTEXT
# Defines private Microsoft Graph and Entra context discovery and matching helpers.

function Get-MgModuleCurrentContext {
    # Returns the live Microsoft.Graph context (or a stub if the module is missing).
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $cmd = Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject][ordered]@{
            HasMgModule  = $false
            LoggedIn     = $false
            TenantId     = $null
            Account      = $null
            ClientId     = $null
            Scopes       = $null
            AuthType     = $null
            ContextScope = $null
        }
    }

    $ctx = $null
    try { $ctx = Get-MgContext -ErrorAction Stop } catch { Write-Verbose "Get-MgContext failed: $_" }

    [PSCustomObject][ordered]@{
        HasMgModule  = $true
        LoggedIn     = ($null -ne $ctx)
        TenantId     = $ctx.TenantId
        Account      = $ctx.Account
        ClientId     = $ctx.ClientId
        Scopes       = $ctx.Scopes
        AuthType     = $ctx.AuthType
        ContextScope = $ctx.ContextScope
    }
}

function Get-EntraModuleCurrentContext {
    # Returns the live Microsoft.Entra context (or a stub if the module is missing).
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $cmd = Get-Command -Name Get-EntraContext -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject][ordered]@{
            HasEntraModule = $false
            LoggedIn       = $false
            TenantId       = $null
            Account        = $null
            ClientId       = $null
            Scopes         = $null
        }
    }

    $ctx = $null
    try { $ctx = Get-EntraContext -ErrorAction Stop } catch { Write-Verbose "Get-EntraContext failed: $_" }

    [PSCustomObject][ordered]@{
        HasEntraModule = $true
        LoggedIn       = ($null -ne $ctx)
        TenantId       = $ctx.TenantId
        Account        = $ctx.Account
        ClientId       = $ctx.ClientId
        Scopes         = $ctx.Scopes
    }
}

function Resolve-MgProfileMatch {
    # Returns $true if the live context matches the profile's tenant + account (or tenant + clientId for AppOnly).
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][hashtable]$ProfileConfig,
        [Parameter(Mandatory)][PSCustomObject]$Context
    )

    if (-not $Context.LoggedIn) { return $false }
    if (-not $ProfileConfig.TenantId) { return $false }
    if ($Context.TenantId -ne $ProfileConfig.TenantId) { return $false }

    if ($ProfileConfig.ContainsKey('MgClientId') -and $ProfileConfig.MgClientId) {
        return ($Context.ClientId -eq $ProfileConfig.MgClientId)
    }

    if ($ProfileConfig.ContainsKey('Account') -and $ProfileConfig.Account -and $Context.Account) {
        return ($Context.Account -ieq $ProfileConfig.Account)
    }

    return $true
}

#endregion
