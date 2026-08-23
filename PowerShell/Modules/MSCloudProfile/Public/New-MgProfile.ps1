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
        Creates a new Microsoft Graph / Entra profile or initializes an existing config entry.
    .DESCRIPTION
        In NewProfile mode, prompts for tenant/account details, runs Connect-MgGraph (and
        Connect-Entra if available) with process-scoped contexts, captures the resulting
        context, and optionally saves the entry to PersonalConfig.psd1 or WorkConfig.psd1.
        In FromConfig mode, activates an existing config entry via Use-MgProfile.
    .PARAMETER Name
        Profile name (top-level key in the config psd1).
    .PARAMETER TenantId
        Target tenant ID (NewProfile mode).
    .PARAMETER Account
        Optional account UPN/email to record on the profile (NewProfile mode).
    .PARAMETER Scopes
        Optional delegated scopes for Connect-MgGraph.
    .PARAMETER ClientId
        Optional client (application) ID for app-only auth.
    .PARAMETER Description
        Free-form description for the profile.
    .PARAMETER Save
        Prompts to save the profile to a config psd1 (NewProfile mode).
    .PARAMETER FromConfig
        Activates a profile already defined in config.
    .EXAMPLE
        New-MgProfile -Name lab -TenantId <guid> -Save
    .EXAMPLE
        New-MgProfile -Name qu -FromConfig
    #>
    [CmdletBinding(DefaultParameterSetName = 'NewProfile')]
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


    if ($FromConfig.IsPresent) {
        # Delegate to Use-MgProfile to perform process-scoped activation.
        $allProfiles = Get-AllAzureProfileConfigs
        if (-not $allProfiles.ContainsKey($Name)) {
            throw "Profile '$Name' not found in any config."
        }
        Use-MgProfile -Name $Name
        return Get-CurrentMgProfile
    }

    # Require Graph SDK support for process-scoped profile activation.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available."
    }
    if (-not $connectMgCommand.Parameters.ContainsKey('ContextScope')) {
        throw "Connect-MgGraph does not support ContextScope. Upgrade Microsoft.Graph.Authentication."
    }

    # Disconnect only prior process contexts so the persistent CurrentUser default remains intact.
    $currentMg = Get-MgModuleCurrentContext
    $currentEntra = Get-EntraModuleCurrentContext
    if ($currentMg.LoggedIn -and [string]$currentMg.ContextScope -ieq 'Process') {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
    }
    if ($currentEntra.LoggedIn -and [string]$currentEntra.ContextScope -ieq 'Process') {
        $disconnectEntraCommand = Get-Command -Name Disconnect-Entra -ErrorAction SilentlyContinue
        if ($disconnectEntraCommand) {
            try { Disconnect-Entra -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-Entra failed: $_" }
        }
    }
    Set-MgActiveProfileName -ProfileName '(default)'

    $connectParams = @{
        TenantId     = $TenantId
        ContextScope = 'Process'
        ErrorAction  = 'Stop'
    }
    if ($Scopes)   { $connectParams.Scopes   = $Scopes }
    if ($ClientId) { $connectParams.ClientId = $ClientId }

    Connect-MgGraph @connectParams | Out-Null
    Set-MgActiveProfileName -ProfileName $Name

    $connectEntraCommand = Get-Command -Name Connect-Entra -ErrorAction SilentlyContinue
    if ($connectEntraCommand -and $connectEntraCommand.Parameters.ContainsKey('ContextScope')) {
        $entraParams = @{
            TenantId     = $TenantId
            ContextScope = 'Process'
            ErrorAction  = 'Continue'
        }
        if ($Scopes)   { $entraParams.Scopes   = $Scopes }
        if ($ClientId) { $entraParams.ClientId = $ClientId }
        try { Connect-Entra @entraParams | Out-Null } catch { Write-Warning "Connect-Entra failed: $_" }
    }
    elseif ($connectEntraCommand) {
        Write-Warning "Connect-Entra does not support ContextScope. Upgrade Microsoft.Entra.Authentication."
    }

    $newContext = Get-MgModuleCurrentContext
    $effectiveAccount = if ($Account) { $Account } else { $newContext.Account }

    if ($Save.IsPresent) {
        # Resolve writable config files (mirror New-AzProfile prompt flow).
        $personalConfigPath = Join-Path $HOME 'OneDrive\Apps\PowerShell\PersonalConfig.psd1'
        $workConfigPath = Join-Path $HOME 'OneDrive - Quisitive\Code\PowerShell\Config\WorkConfig.psd1'

        Write-Host "`nSave Mg profile '$Name' to which config?"
        Write-Host "  [1] PersonalConfig.psd1"
        Write-Host "  [2] WorkConfig.psd1"
        Write-Host "  [N] Don't save"
        $choice = Read-Host "Choice"

        $configPath = switch ($choice) {
            '1' { $personalConfigPath }
            '2' { $workConfigPath }
            default { $null }
        }

        if ($configPath -and (Test-Path $configPath)) {
            $content = Get-Content $configPath -Raw

            # Build profile entry body conditionally so optional fields are omitted when empty.
            $lines = @()
            $lines += "        Account        = '$effectiveAccount'"
            $lines += "        TenantId       = '$TenantId'"
            $lines += "        Description    = '$Description'"
            if ($Scopes)   { $lines += "        MgScopes       = @('" + ($Scopes -join "','") + "')" }
            if ($ClientId) { $lines += "        MgClientId     = '$ClientId'" }

            $profileEntry = @"

    '$Name' = @{
$($lines -join "`n")
    }
"@

            $insertPattern = "# Template for adding new"
            if ($content -match [regex]::Escape($insertPattern)) {
                $content = $content -replace [regex]::Escape($insertPattern), "$profileEntry`n`n    # Template for adding new"
                Set-Content -Path $configPath -Value $content -NoNewline
                Write-Host "Mg profile saved to config file" -ForegroundColor Green
            }
            else {
                Write-Warning "Could not auto-insert. Please add manually."
            }
        }
    }

    Get-CurrentMgProfile
}

#endregion
