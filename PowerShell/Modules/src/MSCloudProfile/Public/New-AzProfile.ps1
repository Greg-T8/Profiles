# -------------------------------------------------------------------------
# Program: New-AzProfile.ps1
# Description: Defines the public MSCloudProfile command New-AzProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command New-AzProfile.

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
            $personalConfigPath = "$env:USERPROFILE/Documents/PowerShell/Config/PersonalConfig.psd1"
            $workConfigPath = "$env:OneDriveCommercial/Code/PowerShell/Config/WorkConfig.psd1"

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

#endregion
