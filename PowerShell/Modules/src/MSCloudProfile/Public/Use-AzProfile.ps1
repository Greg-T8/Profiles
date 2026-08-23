# -------------------------------------------------------------------------
# Program: Use-AzProfile.ps1
# Description: Defines the public MSCloudProfile command Use-AzProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Use-AzProfile.

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

#endregion
