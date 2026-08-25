# -------------------------------------------------------------------------
# Program: MSCloudProfile.psm1
# Description: Bundled MSCloudProfile implementation for faster profile import.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region MODULE CONTENTS
# Configuration paths and imported data remain private module state.
$script:ConfigurationSources = [ordered]@{
    Personal = [ordered]@{
        Name         = 'Personal'
        Path         = $null
        Exists       = $false
        Loaded       = $false
        Config       = @{}
        ProfileCount = 0
        Precedence   = 1
    }
    Work = [ordered]@{
        Name         = 'Work'
        Path         = $null
        Exists       = $false
        Loaded       = $false
        Config       = @{}
        ProfileCount = 0
        Precedence   = 2
    }
}
# Public commands follow the manifest order; private helpers follow.

#region PUBLIC FUNCTIONS
# Public commands are ordered to match FunctionsToExport in the module manifest.

function Use-AzProfile {
    <#
    .SYNOPSIS
        Switches to a specified Azure CLI profile.
    .DESCRIPTION
        Sets AZURE_CONFIG_DIR to isolate the Azure CLI context for a specific
        account/tenant combination. Logs in if not already authenticated for
        that profile.
    .PARAMETER Name
        The profile name as defined as a top-level key in PersonalConfig.psd1 or WorkConfig.psd1,
        or '(default)' for the default Azure CLI profile.
    .PARAMETER Force
        Forces re-authentication even if already logged in.
    .PARAMETER SelectAccount
        Prompts for account selection during login (useful for MFA/CA).
    .EXAMPLE
        Use-AzProfile '(default)'
        Switches to the default Azure profile.
    .EXAMPLE
        Use-AzProfile lab
        Switches to the lab profile.
    .EXAMPLE
        Use-AzProfile qu -Force
        Forces re-authentication to the Quisitive profile.
    .EXAMPLE
        uap lab
        Uses the alias to quickly switch profiles.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SelectAccount
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

    # Handle default profile specially
    if ($Name -eq '(default)' -or $Name -eq 'default') {
        # Set to default Azure config directory
        $configDir = Join-Path $HOME ".azure"
        $env:AZURE_CONFIG_DIR = $configDir
        & $writeStepTiming "Set AZURE_CONFIG_DIR for default profile"

        Write-Host "Switching to profile: " -NoNewline
        Write-Host "(default)" -ForegroundColor Cyan -NoNewline
        Write-Host " (Default Azure CLI profile)"

        # Check if we need to login
        $accountInfo = $null
        $needsLogin = $Force.IsPresent

        if (-not $needsLogin) {
            try {
                $accountJson = az account show -o json 2>$null
                if ($LASTEXITCODE -eq 0 -and $accountJson) {
                    $accountInfo = $accountJson | ConvertFrom-Json
                }
                else {
                    $needsLogin = $true
                }
            }
            catch {
                $needsLogin = $true
            }
        }
        & $writeStepTiming "Checked existing Azure CLI login"

        # Perform login if needed
        if ($needsLogin) {
            Write-Host "Logging in..." -ForegroundColor Yellow

            $loginArgs = @('login')

            # Add account selection prompt if requested
            if ($SelectAccount.IsPresent) {
                $loginArgs += '--prompt'
                $loginArgs += 'select_account'
            }

            az @loginArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Error "Login failed for default profile"
                return
            }

            & $writeStepTiming "Completed Azure CLI login"
        }

        # Show current context
        if (-not $accountInfo) {
            $accountInfo = az account show -o json 2>$null | ConvertFrom-Json
            & $writeStepTiming "Retrieved Azure CLI account context"
        }

        # Sync Az module context to match CLI profile context
        $azModuleContext = $null
        if ($accountInfo) {
            $azModuleContext = Sync-AzModuleContext -ProfileName '(default)' -TenantId $accountInfo.tenantId -SubscriptionId $accountInfo.id -AccountId $accountInfo.user.name
        }
        & $writeStepTiming "Synchronized Az PowerShell module context"

        if ($slowestStepName) {
            Write-Verbose ("Use-AzProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
        }
        Write-Verbose ("Use-AzProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

        # Return context info
        return [PSCustomObject][ordered]@{
            AzCliIsLoggedIn = ($null -ne $accountInfo)
            AzCliUser      = $accountInfo.user.name
            AzCliTenantId  = $accountInfo.tenantId
            AzCliSubscription = $accountInfo.name
            AzCliSubscriptionId = $accountInfo.id
            HasAzModule    = $azModuleContext.HasAzModule
            AzModuleContextName = $azModuleContext.ContextName
            AzModuleUser   = $azModuleContext.Account
            AzModuleTenantId = $azModuleContext.TenantId
            AzModuleSubscription = $azModuleContext.Subscription
            AzModuleSubscriptionId = $azModuleContext.SubscriptionId
        }
    }

    # Get all configured profiles from Personal and Work configs
    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    & $writeStepTiming "Loaded and merged profile configuration"

    if ($allConfiguredProfiles.Count -eq 0) {
        Write-Error "No Azure profiles configured. Add profile keys to PersonalConfig.psd1 or WorkConfig.psd1"
        return
    }

    # Get the profile configuration
    $profileConfig = $allConfiguredProfiles[$Name]
    & $writeStepTiming "Resolved requested profile configuration"

    if (-not $profileConfig) {
        $availableProfiles = $allConfiguredProfiles.Keys -join ', '
        Write-Error "Profile '$Name' not found. Available profiles: $availableProfiles"
        return
    }

    $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }

    # Set the config directory for this profile
    $configDir = Join-Path $HOME ".azure\profiles\$Name"
    $env:AZURE_CONFIG_DIR = $configDir
    & $writeStepTiming "Set AZURE_CONFIG_DIR for named profile"

    Write-Host "Switching to profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan -NoNewline
    Write-Host " ($($profileConfig.Description))"

    # Check if we need to login
    $accountInfo = $null
    $needsLogin = $Force.IsPresent

    if (-not $needsLogin) {
        try {
            $accountJson = az account show -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and $accountJson) {
                $accountInfo = $accountJson | ConvertFrom-Json
            }
            else {
                $needsLogin = $true
            }
        }
        catch {
            $needsLogin = $true
        }
    }
    & $writeStepTiming "Checked existing Azure CLI login"

    # Perform login if needed
    if ($needsLogin) {
        Write-Host "Logging in to tenant: $($profileConfig.TenantId)" -ForegroundColor Yellow

        $loginArgs = @('login', '--tenant', $profileConfig.TenantId)

        # Add account selection prompt if requested
        if ($SelectAccount.IsPresent) {
            $loginArgs += '--prompt'
            $loginArgs += 'select_account'
        }

        az @loginArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Login failed for profile '$Name'"
            return
        }

        & $writeStepTiming "Completed Azure CLI login"
    }

    # Set subscription if configured
    $shouldRefreshAccountInfo = $false

    if ($configuredPrimarySub) {
        if (-not $accountInfo -or $accountInfo.id -ne $configuredPrimarySub) {
            az account set --subscription $configuredPrimarySub 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not set subscription: $configuredPrimarySub"
            }

            & $writeStepTiming "Set Azure CLI subscription"
            $shouldRefreshAccountInfo = $true
        }
        else {
            Write-Verbose "Azure CLI subscription already matches target; skipping account set"
        }
    }

    # Show current context
    if (-not $accountInfo -or $shouldRefreshAccountInfo) {
        $accountInfo = az account show -o json 2>$null | ConvertFrom-Json
        & $writeStepTiming "Retrieved Azure CLI account context"
    }

    # Validate we're in the expected tenant
    if ($accountInfo.tenantId -ne $profileConfig.TenantId) {
        Write-Warning "Tenant mismatch! Expected: $($profileConfig.TenantId), Got: $($accountInfo.tenantId)"
    }

    # Sync Az module context to match CLI profile context
    $azModuleContext = Sync-AzModuleContext -ProfileName $Name -TenantId $accountInfo.tenantId -SubscriptionId $accountInfo.id -AccountId $accountInfo.user.name
    & $writeStepTiming "Synchronized Az PowerShell module context"

    if ($slowestStepName) {
        Write-Verbose ("Use-AzProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
    }
    Write-Verbose ("Use-AzProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

    # Return context info
    [PSCustomObject][ordered]@{
        AzCliIsLoggedIn = ($null -ne $accountInfo)
        AzCliUser      = $accountInfo.user.name
        AzCliTenantId  = $accountInfo.tenantId
        AzCliSubscription = $accountInfo.name
        AzCliSubscriptionId = $accountInfo.id
        HasAzModule    = $azModuleContext.HasAzModule
        AzModuleContextName = $azModuleContext.ContextName
        AzModuleUser   = $azModuleContext.Account
        AzModuleTenantId = $azModuleContext.TenantId
        AzModuleSubscription = $azModuleContext.Subscription
        AzModuleSubscriptionId = $azModuleContext.SubscriptionId
    }
}

# Register argument completer for Use-AzProfile profile names (for both function and alias)
$azProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)


    # Add default profile first
    $results = @([System.Management.Automation.CompletionResult]::new(
        '(default)',
        '(default)',
        'ParameterValue',
        'Default Azure CLI profile'
    ))

    # Add configured profiles
    $allProfiles = Get-AllAzureProfileConfigs
    if ($allProfiles.Count -gt 0) {
        $results += $allProfiles.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $description = $allProfiles[$_].Description
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
        }
    }

    # Filter by word to complete and return
    $results | Where-Object { $_.CompletionText -like "$wordToComplete*" }
}

Register-ArgumentCompleter -CommandName Use-AzProfile, uap -ParameterName Name -ScriptBlock $azProfileCompleter



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
    $result = [PSCustomObject][ordered]@{
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

    $result.PSObject.TypeNames.Insert(0, 'MSCloudProfile.CurrentAzProfile')
    $result
}



function Get-CurrentMgProfile {
    <#
    .SYNOPSIS
        Shows the currently active Microsoft Graph / Entra profile and live context.
    .DESCRIPTION
        Reports the process-local active profile name and the live Microsoft.Graph
        and Microsoft.Entra contexts, if those modules are loaded and connected.
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

    $result = [PSCustomObject][ordered]@{
        ProfileName        = $activeName
        HasMgModule        = $mgContext.HasMgModule
        MgLoggedIn         = $mgContext.LoggedIn
        MgAccount          = $mgContext.Account
        MgTenantId         = $mgContext.TenantId
        MgClientId         = $mgContext.ClientId
        MgScopes           = $mgContext.Scopes
        MgAuthType         = $mgContext.AuthType
        MgContextScope     = $mgContext.ContextScope
        HasEntraModule     = $entraContext.HasEntraModule
        EntraLoggedIn      = $entraContext.LoggedIn
        EntraAccount       = $entraContext.Account
        EntraTenantId      = $entraContext.TenantId
        EntraClientId      = $entraContext.ClientId
        EntraContextScope  = $entraContext.ContextScope
        ContextSynchronized = (
            $mgContext.LoggedIn -and $entraContext.LoggedIn -and
            $mgContext.TenantId -eq $entraContext.TenantId
        )
    }

    $result.PSObject.TypeNames.Insert(0, 'MSCloudProfile.CurrentMgProfile')
    $result
}



function Get-AllAzProfiles {
    <#
    .SYNOPSIS
        Lists Azure CLI profiles from both PersonalConfig and WorkConfig and the profiles directory.
    .DESCRIPTION
        Scans ~/.azure/profiles directory for existing profile directories and
        combines with profiles defined in PersonalConfig.psd1 and/or WorkConfig.psd1.
        Shows login status and configuration details for each profile.

        ConfigSource values:
        - PersonalConfig: Defined in PersonalConfig.psd1 only
        - WorkConfig: Defined in WorkConfig.psd1 only
        - Both: Defined in both config files (Personal takes precedence)
        - DiskOnly: Config directory exists but not in any config file
    .PARAMETER ConfiguredOnly
        Shows only profiles defined in PersonalConfig or WorkConfig.psd1.
    .PARAMETER DiscoveredOnly
        Shows only profiles found in ~/.azure/profiles directory without config.
    .EXAMPLE
        Get-AllAzProfiles
        Lists all profiles from both sources.
    .EXAMPLE
        Get-AllAzProfiles -ConfiguredOnly
        Shows only profiles defined in config files.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$ConfiguredOnly,

        [Parameter()]
        [switch]$DiscoveredOnly
    )


    $profilesDir = Join-Path $HOME ".azure\profiles"
    $allProfiles = @{}
    $configSources = @{}  # Track which configs define each profile

    $azModuleAvailable = $null -ne (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)
    $azModuleCurrentContext = $null
    $azModuleContexts = @()

    if ($azModuleAvailable) {
        try {
            $azModuleCurrentContext = Get-AzContext -ErrorAction SilentlyContinue
            $azModuleContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue)
        }
        catch {
            $azModuleCurrentContext = $null
            $azModuleContexts = @()
        }
    }

    # Check for default Azure profile (used when AZURE_CONFIG_DIR is not set)
    if (-not $ConfiguredOnly.IsPresent) {
        $defaultConfigDir = Join-Path $HOME ".azure"
        $defaultConfigFile = Join-Path $defaultConfigDir "azureProfile.json"
        $isLoggedIn = Test-Path $defaultConfigFile
        $currentUser = $null
        $tenantId = $null

        if ($isLoggedIn) {
            try {
                $azProfile = Get-Content $defaultConfigFile | ConvertFrom-Json
                if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                    $currentUser = $azProfile.subscriptions[0].user.name
                    $tenantId = $azProfile.subscriptions[0].tenantId
                }
            }
            catch {
                $currentUser = "(cached)"
            }
        }

        # Always show default profile if .azure directory exists
        if (Test-Path $defaultConfigDir) {
            $allProfiles['(default)'] = [PSCustomObject][ordered]@{
                Name        = '(default)'
                Description = 'Default Azure CLI profile'
                Account     = $null
                SubscriptionId = $null
                AzConfigDir = $defaultConfigDir
                LoggedIn    = $isLoggedIn
                CurrentUser = $currentUser
                TenantId    = $tenantId
                ConfigSource = 'Default'
                AzCliAccount = $null
                AzCliSubscriptionId = $null
                AzCliConfigDir = $defaultConfigDir
                AzCliIsLoggedIn = $isLoggedIn
                AzCliLoggedIn = $isLoggedIn
                AzCliCurrentUser = $currentUser
                AzCliUser = $currentUser
                AzCliTenantId = $tenantId
                HasAzModule = $azModuleAvailable
                AzModuleLoggedIn = $false
                AzModuleContextName = $null
                AzModuleAccount = $null
                AzModuleTenantId = $null
                AzModuleSubscription = $null
                AzModuleSubscriptionId = $null
                AzModuleIsCurrent = $false
            }
        }
    }

    # Discover profiles from disk
    if (-not $ConfiguredOnly.IsPresent -and (Test-Path $profilesDir)) {
        $discoveredDirs = Get-ChildItem -Path $profilesDir -Directory

        foreach ($dir in $discoveredDirs) {
            $name = $dir.Name
            $configFile = Join-Path $dir.FullName "azureProfile.json"
            $isLoggedIn = Test-Path $configFile
            $currentUser = $null
            $tenantId = $null

            if ($isLoggedIn) {
                try {
                    $azProfile = Get-Content $configFile | ConvertFrom-Json
                    if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                        $currentUser = $azProfile.subscriptions[0].user.name
                        $tenantId = $azProfile.subscriptions[0].tenantId
                    }
                }
                catch {
                    $currentUser = "(cached)"
                }
            }

            $allProfiles[$name] = [PSCustomObject][ordered]@{
                Name        = $name
                Description = $null
                Account     = $null
                SubscriptionId = $null
                AzConfigDir = $dir.FullName
                LoggedIn    = $isLoggedIn
                CurrentUser = $currentUser
                TenantId    = $tenantId
                ConfigSource = $null  # Will be set based on config files
                AzCliAccount = $null
                AzCliSubscriptionId = $null
                AzCliConfigDir = $dir.FullName
                AzCliIsLoggedIn = $isLoggedIn
                AzCliLoggedIn = $isLoggedIn
                AzCliCurrentUser = $currentUser
                AzCliUser = $currentUser
                AzCliTenantId = $tenantId
                HasAzModule = $azModuleAvailable
                AzModuleLoggedIn = $false
                AzModuleContextName = $null
                AzModuleAccount = $null
                AzModuleTenantId = $null
                AzModuleSubscription = $null
                AzModuleSubscriptionId = $null
                AzModuleIsCurrent = $false
            }
            # Initialize tracking - this is discovered but not yet in any config
            $configSources[$name] = @()
        }
    }

    # Merge with configured profiles from Personal and Work configs
    if (-not $DiscoveredOnly.IsPresent) {
        # Check Personal config
        $personalProfiles = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Personal)
        if ($personalProfiles.Count -gt 0) {
            foreach ($name in $personalProfiles.Keys) {
                $profileConfig = $personalProfiles[$name]
                $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
                $configDir = Join-Path $HOME ".azure\profiles\$name"
                $configFile = Join-Path $configDir "azureProfile.json"
                $isLoggedIn = Test-Path $configFile
                $currentUser = $null

                if ($isLoggedIn) {
                    try {
                        $azProfile = Get-Content $configFile | ConvertFrom-Json
                        if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                            $currentUser = $azProfile.subscriptions[0].user.name
                        }
                    }
                    catch {
                        $currentUser = "(cached)"
                    }
                }

                # Track that this profile is in Personal config
                if (-not $configSources.ContainsKey($name)) {
                    $configSources[$name] = @()
                }
                $configSources[$name] += 'PersonalConfig'

                if ($allProfiles.ContainsKey($name)) {
                    # Profile already exists (was on disk), update it
                    $allProfiles[$name].Description = $profileConfig.Description
                    $allProfiles[$name].Account = $profileConfig.Account
                    $allProfiles[$name].AzCliAccount = $profileConfig.Account
                    $allProfiles[$name].TenantId = $profileConfig.TenantId
                    $allProfiles[$name].SubscriptionId = $configuredPrimarySub
                    $allProfiles[$name].AzCliSubscriptionId = $configuredPrimarySub
                }
                else {
                    # Add Personal config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $configuredPrimarySub
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $configuredPrimarySub
                        AzCliConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        AzCliIsLoggedIn = $isLoggedIn
                        AzCliLoggedIn = $isLoggedIn
                        AzCliCurrentUser = $currentUser
                        AzCliUser = $currentUser
                        AzCliTenantId = $profileConfig.TenantId
                        HasAzModule = $azModuleAvailable
                        AzModuleLoggedIn = $false
                        AzModuleContextName = $null
                        AzModuleAccount = $null
                        AzModuleTenantId = $null
                        AzModuleSubscription = $null
                        AzModuleSubscriptionId = $null
                        AzModuleIsCurrent = $false
                    }
                }
            }
        }

        # Check Work config
        $workProfiles = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Work)
        if ($workProfiles.Count -gt 0) {
            foreach ($name in $workProfiles.Keys) {
                $profileConfig = $workProfiles[$name]
                $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
                $configDir = Join-Path $HOME ".azure\profiles\$name"
                $configFile = Join-Path $configDir "azureProfile.json"
                $isLoggedIn = Test-Path $configFile
                $currentUser = $null

                if ($isLoggedIn) {
                    try {
                        $azProfile = Get-Content $configFile | ConvertFrom-Json
                        if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                            $currentUser = $azProfile.subscriptions[0].user.name
                        }
                    }
                    catch {
                        $currentUser = "(cached)"
                    }
                }

                # Track that this profile is in Work config
                if (-not $configSources.ContainsKey($name)) {
                    $configSources[$name] = @()
                }
                $configSources[$name] += 'WorkConfig'

                if ($allProfiles.ContainsKey($name)) {
                    # Profile already exists, update it
                    $allProfiles[$name].Description = $profileConfig.Description
                    $allProfiles[$name].Account = $profileConfig.Account
                    $allProfiles[$name].AzCliAccount = $profileConfig.Account
                    $allProfiles[$name].TenantId = $profileConfig.TenantId
                    $allProfiles[$name].SubscriptionId = $configuredPrimarySub
                    $allProfiles[$name].AzCliSubscriptionId = $configuredPrimarySub
                }
                else {
                    # Add Work config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $configuredPrimarySub
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $configuredPrimarySub
                        AzCliConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        AzCliIsLoggedIn = $isLoggedIn
                        AzCliLoggedIn = $isLoggedIn
                        AzCliCurrentUser = $currentUser
                        AzCliUser = $currentUser
                        AzCliTenantId = $profileConfig.TenantId
                        HasAzModule = $azModuleAvailable
                        AzModuleLoggedIn = $false
                        AzModuleContextName = $null
                        AzModuleAccount = $null
                        AzModuleTenantId = $null
                        AzModuleSubscription = $null
                        AzModuleSubscriptionId = $null
                        AzModuleIsCurrent = $false
                    }
                }
            }
        }
    }

    # Set ConfigSource based on which config files define each profile
    foreach ($name in $allProfiles.Keys) {
        if ($configSources.ContainsKey($name) -and $configSources[$name].Count -gt 0) {
            if ($configSources[$name].Count -eq 2) {
                $allProfiles[$name].ConfigSource = 'Both'
            }
            elseif ($configSources[$name] -contains 'PersonalConfig') {
                $allProfiles[$name].ConfigSource = 'PersonalConfig'
            }
            else {
                $allProfiles[$name].ConfigSource = 'WorkConfig'
            }
        }
        elseif ($null -ne $allProfiles[$name].AzConfigDir -and -not $configSources.ContainsKey($name)) {
            $allProfiles[$name].ConfigSource = 'DiskOnly'
        }

        if ($azModuleAvailable -and $azModuleContexts.Count -gt 0) {
            $profileRecord = $allProfiles[$name]
            $matchingContext = $null

            if ($profileRecord.SubscriptionId) {
                $subscriptionMatches = @($azModuleContexts | Where-Object {
                    $_.Subscription -and $_.Subscription.Id -eq $profileRecord.SubscriptionId
                })

                if ($profileRecord.Account) {
                    $subscriptionMatches = @($subscriptionMatches | Where-Object {
                        $_.Account -and $_.Account.Id -eq $profileRecord.Account
                    })
                }

                if ($subscriptionMatches.Count -gt 0) {
                    $matchingContext = $subscriptionMatches | Where-Object {
                        $_.Name -ieq $name
                    } | Select-Object -First 1

                    if (-not $matchingContext) {
                        $matchingContext = $subscriptionMatches | Select-Object -First 1
                    }
                }
            }

            if (-not $matchingContext -and $profileRecord.TenantId) {
                $tenantMatches = @($azModuleContexts | Where-Object {
                    $_.Tenant -and $_.Tenant.Id -eq $profileRecord.TenantId -and
                    (
                        -not $profileRecord.Account -or
                        ($_.Account -and $_.Account.Id -eq $profileRecord.Account)
                    )
                })

                if ($tenantMatches.Count -gt 0) {
                    $matchingContext = $tenantMatches | Where-Object {
                        $_.Name -ieq $name
                    } | Select-Object -First 1

                    if (-not $matchingContext) {
                        $matchingContext = $tenantMatches | Select-Object -First 1
                    }
                }
            }

            if ($matchingContext) {
                $profileRecord.AzModuleLoggedIn = $true
                $profileRecord.AzModuleContextName = $matchingContext.Name
                $profileRecord.AzModuleAccount = $matchingContext.Account.Id
                $profileRecord.AzModuleTenantId = $matchingContext.Tenant.Id
                $profileRecord.AzModuleSubscription = $matchingContext.Subscription.Name
                $profileRecord.AzModuleSubscriptionId = $matchingContext.Subscription.Id
                $profileRecord.AzModuleIsCurrent = (
                    $azModuleCurrentContext -and
                    $azModuleCurrentContext.Name -eq $matchingContext.Name
                )
            }
        }
    }

    # Return sorted profiles
    return $allProfiles.Values | Sort-Object Name | ForEach-Object {
        $_.PSObject.TypeNames.Insert(0, 'MSCloudProfile.AzProfile')
        $_
    }
}



function Get-AllMgProfiles {
    <#
    .SYNOPSIS
        Lists Microsoft Graph profiles from configuration and on-disk routing metadata.
    .DESCRIPTION
        Returns the reserved default profile plus one record per known named profile,
        combining entries from PersonalConfig.psd1, WorkConfig.psd1, and profile
        metadata directories under ~/.mg/profiles/. ConfigSource is one of:
        Default, PersonalConfig, WorkConfig, Both, or DiskOnly.
    .EXAMPLE
        Get-AllMgProfiles
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()


    # Pull entries from each loaded config and tag their source.
    $personalProfiles = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Personal)
    $workProfiles     = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Work)

    $combined = @{}

    # Always expose the reserved unlabelled default Graph profile.
    $combined['default'] = @{ Config = $null; Source = 'Default' }

    # Add personal named profiles while preserving the reserved default entry.
    foreach ($entry in $personalProfiles.GetEnumerator()) {
        if ($entry.Key -ine 'default') {
            $combined[$entry.Key] = @{ Config = $entry.Value; Source = 'PersonalConfig' }
        }
    }

    # Merge work named profiles while preserving personal precedence.
    foreach ($entry in $workProfiles.GetEnumerator()) {
        if ($entry.Key -ieq 'default') {
            continue
        }

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

        $result = [PSCustomObject][ordered]@{
            Name         = $name
            IsActive     = ($name -ieq $activeName)
            ConfigSource = $entry.Source
            Account      = if ($cfg) { $cfg.Account } else { $cached.Account }
            TenantId     = if ($cfg) { $cfg.TenantId } else { $cached.TenantId }
            MgClientId   = if ($cfg -and $cfg.ContainsKey('MgClientId')) { $cfg.MgClientId } else { $cached.ClientId }
            MgScopes     = if ($cfg -and $cfg.ContainsKey('MgScopes')) { $cfg.MgScopes } else { $cached.Scopes }
            Description  = if ($cfg) { $cfg.Description } else { $cached.Description }
            HasCache     = ($null -ne $cached)
        }

        $result.PSObject.TypeNames.Insert(0, 'MSCloudProfile.MgProfile')
        $result
    }
}



function Set-MSCloudProfileConfiguration {
    <#
    .SYNOPSIS
        Registers Personal and Work configuration files for this module session.
    .DESCRIPTION
        Resolves supplied paths, environment-variable overrides, or the standard
        OneDrive locations. Existing PSD1 files are imported into private module
        state. Missing files are registered as empty sources.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$PersonalPath,

        [Parameter()]
        [string]$WorkPath
    )

    if (-not $PSBoundParameters.ContainsKey('PersonalPath')) {
        $PersonalPath = if ($env:MSCLOUDPROFILE_PERSONAL_CONFIG_PATH) {
            $env:MSCLOUDPROFILE_PERSONAL_CONFIG_PATH
        }
        elseif ($env:OneDriveConsumer) {
            Join-Path $env:OneDriveConsumer 'Apps\PowerShell\PersonalConfig.psd1'
        }
        else {
            Join-Path $HOME 'OneDrive\Apps\PowerShell\PersonalConfig.psd1'
        }
    }

    if (-not $PSBoundParameters.ContainsKey('WorkPath')) {
        $WorkPath = if ($env:MSCLOUDPROFILE_WORK_CONFIG_PATH) {
            $env:MSCLOUDPROFILE_WORK_CONFIG_PATH
        }
        elseif ($env:OneDriveCommercial) {
            Join-Path $env:OneDriveCommercial 'Code\PowerShell\Config\WorkConfig.psd1'
        }
        else {
            Join-Path $HOME 'OneDrive - Quisitive\Code\PowerShell\Config\WorkConfig.psd1'
        }
    }

    $personalSource = New-MSCloudProfileConfigurationSource -Name Personal -Path $PersonalPath -Precedence 1
    $workSource = New-MSCloudProfileConfigurationSource -Name Work -Path $WorkPath -Precedence 2

    $script:ConfigurationSources = [ordered]@{
        Personal = $personalSource
        Work     = $workSource
    }

    Get-MSCloudProfileConfiguration
}


function Get-MSCloudProfileConfiguration {
    <#
    .SYNOPSIS
        Shows the configuration files currently registered with MSCloudProfile.
    .DESCRIPTION
        Returns the resolved path, file and load status, configured-profile count,
        and precedence for the Personal and Work sources. Lower precedence values
        win when profile names overlap.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    foreach ($source in $script:ConfigurationSources.Values) {
        $result = [PSCustomObject][ordered]@{
            Name         = $source.Name
            Path         = $source.Path
            Exists       = $source.Exists
            Loaded       = $source.Loaded
            ProfileCount = $source.ProfileCount
            Precedence   = $source.Precedence
        }

        $result.PSObject.TypeNames.Insert(0, 'MSCloudProfile.Configuration')
        $result
    }
}


function New-AzProfile {
    <#
    .SYNOPSIS
        Creates a new Azure CLI profile by logging in and capturing context.
    .DESCRIPTION
        Logs into Azure with a specified tenant, captures the account details,
        and adds the profile to the in-memory configuration. Optionally saves
        the profile to WorkConfig.psd1.

        Can also initialize the config directory for an existing profile defined in config.
    .PARAMETER Name
        Short name for the profile (e.g., 'contoso', 'lab2').
    .PARAMETER TenantId
        The Azure AD tenant ID to log into.
    .PARAMETER Description
        A description for this profile.
    .PARAMETER SubscriptionId
        Optional subscription ID to set as default for this profile.
    .PARAMETER Save
        Saves the profile to WorkConfig.psd1 for persistence across sessions.
    .PARAMETER FromConfig
        Initializes the config directory for a profile that already exists in PersonalConfig or WorkConfig.
        When using this, only -Name parameter is required (TenantId and Description are read from config).
    .EXAMPLE
        New-AzProfile -Name 'contoso' -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Description 'Contoso Corp'
        Creates a new profile and logs in.
    .EXAMPLE
        New-AzProfile -Name 'newclient' -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Description 'New Client' -Save
        Creates a profile and saves it to WorkConfig.psd1.
    .EXAMPLE
        New-AzProfile -Name 'lab' -FromConfig
        Initializes the config directory for the 'lab' profile already defined in PersonalConfig.
    #>
    [CmdletBinding(DefaultParameterSetName = 'NewProfile')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'NewProfile')]
        [string]$TenantId,

        [Parameter(Mandatory, ParameterSetName = 'NewProfile')]
        [string]$Description,

        [Parameter(ParameterSetName = 'NewProfile')]
        [string]$SubscriptionId,

        [Parameter(ParameterSetName = 'NewProfile')]
        [switch]$Save,

        [Parameter(ParameterSetName = 'FromConfig')]
        [switch]$FromConfig
    )



    # Handle FromConfig parameter set
    if ($FromConfig.IsPresent) {
        # Get all configured profiles
        $allConfiguredProfiles = Get-AllAzureProfileConfigs
        if (-not $allConfiguredProfiles.ContainsKey($Name)) {
            $availableProfiles = $allConfiguredProfiles.Keys -join ', '
            Write-Error "Profile '$Name' not found in config. Available profiles: $availableProfiles"
            return
        }

        $profileConfig = $allConfiguredProfiles[$Name]
        $TenantId = $profileConfig.TenantId
        $Description = $profileConfig.Description
        $SubscriptionId = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }

        Write-Host "Initializing config directory for existing profile: " -NoNewline
        Write-Host $Name -ForegroundColor Cyan
        Write-Host "Description: $Description"
        Write-Host "Tenant:      $TenantId"
    }
    else {
        # New profile parameter set - check if profile already exists
        $allConfiguredProfiles = Get-AllAzureProfileConfigs
        if ($allConfiguredProfiles.ContainsKey($Name)) {
            Write-Error "Profile '$Name' already exists. Use a different name or remove the existing profile first."
            return
        }
    }

    # Set the config directory for this profile
    $configDir = Join-Path $HOME ".azure\profiles\$Name"
    $env:AZURE_CONFIG_DIR = $configDir

    if (-not $FromConfig.IsPresent) {
        Write-Host "Creating new profile: " -NoNewline
        Write-Host $Name -ForegroundColor Cyan
    }

    Write-Host "Logging in to tenant: $TenantId" -ForegroundColor Yellow

    # Perform login with account selection
    az login --tenant $TenantId

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Login failed. Profile initialization failed."
        return
    }

    # Get account info after login
    $accountInfo = az account show -o json 2>$null | ConvertFrom-Json

    if (-not $accountInfo) {
        Write-Error "Could not retrieve account information. Profile initialization failed."
        return
    }

    # If subscription ID provided, set it
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not set subscription: $SubscriptionId. Using default."
            $SubscriptionId = $accountInfo.id
        }
    }
    else {
        # Refresh account info after setting subscription
        $accountInfo = az account show -o json 2>$null | ConvertFrom-Json
        $SubscriptionId = $accountInfo.id
    }

    # Register/select matching Az module context for this profile
    $azModuleContext = Sync-AzModuleContext -ProfileName $Name -TenantId $accountInfo.tenantId -SubscriptionId $accountInfo.id -AccountId $accountInfo.user.name

    # If not using FromConfig, create the profile entry and offer to save
    if (-not $FromConfig.IsPresent) {
        # Create the profile entry
        $newProfile = @{
            Account        = $accountInfo.user.name
            TenantId       = $accountInfo.tenantId
            PrimarySub     = $SubscriptionId
            Description    = $Description
        }

        Write-Host "`nProfile created successfully!" -ForegroundColor Green
        Write-Host "  Name:         $Name"
        Write-Host "  Account:      $($newProfile.Account)"
        Write-Host "  Tenant:       $($newProfile.TenantId)"
        Write-Host "  Subscription: $($accountInfo.name) ($SubscriptionId)"

        # Save to config file if requested
        if ($Save.IsPresent) {
            $personalConfigPath = $script:ConfigurationSources.Personal.Path
            $workConfigPath = $script:ConfigurationSources.Work.Path

            Write-Host "`nTo persist this profile, add the following to your config file:" -ForegroundColor Yellow
            Write-Host @"

        '$Name' = @{
            Account        = '$($newProfile.Account)'
            TenantId       = '$($newProfile.TenantId)'
            PrimarySub     = '$SubscriptionId'
            Description    = '$Description'
        }
"@ -ForegroundColor Cyan

            Write-Host "`nSave to:" -ForegroundColor Yellow
            Write-Host "  [1] PersonalConfig.psd1 (personal/lab profiles)"
            Write-Host "  [2] WorkConfig.psd1 (work/customer profiles)"
            Write-Host "  [N] Don't save"
            $choice = Read-Host "Choice"

            $configPath = switch ($choice) {
                '1' { $personalConfigPath }
                '2' { $workConfigPath }
                default { $null }
            }

            if ($configPath -and (Test-Path $configPath)) {
                # Read the current file content
                $content = Get-Content $configPath -Raw

                # Find the profile template section and add the new profile
                $profileEntry = @"

    '$Name' = @{
        Account        = '$($newProfile.Account)'
        TenantId       = '$($newProfile.TenantId)'
        PrimarySub     = '$SubscriptionId'
        Description    = '$Description'
    }
"@
            # Insert before the template comment marker.
            $insertPattern = "# Template for adding new"
            if ($content -match [regex]::Escape($insertPattern)) {
                $content = $content -replace [regex]::Escape($insertPattern), "$profileEntry`n`n    # Template for adding new"
                Set-Content -Path $configPath -Value $content -NoNewline
                Write-Host "Profile saved to config file" -ForegroundColor Green
            }
            else {
                Write-Warning "Could not auto-insert. Please add manually."
            }
        }
    }

    }

    # Return the profile info
    if ($FromConfig.IsPresent) {
        Write-Host "`nProfile initialized successfully!" -ForegroundColor Green
        Write-Host "  Name:         $Name"
        Write-Host "  Account:      $($accountInfo.user.name)"
        Write-Host "  Tenant:       $($accountInfo.tenantId)"
        Write-Host "  Subscription: $($accountInfo.name) ($($accountInfo.id))"

        [PSCustomObject][ordered]@{
            Profile        = $Name
            Account        = $accountInfo.user.name
            TenantId       = $accountInfo.tenantId
            Subscription   = $accountInfo.name
            SubscriptionId = $accountInfo.id
            Description    = $Description
            AzCliAccount   = $accountInfo.user.name
            AzCliIsLoggedIn = ($null -ne $accountInfo)
            AzCliTenantId  = $accountInfo.tenantId
            AzCliSubscription = $accountInfo.name
            AzCliSubscriptionId = $accountInfo.id
            HasAzModule    = $azModuleContext.HasAzModule
            AzModuleContextName = $azModuleContext.ContextName
            AzModuleUser   = $azModuleContext.Account
            AzModuleTenantId = $azModuleContext.TenantId
            AzModuleSubscription = $azModuleContext.Subscription
            AzModuleSubscriptionId = $azModuleContext.SubscriptionId
        }
    }
    else {
        [PSCustomObject][ordered]@{
            Profile        = $Name
            Account        = $newProfile.Account
            TenantId       = $newProfile.TenantId
            Subscription   = $accountInfo.name
            SubscriptionId = $SubscriptionId
            Description    = $Description
            AzCliAccount   = $newProfile.Account
            AzCliIsLoggedIn = ($null -ne $accountInfo)
            AzCliTenantId  = $newProfile.TenantId
            AzCliSubscription = $accountInfo.name
            AzCliSubscriptionId = $SubscriptionId
            HasAzModule    = $azModuleContext.HasAzModule
            AzModuleContextName = $azModuleContext.ContextName
            AzModuleUser   = $azModuleContext.Account
            AzModuleTenantId = $azModuleContext.TenantId
            AzModuleSubscription = $azModuleContext.Subscription
            AzModuleSubscriptionId = $azModuleContext.SubscriptionId
        }
    }
}



function New-MgProfile {
    <#
    .SYNOPSIS
        Creates or initializes a persistent Microsoft Graph profile.
    .DESCRIPTION
        Connects with a CurrentUser context, optionally targets the configured account
        through LoginHint, validates the resulting context, and stores non-secret
        routing metadata. WAM/MSAL owns the shared protected credential cache.
        The reserved default profile is stored only as Graph metadata and never adds
        an Azure profile entry.
    .PARAMETER Name
        Profile name, including the reserved name default.
    .PARAMETER TenantId
        Target tenant ID.
    .PARAMETER Account
        Optional account UPN/email used as the login hint and validation target.
    .PARAMETER Scopes
        Optional delegated scopes for Connect-MgGraph.
    .PARAMETER ClientId
        Optional public-client application ID.
    .PARAMETER Description
        Free-form description for the profile.
    .PARAMETER Save
        Prompts to save a named profile to a config psd1. Default is stored only in the Graph cache.
    .PARAMETER FromConfig
        Activates an existing config entry through Use-MgProfile.
    .EXAMPLE
        New-MgProfile -Name default -TenantId <guid> -Account user@contoso.com
    .EXAMPLE
        New-MgProfile -Name lab -TenantId <guid> -Account user@contoso.com -Save
    .EXAMPLE
        New-MgProfile -Name qu -FromConfig
    #>
    [CmdletBinding(DefaultParameterSetName = 'NewProfile', SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'NewProfile')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'FromConfig')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'NewProfile')]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'NewProfile')]
        [string]$Account,

        [Parameter(ParameterSetName = 'NewProfile')]
        [string[]]$Scopes,

        [Parameter(ParameterSetName = 'NewProfile')]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'NewProfile')]
        [string]$Description = '',

        [Parameter(ParameterSetName = 'NewProfile')]
        [switch]$Save,

        [Parameter(Mandatory, ParameterSetName = 'FromConfig')]
        [switch]$FromConfig
    )

    $normalizedName = if ($Name -ieq '(default)' -or $Name -ieq 'default') { 'default' } else { $Name }

    # Delegate configured activation to the common persistent switching flow.
    if ($FromConfig.IsPresent) {
        if ($normalizedName -ne 'default') {
            $allProfiles = Get-AllAzureProfileConfigs
            if (-not $allProfiles.ContainsKey($normalizedName)) {
                throw "Profile '$normalizedName' not found in any config."
            }
        }

        if ($PSCmdlet.ShouldProcess("Mg profile '$normalizedName'", 'Activate configured profile')) {
            Use-MgProfile -Name $normalizedName | Out-Null
        }
        return Get-CurrentMgProfile
    }

    # Require the Graph authentication capabilities used for persistent account targeting.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available."
    }
    if (-not $connectMgCommand.Parameters.ContainsKey('ContextScope')) {
        throw "Connect-MgGraph does not support ContextScope. Upgrade Microsoft.Graph.Authentication."
    }
    if ($Account -and -not $connectMgCommand.Parameters.ContainsKey('LoginHint')) {
        throw "Connect-MgGraph does not support LoginHint. Upgrade Microsoft.Graph.Authentication to 2.39.0 or later."
    }

    Write-Host "Creating Mg profile: " -NoNewline
    Write-Host $normalizedName -ForegroundColor Cyan

    # Honor WhatIf and confirmation before connecting or writing profile metadata.
    if (-not $PSCmdlet.ShouldProcess("Mg profile '$normalizedName'", 'Connect and save persistent profile metadata')) {
        return
    }

    # Clear the prompt marker until the requested identity is connected and validated.
    Set-MgActiveProfileName -ProfileName 'default'

    # Connect without signing out so existing WAM/MSAL credentials remain reusable.
    $connectParams = @{
        TenantId     = $TenantId
        ContextScope = 'CurrentUser'
        ErrorAction  = 'Stop'
    }
    if ($Scopes) { $connectParams.Scopes = $Scopes }
    if ($ClientId) { $connectParams.ClientId = $ClientId }
    if ($Account) { $connectParams.LoginHint = $Account }

    try {
        Connect-MgGraph @connectParams | Out-Null

        $newContext = Get-MgModuleCurrentContext
        if (-not $newContext.LoggedIn) {
            throw "Connect-MgGraph returned without a live context."
        }
        if ($newContext.TenantId -ne $TenantId) {
            throw "Tenant mismatch. Expected '$TenantId', connected '$($newContext.TenantId)'."
        }
        if ($Account -and $newContext.Account -ine $Account) {
            throw "Account mismatch. Expected '$Account', connected '$($newContext.Account)'."
        }

        $effectiveDescription = if ($Description) {
            $Description
        }
        elseif ($normalizedName -ieq 'default') {
            'Default Microsoft Graph profile'
        }
        else {
            ''
        }

        Save-MgProfileContext -ProfileName $normalizedName -Context $newContext -Description $effectiveDescription
        Set-MgActiveProfileName -ProfileName $normalizedName
    }
    catch {
        Write-Error "Could not create Mg profile '$normalizedName': $_"
        throw
    }

    # Save only named profiles to the shared Azure/Mg configuration files.
    if ($Save.IsPresent -and $normalizedName -ieq 'default') {
        Write-Host "Default Mg profile metadata saved under ~/.mg/profiles/default." -ForegroundColor Green
    }
    elseif ($Save.IsPresent) {
        $effectiveAccount = if ($Account) { $Account } else { $newContext.Account }
        $personalConfigPath = $script:ConfigurationSources.Personal.Path
        $workConfigPath = $script:ConfigurationSources.Work.Path

        Write-Host "`nSave Mg profile '$normalizedName' to which config?"
        Write-Host "  [1] PersonalConfig.psd1"
        Write-Host "  [2] WorkConfig.psd1"
        Write-Host "  [N] Don't save"
        $choice = Read-Host "Choice"

        $configPath = switch ($choice) {
            '1' { $personalConfigPath }
            '2' { $workConfigPath }
            default { $null }
        }

        # Insert the new named profile before the existing configuration template.
        if ($configPath -and (Test-Path -LiteralPath $configPath)) {
            $content = Get-Content -LiteralPath $configPath -Raw
            $lines = @()
            $lines += "        Account        = '$effectiveAccount'"
            $lines += "        TenantId       = '$TenantId'"
            $lines += "        Description    = '$Description'"
            if ($Scopes) { $lines += "        MgScopes       = @('" + ($Scopes -join "','") + "')" }
            if ($ClientId) { $lines += "        MgClientId     = '$ClientId'" }

            $profileEntry = @"

    '$normalizedName' = @{
$($lines -join "`n")
    }
"@

            $insertPattern = "# Template for adding new"
            if ($content -match [regex]::Escape($insertPattern)) {
                $content = $content -replace [regex]::Escape($insertPattern), "$profileEntry`n`n    # Template for adding new"
                Set-Content -LiteralPath $configPath -Value $content -NoNewline
                Write-Host "Mg profile saved to config file" -ForegroundColor Green
            }
            else {
                Write-Warning "Could not auto-insert. Please add the profile manually."
            }
        }
    }

    Get-CurrentMgProfile
}



function Remove-AzProfile {
    <#
    .SYNOPSIS
        Removes an Azure CLI profile configuration directory.
    .DESCRIPTION
        Removes the Azure CLI config directory for the specified profile and
        optionally removes it from the in-memory configuration.
    .PARAMETER Name
        The profile name to remove.
    .PARAMETER KeepConfig
        Keeps the profile in WorkConfig (only removes the local config dir).
    .EXAMPLE
        Remove-AzProfile -Name 'oldclient'
        Removes the profile's config directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig
    )


    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    $profileConfig = $null
    if ($allConfiguredProfiles.ContainsKey($Name)) {
        $profileConfig = $allConfiguredProfiles[$Name]
    }

    $configDir = Join-Path $HOME ".azure\profiles\$Name"

    # Remove config directory if it exists
    if (Test-Path $configDir) {
        if ($PSCmdlet.ShouldProcess($configDir, "Remove Azure config directory")) {
            Remove-Item -Path $configDir -Recurse -Force
            Write-Host "Removed config directory: $configDir" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Config directory not found: $configDir" -ForegroundColor Yellow
    }

    # Remove matching Az PowerShell module contexts for this profile
    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    $removeAzContextCommand = Get-Command -Name Remove-AzContext -ErrorAction SilentlyContinue

    if ($getAzContextCommand -and $removeAzContextCommand -and $profileConfig) {
        $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
        $matchingContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            ($configuredPrimarySub -and $_.Subscription -and $_.Subscription.Id -eq $configuredPrimarySub) -or
            (
                $profileConfig.TenantId -and
                $_.Tenant -and
                $_.Tenant.Id -eq $profileConfig.TenantId -and
                (
                    -not $profileConfig.Account -or
                    ($_.Account -and $_.Account.Id -eq $profileConfig.Account)
                )
            )
        })

        if ($matchingContexts.Count -gt 0) {
            $contextNames = $matchingContexts | Select-Object -ExpandProperty Name -Unique

            foreach ($contextName in $contextNames) {
                if ($PSCmdlet.ShouldProcess($contextName, "Remove Az PowerShell context")) {
                    try {
                        Remove-AzContext -Name $contextName -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
                        Remove-AzContext -Name $contextName -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "Removed Az PowerShell context: $contextName" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Could not remove Az PowerShell context '$contextName': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # Remove from in-memory config unless KeepConfig is specified
    if (-not $KeepConfig.IsPresent) {
        $removed = $false
        $personalConfig = Get-MSCloudProfileConfigurationData -Name Personal
        $workConfig = Get-MSCloudProfileConfigurationData -Name Work
        $personalProfiles = Get-AzureProfilesFromConfig -Config $personalConfig
        $workProfiles = Get-AzureProfilesFromConfig -Config $workConfig

        if ($personalProfiles.ContainsKey($Name)) {
            if ($personalConfig.ContainsKey('AzureProfiles') -and $personalConfig.AzureProfiles -is [hashtable]) {
                $personalConfig.AzureProfiles.Remove($Name)
            }
            else {
                $personalConfig.Remove($Name)
            }
            Write-Host "Removed profile from Personal in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from PersonalConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if ($workProfiles.ContainsKey($Name)) {
            if ($workConfig.ContainsKey('AzureProfiles') -and $workConfig.AzureProfiles -is [hashtable]) {
                $workConfig.AzureProfiles.Remove($Name)
            }
            else {
                $workConfig.Remove($Name)
            }
            Write-Host "Removed profile from Work in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from WorkConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if (-not $removed) {
            Write-Host "Profile '$Name' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completer for Remove-AzProfile
Register-ArgumentCompleter -CommandName Remove-AzProfile -ParameterName Name -ScriptBlock $azProfileCompleter



function Remove-MgProfile {
    <#
    .SYNOPSIS
        Removes Microsoft Graph profile metadata and optionally its config entry.
    .DESCRIPTION
        Deletes non-secret metadata under ~/.mg/profiles/<name>/ and, unless
        KeepConfig is specified, removes matching in-memory Personal and Work entries.
        The config psd1 files and shared WAM/MSAL credential cache are not modified.
        Removing the reserved default profile resets its metadata but does not remove
        default from profile discovery.
    .PARAMETER Name
        Profile name to remove or reset.
    .PARAMETER KeepConfig
        Leaves the in-memory config entries intact.
    .PARAMETER KeepCache
        Leaves the on-disk ~/.mg/profiles/<name>/ directory intact.
    .EXAMPLE
        Remove-MgProfile lab
    .EXAMPLE
        Remove-MgProfile default
        Resets the captured default-profile metadata without signing out.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig,

        [Parameter()]
        [switch]$KeepCache
    )

    $normalizedName = if ($Name -ieq '(default)' -or $Name -ieq 'default') { 'default' } else { $Name }
    $activeName = Get-MgActiveProfileName

    # Move an active named profile to default without clearing the shared credential cache.
    if ($normalizedName -ne 'default' -and $normalizedName -ieq $activeName) {
        if (-not $PSCmdlet.ShouldProcess("active Mg profile '$normalizedName'", 'Switch to default profile')) {
            return
        }

        Use-MgProfile -Name default -NoWelcome | Out-Null
    }

    # Remove the profile metadata directory unless explicitly preserved.
    if (-not $KeepCache.IsPresent) {
        $cacheDir = Get-MgGraphProfileDir -ProfileName $normalizedName
        if (Test-Path -LiteralPath $cacheDir) {
            if ($PSCmdlet.ShouldProcess($cacheDir, 'Remove profile metadata directory')) {
                Remove-Item -LiteralPath $cacheDir -Recurse -Force
                Write-Host "Removed profile metadata: $cacheDir" -ForegroundColor Green
            }
        }
    }

    # Remove named profiles from loaded configuration without editing their source files.
    if (-not $KeepConfig.IsPresent -and $normalizedName -ne 'default') {
        $removed = $false
        foreach ($varName in @('Personal', 'Work')) {
            $configVar = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
            if ($configVar -and $configVar.Value -is [hashtable] -and $configVar.Value.ContainsKey($normalizedName)) {
                if ($PSCmdlet.ShouldProcess("`$$varName[$normalizedName]", 'Remove in-memory profile entry')) {
                    $configVar.Value.Remove($normalizedName)
                    Write-Host "Removed in-memory entry: `$$varName[$normalizedName]" -ForegroundColor Green
                    $removed = $true
                }
            }
        }

        if (-not $removed) {
            Write-Host "Profile '$normalizedName' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completion for the reserved default and all configured or cached profiles.
$mgProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $results = @(
        [System.Management.Automation.CompletionResult]::new(
            'default',
            'default',
            'ParameterValue',
            'Default Microsoft Graph profile'
        )
    )
    $allProfiles = Get-AllAzureProfileConfigs

    # Add configured named profiles without shadowing the reserved default.
    if ($allProfiles.Count -gt 0) {
        $results += $allProfiles.Keys |
            Where-Object { $_ -ine 'default' -and $_ -like "$wordToComplete*" } |
            ForEach-Object {
                $description = $allProfiles[$_].Description
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
            }
    }

    # Add disk-only profile metadata directories without duplicating known names.
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ine 'default' -and
                $_.Name -like "$wordToComplete*" -and
                -not $allProfiles.ContainsKey($_.Name)
            } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    $_.Name,
                    $_.Name,
                    'ParameterValue',
                    'Disk-only Mg profile metadata'
                )
            }
    }

    $results | Where-Object { $_.CompletionText -like "$wordToComplete*" }
}

Register-ArgumentCompleter -CommandName Use-MgProfile, ugp -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName Remove-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName New-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter



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

#region PRIVATE FUNCTIONS
# Private helpers support the public commands declared above.
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

function New-MSCloudProfileConfigurationSource {
    <#
    .SYNOPSIS
        Creates one validated configuration-source record.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Personal', 'Work')]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$Precedence
    )

    $resolvedPath = [Environment]::ExpandEnvironmentVariables($Path)
    $source = [ordered]@{
        Name         = $Name
        Path         = $resolvedPath
        Exists       = [System.IO.File]::Exists($resolvedPath)
        Loaded       = $false
        Config       = @{}
        ProfileCount = 0
        Precedence   = $Precedence
    }

    if (-not $source.Exists) {
        return $source
    }

    try {
        $config = Import-PowerShellDataFile -Path $resolvedPath -ErrorAction Stop
    }
    catch {
        throw "Failed to import $Name configuration '$resolvedPath': $($_.Exception.Message)"
    }

    if ($config -isnot [hashtable]) {
        throw "$Name configuration '$resolvedPath' must contain a hashtable."
    }

    $source.Config = $config
    $source.Loaded = $true
    $source.ProfileCount = (Get-AzureProfilesFromConfig -Config $config).Count
    return $source
}

function Get-MSCloudProfileConfigurationData {
    <#
    .SYNOPSIS
        Gets the private imported data for one registered configuration source.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Personal', 'Work')]
        [string]$Name
    )

    return $script:ConfigurationSources[$Name].Config
}

function Get-AllAzureProfileConfigs {
    <#
    .SYNOPSIS
        Returns a merged hashtable of Azure profiles from Personal and Work configs.
    .DESCRIPTION
        Combines top-level profile entries from registered Personal and Work configuration sources.
        Personal profiles take precedence if there's a name conflict.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $merged = @{}
    $workProfiles = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Work)
    $personalProfiles = Get-AzureProfilesFromConfig -Config (Get-MSCloudProfileConfigurationData -Name Personal)

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
#region PRIVATE MG PROFILE STORE
# Defines private Microsoft Graph profile metadata and session-state helpers.

function Get-MgGraphProfileRoot {
    # Return the live Microsoft Graph SDK configuration directory.
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    return (Join-Path $userHome '.mg')
}

function Get-MgGraphProfilesRoot {
    # Return the directory that holds logical Microsoft Graph profiles.
    return (Join-Path (Get-MgGraphProfileRoot) 'profiles')
}

function Get-MgGraphProfileDir {
    # Return the metadata directory for one logical Microsoft Graph profile.
    param([Parameter(Mandatory)][string]$ProfileName)

    $normalizedName = if ($ProfileName -ieq '(default)') { 'default' } else { $ProfileName }
    return (Join-Path (Get-MgGraphProfilesRoot) $normalizedName)
}

function Get-MgActiveProfileName {
    # Read the process-local active profile name, defaulting to the hidden-label default profile.
    $stateVariable = Get-Variable -Name MSCloudMgProfileName -Scope Global -ErrorAction SilentlyContinue
    if ($stateVariable -and -not [string]::IsNullOrWhiteSpace([string]$stateVariable.Value)) {
        return [string]$stateVariable.Value
    }

    return 'default'
}

function Set-MgActiveProfileName {
    # Set the process-local prompt state without coupling it to authentication persistence.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
    param([Parameter(Mandatory)][string]$ProfileName)

    $stateTarget = '$global:MSCloudMgProfileName'
    if (-not $PSCmdlet.ShouldProcess($stateTarget, "Set active Mg profile to '$ProfileName'")) {
        return
    }

    # Keep the prompt unlabelled while the reserved default profile is active.
    if ($ProfileName -ieq '(default)' -or $ProfileName -ieq 'default') {
        Remove-Variable -Name MSCloudMgProfileName -Scope Global -ErrorAction SilentlyContinue
        return
    }

    Set-Variable -Name MSCloudMgProfileName -Scope Global -Value $ProfileName
}

function Save-MgProfileContext {
    # Persist non-secret routing metadata while leaving WAM/MSAL token files untouched.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Context,

        [Parameter()]
        [string]$Description
    )

    $profileDir = Get-MgGraphProfileDir -ProfileName $ProfileName
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }

    # Store only values needed to route and validate a future cached connection.
    $profileContext = [ordered]@{
        Account     = $Context.Account
        TenantId    = $Context.TenantId
        Scopes      = @($Context.Scopes)
        ClientId    = $Context.ClientId
        AuthType    = $Context.AuthType
        Description = $Description
        UpdatedAt   = (Get-Date).ToString('o')
    }

    $contextPath = Join-Path $profileDir 'mg.context.json'
    $profileContext |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $contextPath -Encoding utf8
}

function Get-MgProfileCachedContext {
    # Read a profile's non-secret routing metadata without touching the live Graph session.
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$ProfileName)

    $contextFile = Join-Path (Get-MgGraphProfileDir -ProfileName $ProfileName) 'mg.context.json'
    if (-not (Test-Path -LiteralPath $contextFile)) {
        return $null
    }

    try {
        $data = Get-Content -LiteralPath $contextFile -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    [PSCustomObject][ordered]@{
        Account     = $data.Account
        TenantId    = $data.TenantId
        Scopes      = $data.Scopes
        ClientId    = $data.ClientId
        AuthType    = $data.AuthType
        Description = $data.Description
        UpdatedAt   = $data.UpdatedAt
    }
}

#endregion
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
            ContextScope   = $null
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
        ContextScope   = $ctx.ContextScope
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
#endregion

#endregion

#region MODULE EXPORTS
# Export only the commands declared in the module manifest.
Export-ModuleMember -Function @(
 'Use-AzProfile',
 'Use-MgProfile',
 'Get-CurrentAzProfile',
 'Get-CurrentMgProfile',
 'Get-AllAzProfiles',
 'Get-AllMgProfiles',
 'Set-MSCloudProfileConfiguration',
 'Get-MSCloudProfileConfiguration',
 'New-AzProfile',
 'New-MgProfile',
 'Remove-AzProfile',
 'Remove-MgProfile',
 'Use-AzProfileSubscription'
)
#endregion
