# -------------------------------------------------------------------------
# Program: MgProfileStore.ps1
# Description: Defines private Microsoft Graph profile cache and active-profile state helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PRIVATE MG PROFILE STORE
# Defines private Microsoft Graph profile cache and active-profile state helpers.

$script:MgGraphProfileFiles = @('mg.authrecord.json', 'mg.context.json', 'mg.graphoptions.json')

function Get-MgGraphProfileRoot {
    # Returns the live ~/.mg directory path.
    $userHome = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
    return (Join-Path $userHome '.mg')
}

function Get-MgGraphProfilesRoot {
    # Returns the parent directory that holds all per-profile caches.
    return (Join-Path (Get-MgGraphProfileRoot) 'profiles')
}

function Get-MgGraphProfileDir {
    param([Parameter(Mandatory)][string]$ProfileName)
    return (Join-Path (Get-MgGraphProfilesRoot) $ProfileName)
}

function Get-MgActiveProfileName {
    # Reads the active profile name from ~/.mg/profiles/.active, defaulting to '(default)'.
    $stateFile = Join-Path (Get-MgGraphProfilesRoot) '.active'
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $name = (Get-Content -LiteralPath $stateFile -Raw -ErrorAction Stop).Trim()
            if ($name) { return $name }
        }
        catch { Write-Verbose "Could not read Mg active-profile state file: $_" }
    }
    return '(default)'
}

function Set-MgActiveProfileName {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
    param([Parameter(Mandatory)][string]$ProfileName)

    $profilesRoot = Get-MgGraphProfilesRoot
    if (-not (Test-Path -LiteralPath $profilesRoot)) {
        New-Item -Path $profilesRoot -ItemType Directory -Force | Out-Null
    }
    $stateFile = Join-Path $profilesRoot '.active'
    if ($PSCmdlet.ShouldProcess($stateFile, "Write active profile name '$ProfileName'")) {
        Set-Content -LiteralPath $stateFile -Value $ProfileName -NoNewline
    }
}

function Save-MgProfileCache {
    # Copies the live ~/.mg/mg.*.json files into the per-profile cache directory.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProfileName)

    $mgRoot = Get-MgGraphProfileRoot
    if (-not (Test-Path -LiteralPath $mgRoot)) { return }

    $destDir = Get-MgGraphProfileDir -ProfileName $ProfileName
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    foreach ($file in $script:MgGraphProfileFiles) {
        $src = Join-Path $mgRoot $file
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $destDir $file) -Force
        }
    }
}

function Restore-MgProfileCache {
    # Copies a profile's cached files into ~/.mg/. Returns $true if any were copied.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$ProfileName)

    $srcDir = Get-MgGraphProfileDir -ProfileName $ProfileName
    if (-not (Test-Path -LiteralPath $srcDir)) { return $false }

    $mgRoot = Get-MgGraphProfileRoot
    if (-not (Test-Path -LiteralPath $mgRoot)) {
        New-Item -Path $mgRoot -ItemType Directory -Force | Out-Null
    }

    $restored = $false
    foreach ($file in $script:MgGraphProfileFiles) {
        $src = Join-Path $srcDir $file
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $mgRoot $file) -Force
            $restored = $true
        }
    }
    return $restored
}

function Clear-MgGraphLiveCache {
    # Removes the live ~/.mg/mg.*.json files so cached state doesn't bleed between profiles.
    $mgRoot = Get-MgGraphProfileRoot
    if (-not (Test-Path -LiteralPath $mgRoot)) { return }
    foreach ($file in $script:MgGraphProfileFiles) {
        $live = Join-Path $mgRoot $file
        if (Test-Path -LiteralPath $live) {
            Remove-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-MgProfileCachedContext {
    # Reads a profile's cached mg.context.json without touching the live session.
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$ProfileName)

    $contextFile = Join-Path (Get-MgGraphProfileDir -ProfileName $ProfileName) 'mg.context.json'
    if (-not (Test-Path -LiteralPath $contextFile)) { return $null }

    try {
        $data = Get-Content -LiteralPath $contextFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    [PSCustomObject][ordered]@{
        Account  = $data.Account
        TenantId = $data.TenantId
        Scopes   = $data.Scopes
        ClientId = $data.ClientId
        AuthType = $data.AuthType
    }
}

#endregion
