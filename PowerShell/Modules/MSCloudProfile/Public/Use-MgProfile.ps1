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
        Connects named profiles with process-scoped Microsoft.Graph and Microsoft.Entra
        contexts so they do not replace the persistent CurrentUser context. Use
        '(default)' to return to the CurrentUser context. Named-profile state exists
        only in the current PowerShell process.
    .PARAMETER Name
        Profile name defined as a top-level key in PersonalConfig.psd1 or WorkConfig.psd1,
        or '(default)' for the persistent CurrentUser context.
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
    .EXAMPLE
        ugp default
        Returns to the persistent CurrentUser Microsoft Graph / Entra context.
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

    # Require Graph SDK support for process-scoped named contexts.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available. Install-Module Microsoft.Graph.Authentication."
    }
    if (-not $connectMgCommand.Parameters.ContainsKey('ContextScope')) {
        throw "Connect-MgGraph does not support ContextScope. Upgrade Microsoft.Graph.Authentication."
    }

    # Use Entra only when its installed command also supports context isolation.
    $connectEntraCommand = Get-Command -Name Connect-Entra -ErrorAction SilentlyContinue
    if ($connectEntraCommand -and -not $connectEntraCommand.Parameters.ContainsKey('ContextScope')) {
        Write-Warning "Connect-Entra does not support ContextScope. Upgrade Microsoft.Entra.Authentication."
        $connectEntraCommand = $null
    }

    # Handle the persistent CurrentUser context separately from configured named profiles.
    $isDefaultProfile = $Name -ieq '(default)' -or $Name -ieq 'default'
    if ($isDefaultProfile) {
        $currentMg = Get-MgModuleCurrentContext
        $currentEntra = Get-EntraModuleCurrentContext
        $activeName = Get-MgActiveProfileName
        $mgIsDefault = $currentMg.LoggedIn -and [string]$currentMg.ContextScope -ieq 'CurrentUser'
        $entraIsDefault = (
            -not $connectEntraCommand -or
            ($currentEntra.LoggedIn -and [string]$currentEntra.ContextScope -ieq 'CurrentUser')
        )
        & $writeStepTiming "Inspected current default contexts"

        # Reuse an already-active CurrentUser context unless reconnection was requested.
        if ($activeName -ieq '(default)' -and $mgIsDefault -and $entraIsDefault -and -not $Force.IsPresent) {
            Write-Host "Already on Mg profile '(default)'. Use -Force to reconnect." -ForegroundColor Yellow
            return Get-CurrentMgProfile
        }

        Write-Host "Switching to Mg profile: " -NoNewline
        Write-Host "(default)" -ForegroundColor Cyan

        # Disconnect the current process contexts before restoring CurrentUser contexts.
        if (
            $currentMg.LoggedIn -and
            ([string]$currentMg.ContextScope -ieq 'Process' -or $Force.IsPresent)
        ) {
            try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
            & $writeStepTiming "Disconnected previous Mg session"
        }
        if (
            $currentEntra.LoggedIn -and
            ([string]$currentEntra.ContextScope -ieq 'Process' -or $Force.IsPresent)
        ) {
            $disconnectEntraCommand = Get-Command -Name Disconnect-Entra -ErrorAction SilentlyContinue
            if ($disconnectEntraCommand) {
                try { Disconnect-Entra -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-Entra failed: $_" }
                & $writeStepTiming "Disconnected previous Entra session"
            }
        }
        Set-MgActiveProfileName -ProfileName '(default)'

        # Reconnect the persistent Microsoft.Graph CurrentUser context.
        $connectParams = @{
            ContextScope = 'CurrentUser'
            ErrorAction  = 'Stop'
        }
        if ($Scopes) { $connectParams.Scopes = $Scopes }
        if ($ClientId) { $connectParams.ClientId = $ClientId }
        if ($NoWelcome.IsPresent) { $connectParams.NoWelcome = $true }

        try {
            Connect-MgGraph @connectParams | Out-Null
            & $writeStepTiming "Connected default Microsoft.Graph context"
        }
        catch {
            Write-Error "Connect-MgGraph failed for profile '(default)': $_"
            throw
        }

        # Reconnect the optional Microsoft.Entra CurrentUser context.
        if ($connectEntraCommand) {
            $entraParams = @{
                ContextScope = 'CurrentUser'
                ErrorAction  = 'Stop'
            }
            if ($Scopes) { $entraParams.Scopes = $Scopes }
            if ($ClientId) { $entraParams.ClientId = $ClientId }
            if ($NoWelcome.IsPresent) { $entraParams.NoWelcome = $true }

            try {
                Connect-Entra @entraParams | Out-Null
                & $writeStepTiming "Connected default Microsoft.Entra context"
            }
            catch {
                Write-Warning "Connect-Entra failed for profile '(default)': $_"
            }
        }
        else {
            Write-Warning "Microsoft.Entra module not found. Install-Module Microsoft.Entra to enable Entra cmdlets."
        }

        if ($slowestStepName) {
            Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
        }
        Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)
        return Get-CurrentMgProfile
    }

    # Resolve named profile configuration.
    $allProfiles = Get-AllAzureProfileConfigs
    if (-not $allProfiles.ContainsKey($Name)) {
        throw "Profile '$Name' not found in PersonalConfig.psd1 or WorkConfig.psd1."
    }
    $profileConfig = $allProfiles[$Name]
    & $writeStepTiming "Resolved profile config"

    if (-not $profileConfig.TenantId) {
        throw "Profile '$Name' is missing a TenantId."
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
    $currentEntra = Get-EntraModuleCurrentContext
    $alreadyMatches = (
        (Resolve-MgProfileMatch -ProfileConfig $profileConfig -Context $currentMg) -and
        [string]$currentMg.ContextScope -ieq 'Process'
    )
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

    # Disconnect active process contexts before connecting the requested profile.
    if ($currentMg.LoggedIn -and [string]$currentMg.ContextScope -ieq 'Process') {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
        & $writeStepTiming "Disconnected previous Mg session"
    }
    if ($currentEntra.LoggedIn -and [string]$currentEntra.ContextScope -ieq 'Process') {
        $disconnectEntraCommand = Get-Command -Name Disconnect-Entra -ErrorAction SilentlyContinue
        if ($disconnectEntraCommand) {
            try { Disconnect-Entra -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-Entra failed: $_" }
            & $writeStepTiming "Disconnected previous Entra session"
        }
    }

    # Clear the marker until the requested Graph connection succeeds.
    Set-MgActiveProfileName -ProfileName '(default)'

    # Build Connect-MgGraph parameter set.
    $connectParams = @{
        TenantId     = $profileConfig.TenantId
        ContextScope = 'Process'
        ErrorAction  = 'Stop'
    }
    if ($effectiveScopes)   { $connectParams.Scopes   = $effectiveScopes }
    if ($effectiveClientId) { $connectParams.ClientId = $effectiveClientId }
    if ($NoWelcome.IsPresent) { $connectParams.NoWelcome = $true }

    try {
        Connect-MgGraph @connectParams | Out-Null
        Set-MgActiveProfileName -ProfileName $Name
        & $writeStepTiming "Connected Microsoft.Graph"
    }
    catch {
        Write-Error "Connect-MgGraph failed for profile '$Name': $_"
        throw
    }

    # Connect Microsoft.Entra against the same tenant (optional module).
    if ($connectEntraCommand) {
        $entraParams = @{
            TenantId     = $profileConfig.TenantId
            ContextScope = 'Process'
            ErrorAction  = 'Stop'
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

    if ($slowestStepName) {
        Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
    }
    Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

    Get-CurrentMgProfile
}

#endregion
