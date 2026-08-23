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
        Switches the active Microsoft Graph / Entra profile.
    .DESCRIPTION
        Saves the live ~/.mg files for the previously-active profile, restores any
        cached files for the requested profile, then runs Connect-MgGraph and
        Connect-Entra against the profile's tenant. The Microsoft.Graph SDK has no
        AZURE_CONFIG_DIR equivalent, so per-profile isolation is implemented by
        copying mg.authrecord.json / mg.context.json / mg.graphoptions.json in and
        out of ~/.mg/ for each switch.
    .PARAMETER Name
        Profile name defined as a top-level key in PersonalConfig.psd1 or WorkConfig.psd1.
    .PARAMETER Scopes
        Optional delegated scopes for Connect-MgGraph. Falls back to the profile's
        MgScopes field; if neither is supplied, Connect-MgGraph uses its default scopes.
    .PARAMETER ClientId
        Optional client (application) ID for app-only auth. Falls back to MgClientId.
    .PARAMETER NoWelcome
        Suppresses the Connect-MgGraph welcome banner.
    .PARAMETER Force
        Forces disconnect/reconnect even when the live context already matches.
    .EXAMPLE
        Use-MgProfile qu
    .EXAMPLE
        ugp lab -Scopes 'User.Read.All','Group.Read.All'
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

    # Resolve profile configuration.
    $allProfiles = Get-AllAzureProfileConfigs
    if (-not $allProfiles.ContainsKey($Name)) {
        throw "Profile '$Name' not found in PersonalConfig.psd1 or WorkConfig.psd1."
    }
    $profileConfig = $allProfiles[$Name]
    & $writeStepTiming "Resolved profile config"

    if (-not $profileConfig.TenantId) {
        throw "Profile '$Name' is missing a TenantId."
    }

    # Validate Connect-MgGraph availability.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available. Install-Module Microsoft.Graph.Authentication."
    }

    # Determine effective Connect-MgGraph parameters from explicit args + config.
    $effectiveScopes = $Scopes
    if (-not $effectiveScopes -and $profileConfig.ContainsKey('MgScopes')) {
        $effectiveScopes = $profileConfig.MgScopes
    }
    $effectiveClientId = $ClientId
    if (-not $effectiveClientId -and $profileConfig.ContainsKey('MgClientId')) {
        $effectiveClientId = $profileConfig.MgClientId
    }

    # Check current live Mg context to decide whether reconnect is needed.
    $currentMg = Get-MgModuleCurrentContext
    $alreadyMatches = Resolve-MgProfileMatch -ProfileConfig $profileConfig -Context $currentMg
    & $writeStepTiming "Inspected current Mg context"

    $previousActive = Get-MgActiveProfileName

    if ($alreadyMatches -and -not $Force.IsPresent -and $previousActive -ieq $Name) {
        Write-Host "Already on Mg profile '$Name'. Use -Force to reconnect." -ForegroundColor Yellow
        if ($slowestStepName) {
            Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
        }
        Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)
        return Get-CurrentMgProfile
    }

    Write-Host "Switching to Mg profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan

    # Save the currently-live files into the previous profile's cache dir.
    if ($previousActive -and $previousActive -ne '(default)') {
        Save-MgProfileCache -ProfileName $previousActive
        & $writeStepTiming "Saved previous profile cache ($previousActive)"
    }

    # Disconnect any active session before swapping files so live state is clean.
    if ($currentMg.LoggedIn) {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
        & $writeStepTiming "Disconnected previous Mg session"
    }

    # Swap live files to the requested profile.
    Clear-MgGraphLiveCache
    $restored = Restore-MgProfileCache -ProfileName $Name
    Set-MgActiveProfileName -ProfileName $Name
    & $writeStepTiming "Restored profile cache (restored=$restored)"

    # Build Connect-MgGraph parameter set.
    $connectParams = @{
        TenantId    = $profileConfig.TenantId
        ErrorAction = 'Stop'
    }
    if ($effectiveScopes)   { $connectParams.Scopes   = $effectiveScopes }
    if ($effectiveClientId) { $connectParams.ClientId = $effectiveClientId }
    if ($NoWelcome.IsPresent) { $connectParams.NoWelcome = $true }

    try {
        Connect-MgGraph @connectParams | Out-Null
        & $writeStepTiming "Connected Microsoft.Graph"
    }
    catch {
        Write-Error "Connect-MgGraph failed for profile '$Name': $_"
        throw
    }

    # Connect Microsoft.Entra against the same tenant (optional module).
    $connectEntraCommand = Get-Command -Name Connect-Entra -ErrorAction SilentlyContinue
    if ($connectEntraCommand) {
        $entraParams = @{
            TenantId    = $profileConfig.TenantId
            ErrorAction = 'Stop'
        }
        if ($effectiveScopes)   { $entraParams.Scopes   = $effectiveScopes }
        if ($effectiveClientId) { $entraParams.ClientId = $effectiveClientId }
        if ($NoWelcome.IsPresent) { $entraParams.NoWelcome = $true }

        try {
            Connect-Entra @entraParams | Out-Null
            & $writeStepTiming "Connected Microsoft.Entra"
        }
        catch {
            Write-Warning "Connect-Entra failed for profile '$Name': $_"
        }
    }
    else {
        Write-Warning "Microsoft.Entra module not found. Install-Module Microsoft.Entra to enable Entra cmdlets."
    }

    # Capture refreshed live files for this profile.
    Save-MgProfileCache -ProfileName $Name
    & $writeStepTiming "Saved refreshed profile cache"

    if ($slowestStepName) {
        Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
    }
    Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

    Get-CurrentMgProfile
}

#endregion
