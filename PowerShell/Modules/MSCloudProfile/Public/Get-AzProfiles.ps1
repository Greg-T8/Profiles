# -------------------------------------------------------------------------
# Program: Get-AzProfiles.ps1
# Description: Defines the public MSCloudProfile command Get-AzProfiles.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Get-AzProfiles.

function Get-AzProfiles {
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
        Get-AzProfiles
        Lists all profiles from both sources.
    .EXAMPLE
        Get-AzProfiles -ConfiguredOnly
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
        $personalProfiles = Get-AzureProfilesFromConfig -Config $global:Personal
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
        $workProfiles = Get-AzureProfilesFromConfig -Config $global:Work
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
    return $allProfiles.Values | Sort-Object Name
}

#endregion
