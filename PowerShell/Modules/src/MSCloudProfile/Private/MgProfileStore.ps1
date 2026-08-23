# -------------------------------------------------------------------------
# Program: MgProfileStore.ps1
# Description: Defines private Microsoft Graph profile metadata and session-state helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

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
