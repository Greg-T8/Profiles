# -------------------------------------------------------------------------
# Program: Use-MgProfile.ps1
# Description: Defines the public MSCloudProfile command Use-MgProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Use-MgProfile.

function Use-MgProfile {
    <#
    .SYNOPSIS
        Switches the active Microsoft Graph profile.
    .DESCRIPTION
        Connects Microsoft Graph profiles with a persistent CurrentUser context so
        WAM/MSAL can silently reuse cached credentials. The configured account is
        passed as a login hint, and the resulting account and tenant are validated
        before the prompt is updated. Use default or (default) to activate the
        reserved default profile without displaying an Mg prompt moniker.
    .PARAMETER Name
        Profile name defined in PersonalConfig.psd1 or WorkConfig.psd1, or default.
    .PARAMETER Scopes
        Optional delegated scopes. Falls back to MgScopes or cached profile metadata.
    .PARAMETER ClientId
        Optional public-client application ID. Falls back to MgClientId or cached metadata.
    .PARAMETER LoginHint
        Optional account hint. Falls back to the profile's configured or cached Account.
    .PARAMETER NoWelcome
        Suppresses the Connect-MgGraph welcome banner.
    .PARAMETER Force
        Re-runs Connect-MgGraph even when the current live context already matches.
        This does not sign out or clear the shared WAM/MSAL token cache.
    .EXAMPLE
        Use-MgProfile qu
    .EXAMPLE
        ugp lab -Scopes 'User.Read.All','Group.Read.All'
    .EXAMPLE
        ugp default
        Activates the persistent default profile without displaying an Mg moniker.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string[]]$Scopes,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$LoginHint,

        [Parameter()]
        [switch]$NoWelcome,

        [Parameter()]
        [switch]$Force
    )

    $overallTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $stepTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $slowestStepName = $null
    $slowestStepMs = 0.0
    $writeStepTiming = {
        param([string]$Step)

        $elapsedMs = $stepTimer.Elapsed.TotalMilliseconds
        if ($elapsedMs -gt $slowestStepMs) {
            $slowestStepMs = $elapsedMs
            $slowestStepName = $Step
        }

        Write-Verbose ("{0,-50} {1,8:N1} ms (total {2,8:N1} ms)" -f $Step, $elapsedMs, $overallTimer.Elapsed.TotalMilliseconds)
        $stepTimer.Restart()
    }

    # Require persistent context support and account-targeting support when a hint is available.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available. Install-Module Microsoft.Graph.Authentication."
    }
    if (-not $connectMgCommand.Parameters.ContainsKey('ContextScope')) {
        throw "Connect-MgGraph does not support ContextScope. Upgrade Microsoft.Graph.Authentication."
    }

    $supportsLoginHint = $connectMgCommand.Parameters.ContainsKey('LoginHint')
    $normalizedName = if ($Name -ieq '(default)' -or $Name -ieq 'default') { 'default' } else { $Name }
    $isDefaultProfile = $normalizedName -ieq 'default'
    $allProfiles = Get-AllAzureProfileConfigs
    $currentMg = Get-MgModuleCurrentContext
    $activeName = Get-MgActiveProfileName
    $defaultContext = Get-MgProfileCachedContext -ProfileName 'default'
    & $writeStepTiming "Loaded Graph profile state"

    # Capture an existing unlabelled CurrentUser context as default only when it is not a configured named identity.
    if (-not $defaultContext -and $currentMg.LoggedIn -and $activeName -ieq 'default') {
        $matchesNamedProfile = $false
        foreach ($configuredProfile in $allProfiles.Values) {
            if (Resolve-MgProfileMatch -ProfileConfig $configuredProfile -Context $currentMg) {
                $matchesNamedProfile = $true
                break
            }
        }

        if (-not $matchesNamedProfile) {
            Save-MgProfileContext -ProfileName 'default' -Context $currentMg -Description 'Default Microsoft Graph profile'
            $defaultContext = Get-MgProfileCachedContext -ProfileName 'default'
            & $writeStepTiming "Captured existing default Graph context"
        }
    }

    # Resolve the requested profile into a common routing contract.
    if ($isDefaultProfile) {
        if (-not $defaultContext -and $currentMg.LoggedIn) {
            throw "The default Mg profile is not initialized. Run New-MgProfile -Name default -TenantId <tenant-id> -Account <account>."
        }

        $targetTenantId = if ($defaultContext) { [string]$defaultContext.TenantId } else { $null }
        $targetAccount = if ($LoginHint) { $LoginHint } elseif ($defaultContext) { [string]$defaultContext.Account } else { $null }
        $effectiveScopes = if ($Scopes) { $Scopes } elseif ($defaultContext) { @($defaultContext.Scopes) } else { $null }
        $effectiveClientId = if ($ClientId) { $ClientId } elseif ($defaultContext) { [string]$defaultContext.ClientId } else { $null }
        $profileDescription = if ($defaultContext -and $defaultContext.Description) {
            [string]$defaultContext.Description
        }
        else {
            'Default Microsoft Graph profile'
        }
    }
    else {
        if (-not $allProfiles.ContainsKey($normalizedName)) {
            throw "Profile '$normalizedName' not found in PersonalConfig.psd1 or WorkConfig.psd1."
        }

        $profileConfig = $allProfiles[$normalizedName]
        if (-not $profileConfig.TenantId) {
            throw "Profile '$normalizedName' is missing a TenantId."
        }

        $targetTenantId = [string]$profileConfig.TenantId
        $targetAccount = if ($LoginHint) { $LoginHint } else { [string]$profileConfig.Account }
        $effectiveScopes = if ($Scopes) {
            $Scopes
        }
        elseif ($profileConfig.ContainsKey('MgScopes')) {
            $profileConfig.MgScopes
        }
        else {
            $null
        }
        $effectiveClientId = if ($ClientId) {
            $ClientId
        }
        elseif ($profileConfig.ContainsKey('MgClientId')) {
            $profileConfig.MgClientId
        }
        else {
            $null
        }
        $profileDescription = [string]$profileConfig.Description
    }
    & $writeStepTiming "Resolved requested Graph profile"

    # Require LoginHint support whenever the profile identifies a specific delegated account.
    if ($targetAccount -and -not $supportsLoginHint) {
        throw "Connect-MgGraph does not support LoginHint. Upgrade Microsoft.Graph.Authentication to 2.39.0 or later."
    }

    # Reuse a matching persistent live context unless the caller requested a reconnect.
    $targetProfileConfig = @{
        TenantId = $targetTenantId
        Account  = $targetAccount
    }
    if ($effectiveClientId) {
        $targetProfileConfig.MgClientId = $effectiveClientId
    }

    $alreadyMatches = (
        $targetTenantId -and
        (Resolve-MgProfileMatch -ProfileConfig $targetProfileConfig -Context $currentMg) -and
        [string]$currentMg.ContextScope -ieq 'CurrentUser'
    )
    if ($alreadyMatches -and $activeName -ieq $normalizedName -and -not $Force.IsPresent) {
        Write-Host "Already on Mg profile '$normalizedName'. Use -Force to reconnect." -ForegroundColor Yellow
        return Get-CurrentMgProfile
    }

    Write-Host "Switching to Mg profile: " -NoNewline
    Write-Host $normalizedName -ForegroundColor Cyan

    # Clear the prompt marker until the requested cached connection is validated.
    Set-MgActiveProfileName -ProfileName 'default'

    # Connect directly without Disconnect-MgGraph so the shared persistent token cache survives.
    $connectParams = @{
        ContextScope = 'CurrentUser'
        ErrorAction  = 'Stop'
    }
    if ($targetTenantId) { $connectParams.TenantId = $targetTenantId }
    if ($effectiveScopes) { $connectParams.Scopes = $effectiveScopes }
    if ($effectiveClientId) { $connectParams.ClientId = $effectiveClientId }
    if ($targetAccount) { $connectParams.LoginHint = $targetAccount }
    if ($NoWelcome.IsPresent) { $connectParams.NoWelcome = $true }

    try {
        Connect-MgGraph @connectParams | Out-Null
        & $writeStepTiming "Connected Microsoft Graph with persistent cache"

        $connectedContext = Get-MgModuleCurrentContext
        if (-not $connectedContext.LoggedIn) {
            throw "Connect-MgGraph returned without a live context."
        }
        if ($targetTenantId -and $connectedContext.TenantId -ne $targetTenantId) {
            throw "Tenant mismatch. Expected '$targetTenantId', connected '$($connectedContext.TenantId)'."
        }
        if ($targetAccount -and $connectedContext.Account -ine $targetAccount) {
            throw "Account mismatch. Expected '$targetAccount', connected '$($connectedContext.Account)'."
        }

        Save-MgProfileContext -ProfileName $normalizedName -Context $connectedContext -Description $profileDescription
        Set-MgActiveProfileName -ProfileName $normalizedName
        & $writeStepTiming "Validated and saved Graph profile metadata"
    }
    catch {
        Write-Error "Connect-MgGraph failed for profile '$normalizedName': $_"
        throw
    }

    if ($slowestStepName) {
        Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
    }
    Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

    Get-CurrentMgProfile
}

#endregion
