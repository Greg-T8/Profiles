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

# Detect if running on Windows
if ($PSVersionTable.PSVersion.Major -ge 6) {
    # PowerShell Core - use automatic variable
    $isWindows = Get-Variable -Name 'IsWindows' -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $isWindows) {
        $isWindows = $true
    }
}
else {
    # Windows PowerShell only runs on Windows
    $isWindows = $true
}

# Check if running as administrator
$isAdmin = $false
if ($isWindows) {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Require administrator mode
if ($isWindows -and -not $isAdmin) {
    Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
    Write-Host "`n❌ This script must be run as Administrator." -ForegroundColor Red
    Write-Host "`nPlease restart PowerShell with administrator privileges and try again." -ForegroundColor Yellow
    Write-Host "Right-click PowerShell and select 'Run as Administrator'`n" -ForegroundColor Yellow
    exit 1
}

# Define installation paths
$windowsPowerShellPath = if ($isWindows) {
    "$HOME\Documents\Windows PowerShell"
}
else {
    $null
}

# Display banner
Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
Write-Host "Repository: $GitHubRepo" -ForegroundColor Gray
Write-Host "Branch: $Branch" -ForegroundColor Gray
Write-Host "Install Paths:" -ForegroundColor Gray
Write-Host "  PowerShell Core: $InstallPath" -ForegroundColor Gray
if ($windowsPowerShellPath) {
    Write-Host "  Windows PowerShell: $windowsPowerShellPath" -ForegroundColor Gray
}
if ($isWindows) {
    Write-Host "Running as Administrator: ✓" -ForegroundColor Green
}
Write-Host ""

# Check and configure execution policy
$executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($executionPolicy -eq 'Restricted' -or $executionPolicy -eq 'Undefined') {
    Write-Host "⚠ Execution policy is currently: $executionPolicy" -ForegroundColor Yellow

    # Attempt to set execution policy
    try {
        if ($isAdmin) {
            Write-Host "Setting execution policy to RemoteSigned (LocalMachine scope)..." -ForegroundColor Yellow
            Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
            Write-Host "✓ Execution policy updated for all users`n" -ForegroundColor Green
        }
        else {
            Write-Host "Setting execution policy to RemoteSigned (CurrentUser scope)..." -ForegroundColor Yellow
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host "✓ Execution policy updated for current user`n" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "⚠ Could not set execution policy: $_" -ForegroundColor Yellow
        Write-Host "Profile will be installed but may not load automatically in new sessions." -ForegroundColor Yellow
        Write-Host "To enable profile loading, run:" -ForegroundColor Cyan
        Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`n" -ForegroundColor White
    }
}

# Install NuGet provider if needed (for PSGallery access)
Write-Host "Checking NuGet provider..." -ForegroundColor Cyan
$nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue

if (-not $nugetProvider) {
    try {
        Write-Host "Installing NuGet provider..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        Write-Host "✓ NuGet provider installed`n" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to install NuGet provider: $_"
    }
}
else {
    Write-Host "✓ NuGet provider already installed`n" -ForegroundColor Green
}

# Create installation directories if they don't exist
if (-not (Test-Path $InstallPath)) {
    Write-Host "Creating PowerShell installation directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
}

if ($windowsPowerShellPath -and -not (Test-Path $windowsPowerShellPath)) {
    Write-Host "Creating Windows PowerShell installation directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $windowsPowerShellPath -Force | Out-Null
    Write-Host "✓ Directory created" -ForegroundColor Green
}
Write-Host ""

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

    # Copy profile files to PowerShell Core directory
    $sourceFiles = @('functions.ps1', 'prompt.ps1', 'PSScriptAnalyzerSettings.psd1')

    Write-Host "Installing to PowerShell Core directory..." -ForegroundColor Cyan
    foreach ($file in $sourceFiles) {
        $sourcePath = Join-Path $repoPath "PowerShell\$file"
        $destPath = Join-Path $InstallPath $file

        if (Test-Path $sourcePath) {
            Copy-Item -Path $sourcePath -Destination $destPath -Force
            Write-Host "  ✓ Installed $file" -ForegroundColor Green
        }
    }

    # Copy the remote-specific profile version
    $remoteProfileSource = Join-Path $repoPath "PowerShell\profile-remote.ps1"
    $remoteProfileDest = Join-Path $InstallPath "profile.ps1"
    if (Test-Path $remoteProfileSource) {
        Copy-Item -Path $remoteProfileSource -Destination $remoteProfileDest -Force
        Write-Host "  ✓ Installed profile.ps1 (remote version)" -ForegroundColor Green
    }

    # Copy profile files to Windows PowerShell directory if on Windows
    if ($windowsPowerShellPath) {
        Write-Host "`nInstalling to Windows PowerShell directory..." -ForegroundColor Cyan
        foreach ($file in $sourceFiles) {
            $sourcePath = Join-Path $repoPath "PowerShell\$file"
            $destPath = Join-Path $windowsPowerShellPath $file

            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-Host "  ✓ Installed $file" -ForegroundColor Green
            }
        }

        # Copy the remote-specific profile version to Windows PowerShell
        $destPath = Join-Path $windowsPowerShellPath "profile.ps1"
        if (Test-Path $remoteProfileSource) {
            Copy-Item -Path $remoteProfileSource -Destination $destPath -Force
            Write-Host "  ✓ Installed profile.ps1 (remote version)" -ForegroundColor Green
        }
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

    # Download to PowerShell Core directory
    Write-Host "Downloading to PowerShell Core directory..." -ForegroundColor Cyan
    foreach ($file in $files) {
        $url = "$baseUrl/$file"
        $destPath = Join-Path $InstallPath $file

        try {
            Write-Host "  Downloading $file..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
            Write-Host "  ✓ Downloaded $file" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to download ${file}: $_"
        }
    }

    # Download the remote-specific profile version as profile.ps1
    try {
        Write-Host "  Downloading profile-remote.ps1..." -ForegroundColor Yellow
        $url = "$baseUrl/profile-remote.ps1"
        $destPath = Join-Path $InstallPath "profile.ps1"
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
        Write-Host "  ✓ Downloaded profile.ps1 (remote version)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to download profile-remote.ps1: $_"
    }

    # Download to Windows PowerShell directory if on Windows
    if ($windowsPowerShellPath) {
        Write-Host "`nDownloading to Windows PowerShell directory..." -ForegroundColor Cyan
        foreach ($file in $files) {
            $url = "$baseUrl/$file"
            $destPath = Join-Path $windowsPowerShellPath $file

            try {
                Write-Host "  Downloading $file..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
                Write-Host "  ✓ Downloaded $file" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to download ${file}: $_"
            }
        }

        # Download the remote-specific profile version as profile.ps1
        try {
            Write-Host "  Downloading profile-remote.ps1..." -ForegroundColor Yellow
            $url = "$baseUrl/profile-remote.ps1"
            $destPath = Join-Path $windowsPowerShellPath "profile.ps1"
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
            Write-Host "  ✓ Downloaded profile.ps1 (remote version)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to download profile-remote.ps1: $_"
        }
    }
}

Write-Host "`n✓ Profile installation complete!" -ForegroundColor Green

# Install PSReadLine module from PSGallery
Write-Host "`nInstalling PSReadLine module..." -ForegroundColor Cyan

try {
    # Check if PSReadLine is already installed
    $psReadLine = Get-Module -ListAvailable -Name PSReadLine | Sort-Object Version -Descending | Select-Object -First 1

    if ($psReadLine) {
        Write-Host "PSReadLine version $($psReadLine.Version) is already installed" -ForegroundColor Gray
        Write-Host "Checking for updates..." -ForegroundColor Yellow

        # Try to update to latest version
        try {
            Update-Module -Name PSReadLine -Force -ErrorAction Stop
            Write-Host "✓ PSReadLine updated to latest version" -ForegroundColor Green
        }
        catch {
            Write-Host "✓ PSReadLine is up to date" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Installing PSReadLine from PSGallery..." -ForegroundColor Yellow
        Install-Module -Name PSReadLine -Force -AllowClobber -Scope AllUsers
        Write-Host "✓ PSReadLine installed successfully" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to install/update PSReadLine: $_"
    Write-Host "You can manually install it later with: Install-Module PSReadLine -Force" -ForegroundColor Yellow
}

# Determine which profile paths to configure
$profilePaths = @()

# Always add current PowerShell profile
$profilePaths += @{
    Path = $PROFILE.CurrentUserAllHosts
    Name = if ($PSVersionTable.PSVersion.Major -ge 6) { "PowerShell Core" } else { "Windows PowerShell" }
}

# If on Windows and running PowerShell Core, also configure Windows PowerShell
if ($isWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    $windowsPowerShellProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Windows PowerShell\profile.ps1'
    $profilePaths += @{
        Path = $windowsPowerShellProfilePath
        Name = "Windows PowerShell"
    }
}

# Create or update profile(s) to source the installed files
foreach ($profileInfo in $profilePaths) {
    $profilePath = $profileInfo.Path
    $profileName = $profileInfo.Name

    Write-Host "`nConfiguring $profileName profile..." -ForegroundColor Cyan

    # Create profile if it doesn't exist
    if (-not (Test-Path $profilePath)) {
        Write-Host "Creating profile at: $profilePath" -ForegroundColor Yellow
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
        Write-Host "Updating profile to auto-load customizations..." -ForegroundColor Yellow
        Add-Content -Path $profilePath -Value $dotSourceCommands
        Write-Host "✓ $profileName profile updated" -ForegroundColor Green
    }
    else {
        Write-Host "✓ $profileName profile already configured" -ForegroundColor Green
    }
}

# Activate profile in current session
if (-not $SkipActivation) {
    Write-Host "`nActivating profile in current session..." -ForegroundColor Cyan

    try {
        if (Test-Path "$InstallPath\prompt.ps1") {
            . "$InstallPath\prompt.ps1"
            Write-Host "✓ Prompt customizations loaded" -ForegroundColor Green
        }

        if (Test-Path "$InstallPath\functions.ps1") {
            . "$InstallPath\functions.ps1"
            Write-Host "✓ Functions loaded" -ForegroundColor Green
        }

        $sessionType = if ($PSVersionTable.PSVersion.Major -ge 6) { "PowerShell Core" } else { "Windows PowerShell" }
        Write-Host "`n✓ Profile activated in current $sessionType session!" -ForegroundColor Green

        if ($isWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
            Write-Host "  (Windows PowerShell profile also configured - will load automatically there)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "`n⚠ Could not activate profile in current session (execution policy restriction)" -ForegroundColor Yellow
        Write-Host "Your profile has been installed successfully and will load automatically in new sessions." -ForegroundColor Yellow
        Write-Host "`nTo enable it in this session, run:" -ForegroundColor Cyan
        Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor White
        Write-Host "  . `$PROFILE" -ForegroundColor White
    }
}
else {
    Write-Host "`nProfile installed but not activated. To activate, restart PowerShell or run:" -ForegroundColor Yellow
    Write-Host ". `$PROFILE" -ForegroundColor Cyan
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Cyan
