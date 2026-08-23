# -------------------------------------------------------------------------
# Program: New-MgProfile.ps1
# Description: Defines the public MSCloudProfile command New-MgProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command New-MgProfile.

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
        $personalConfigPath = Join-Path $HOME 'OneDrive\Apps\PowerShell\PersonalConfig.psd1'
        $workConfigPath = Join-Path $HOME 'OneDrive - Quisitive\Code\PowerShell\Config\WorkConfig.psd1'

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

#endregion
