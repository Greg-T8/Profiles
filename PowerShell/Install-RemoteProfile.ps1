# -------------------------------------------------------------------------
# Program: Install-RemoteProfile.ps1
# Description: Bootstrap script to quickly install PowerShell profile customizations
#              from GitHub into a remote development session
# Context: Remote Development Setup (Microsoft Azure Administrator)
# Author: Greg Tate
# -------------------------------------------------------------------------

<#
.SYNOPSIS
    Installs PowerShell profile customizations from GitHub into the current system.

.DESCRIPTION
    This bootstrap script downloads and installs PowerShell profile files from your
    GitHub repository into the appropriate PowerShell profile location. It can either:
    1. Clone the full repository (if git is available)
    2. Download individual files directly from GitHub (fallback method)

    After installation, it automatically dot-sources the profile to activate it in
    the current session.

.PARAMETER GitHubRepo
    The GitHub repository in the format 'owner/repo'. Defaults to 'Greg-T8/Profiles'.

.PARAMETER Branch
    The branch to pull from. Defaults to 'main'.

.PARAMETER InstallPath
    The path where profile files will be installed. Defaults to a 'PowerShell' folder
    in the user's Documents directory.

.PARAMETER SkipActivation
    If specified, the profile will be installed but not activated in the current session.

.PARAMETER UseRawDownload
    Forces the use of direct file downloads instead of git clone, even if git is available.

.EXAMPLE
    Install-RemoteProfile.ps1

    Installs the profile using default settings.

.EXAMPLE
    Install-RemoteProfile.ps1 -UseRawDownload

    Installs the profile by downloading files directly without using git.

.EXAMPLE
    Install-RemoteProfile.ps1 -SkipActivation

    Installs the profile but doesn't activate it in the current session.

.NOTES
    This script is designed to be run with minimal dependencies. It will work even
    if git is not installed on the system.
#>

[CmdletBinding()]
param(
    [string]$GitHubRepo = 'Greg-T8/Profiles',

    [string]$Branch = 'main',

    [string]$InstallPath = "$HOME\Documents\PowerShell",

    [switch]$SkipActivation,

    [switch]$UseRawDownload
)

$ErrorActionPreference = 'Stop'

# Display banner
Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
Write-Host "Repository: $GitHubRepo" -ForegroundColor Gray
Write-Host "Branch: $Branch" -ForegroundColor Gray
Write-Host "Install Path: $InstallPath`n" -ForegroundColor Gray

# Create installation directory if it doesn't exist
if (-not (Test-Path $InstallPath)) {
    Write-Host "Creating installation directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Directory created`n" -ForegroundColor Green
}

# Check if git is available
$gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)

# Determine installation method
if ($gitAvailable -and -not $UseRawDownload) {
    Write-Host "Git detected. Using git clone method..." -ForegroundColor Cyan

    # Clone or update repository
    $repoPath = Join-Path $InstallPath '.repo'

    if (Test-Path $repoPath) {
        Write-Host "Repository exists. Pulling latest changes..." -ForegroundColor Yellow
        Push-Location $repoPath
        try {
            git pull origin $Branch 2>&1 | Out-Null
            Write-Host "✓ Repository updated`n" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to pull updates: $_"
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host "Cloning repository..." -ForegroundColor Yellow
        git clone "https://github.com/$GitHubRepo.git" $repoPath --branch $Branch --depth 1 2>&1 | Out-Null
        Write-Host "✓ Repository cloned`n" -ForegroundColor Green
    }

    # Copy profile files
    $sourceFiles = @('functions.ps1', 'prompt.ps1', 'PSScriptAnalyzerSettings.psd1')

    foreach ($file in $sourceFiles) {
        $sourcePath = Join-Path $repoPath "PowerShell\$file"
        $destPath = Join-Path $InstallPath $file

        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host "✓ Installed $file" -ForegroundColor Green
        }
    }

    # Copy the remote-specific profile version
    $remoteProfileSource = Join-Path $repoPath "PowerShell\profile-remote.ps1"
    $remoteProfileDest = Join-Path $InstallPath "profile.ps1"
    if (Test-Path $remoteProfileSource) {
        Copy-Item -Path $remoteProfileSource -Destination $remoteProfileDest -Force
        Write-Host "✓ Installed profile.ps1 (remote version)" -ForegroundColor Green
    }
}
else {
    if (-not $gitAvailable) {
        Write-Host "Git not detected. Using direct download method..." -ForegroundColor Yellow
    }
    else {
        Write-Host "Using direct download method..." -ForegroundColor Yellow
    }

    # Download files directly from GitHub
    $baseUrl = "https://raw.githubusercontent.com/$GitHubRepo/$Branch/PowerShell"
    $files = @('functions.ps1', 'prompt.ps1', 'PSScriptAnalyzerSettings.psd1')

    foreach ($file in $files) {
        $url = "$baseUrl/$file"
        $destPath = Join-Path $InstallPath $file

        try {
            Write-Host "Downloading $file..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
            Write-Host "✓ Downloaded $file" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to download ${file}: $_"
        }
    }

    # Download the remote-specific profile version as profile.ps1
    try {
        Write-Host "Downloading profile-remote.ps1..." -ForegroundColor Yellow
        $url = "$baseUrl/profile-remote.ps1"
        $destPath = Join-Path $InstallPath "profile.ps1"
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        Write-Host "✓ Downloaded profile.ps1 (remote version)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to download profile-remote.ps1: $_"
    }
}

Write-Host "`n✓ Profile installation complete!" -ForegroundColor Green

# Create or update PowerShell profile to source the installed files
$profilePath = $PROFILE.CurrentUserAllHosts

if (-not (Test-Path $profilePath)) {
    Write-Host "`nCreating PowerShell profile..." -ForegroundColor Yellow
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

# Add dot-source commands to profile if they don't exist
$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue

$dotSourceCommands = @"

# Auto-generated by Install-RemoteProfile.ps1
if (Test-Path '$InstallPath\prompt.ps1') {
    . '$InstallPath\prompt.ps1'
}
if (Test-Path '$InstallPath\functions.ps1') {
    . '$InstallPath\functions.ps1'
}
"@

if ($profileContent -notmatch 'Install-RemoteProfile\.ps1') {
    Write-Host "Updating PowerShell profile to auto-load customizations..." -ForegroundColor Yellow
    Add-Content -Path $profilePath -Value $dotSourceCommands
    Write-Host "✓ Profile updated`n" -ForegroundColor Green
}

# Activate profile in current session
if (-not $SkipActivation) {
    Write-Host "Activating profile in current session..." -ForegroundColor Cyan

    if (Test-Path "$InstallPath\prompt.ps1") {
        . "$InstallPath\prompt.ps1"
        Write-Host "✓ Prompt customizations loaded" -ForegroundColor Green
    }

    if (Test-Path "$InstallPath\functions.ps1") {
        . "$InstallPath\functions.ps1"
        Write-Host "✓ Functions loaded" -ForegroundColor Green
    }

    Write-Host "`n✓ Profile activated! Open a new PowerShell session to use it automatically." -ForegroundColor Green
}
else {
    Write-Host "`nProfile installed but not activated. Restart PowerShell or run:" -ForegroundColor Yellow
    Write-Host ". `$PROFILE" -ForegroundColor Cyan
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Cyan
