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

    Files installed:
    - profile.ps1  (main profile script containing all customizations)

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
    This script requires administrator privileges on Windows systems.
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

$Main = {
    # Dot-source the helper functions
    . $Helpers

    # Main installation workflow
    Initialize-PlatformDetection
    Show-InstallBanner
    Confirm-AdministratorRole
    Set-PowerShellExecutionPolicy
    Install-NuGetProvider
    New-InstallationDirectory
    Install-ProfileFile
    Install-PSReadLineModule
    Update-ProfileScript
    Enable-ProfileInSession
    Show-InstallComplete
}

$Helpers = {
    # Script-level variables
    $script:isWindows = $null
    $script:isAdmin = $null
    $script:windowsPowerShellPath = $null
    $script:gitAvailable = $null

    function Initialize-PlatformDetection {
        # Detect if running on Windows
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $script:isWindows = Get-Variable -Name 'IsWindows' -ValueOnly -ErrorAction SilentlyContinue
            if ($null -eq $script:isWindows) {
                $script:isWindows = $true
            }
        }
        else {
            $script:isWindows = $true
        }

        # Check if running as administrator
        $script:isAdmin = $false
        if ($script:isWindows) {
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            $script:isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        # Define Windows PowerShell path if on Windows
        $script:windowsPowerShellPath = if ($script:isWindows) {
            "$HOME\Documents\WindowsPowerShell"
        }
        else {
            $null
        }

        # Check if git is available
        $script:gitAvailable = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
    }

    function Show-InstallBanner {
        # Display installation banner with configuration details
        Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
        Write-Host "Repository: $GitHubRepo" -ForegroundColor Gray
        Write-Host "Branch: $Branch" -ForegroundColor Gray
        Write-Host "Install Paths:" -ForegroundColor Gray
        Write-Host "  PowerShell Core: $InstallPath" -ForegroundColor Gray

        if ($script:windowsPowerShellPath) {
            Write-Host "  Windows PowerShell: $script:windowsPowerShellPath" -ForegroundColor Gray
        }

        if ($script:isWindows) {
            Write-Host "Running as Administrator: $(if ($script:isAdmin) { '[OK]' } else { '[FAIL]' })" -ForegroundColor $(if ($script:isAdmin) { 'Green' } else { 'Red' })
        }
        Write-Host ""
    }

    function Confirm-AdministratorRole {
        # Verify administrator privileges on Windows
        if ($script:isWindows -and -not $script:isAdmin) {
            Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
            Write-Host "`n[ERROR] This script must be run as Administrator." -ForegroundColor Red
            Write-Host "`nPlease restart PowerShell with administrator privileges and try again." -ForegroundColor Yellow
            Write-Host "Right-click PowerShell and select 'Run as Administrator'`n" -ForegroundColor Yellow
            exit 1
        }
    }

    function Set-PowerShellExecutionPolicy {
        # Configure execution policy if needed
        $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser

        if ($executionPolicy -eq 'Restricted' -or $executionPolicy -eq 'Undefined') {
            Write-Host "[WARNING] Execution policy is currently: $executionPolicy" -ForegroundColor Yellow

            try {
                if ($script:isAdmin) {
                    Write-Host "Setting execution policy to RemoteSigned (LocalMachine scope)..." -ForegroundColor Yellow
                    Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
                    Write-Host "[OK] Execution policy updated for all users`n" -ForegroundColor Green
                }
                else {
                    Write-Host "Setting execution policy to RemoteSigned (CurrentUser scope)..." -ForegroundColor Yellow
                    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                    Write-Host "[OK] Execution policy updated for current user`n" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "[WARNING] Could not set execution policy: $_" -ForegroundColor Yellow
                Write-Host "Profile will be installed but may not load automatically in new sessions." -ForegroundColor Yellow
                Write-Host "To enable profile loading, run:" -ForegroundColor Cyan
                Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`n" -ForegroundColor White
            }
        }
    }

    function Install-NuGetProvider {
        # Install NuGet provider for PSGallery access (required for module installation)
        Write-Host "Checking NuGet provider..." -ForegroundColor Cyan

        # Check if NuGet is already available
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue -ListAvailable

        if (-not $nugetProvider) {
            Write-Host "Installing NuGet provider automatically..." -ForegroundColor Yellow

            # Use Get-PackageProvider with -Force to bootstrap without prompting
            try {
                Get-PackageProvider -Name NuGet -Force -ForceBootstrap | Out-Null
                Write-Host "[OK] NuGet provider installed`n" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to install NuGet provider: $_"
            }
        }
        else {
            Write-Host "[OK] NuGet provider already installed`n" -ForegroundColor Green
        }

        # Ensure PSGallery is trusted
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
            Write-Host "Setting PSGallery as trusted repository..." -ForegroundColor Yellow
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            Write-Host "[OK] PSGallery is now trusted`n" -ForegroundColor Green
        }
    }

    function New-InstallationDirectory {
        # Create Windows PowerShell directory if it doesn't exist
        if ($script:windowsPowerShellPath -and -not (Test-Path $script:windowsPowerShellPath)) {
            Write-Host "Creating Windows PowerShell installation directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $script:windowsPowerShellPath -Force |
                Out-Null
            Write-Host "[OK] Directory created" -ForegroundColor Green
        }

        # Check if PowerShell Core directory exists (only create if PowerShell Core is installed)
        if (Test-Path $InstallPath) {
            Write-Host "PowerShell Core directory exists: $InstallPath" -ForegroundColor Gray
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 6) {
            # We're running in PowerShell Core, so create the directory
            Write-Host "Creating PowerShell Core installation directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $InstallPath -Force |
                Out-Null
            Write-Host "[OK] Directory created" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] PowerShell Core directory not found - will skip PowerShell Core installation" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    function Install-ProfileFile {
        # Install profile files using git clone or direct download
        if ($script:gitAvailable -and -not $UseRawDownload) {
            Install-ProfileWithGit
        }
        else {
            Install-ProfileWithDownload
        }
    }

    function Install-ProfileWithGit {
        # Clone or update repository using git
        Write-Host "Git detected. Using git clone method..." -ForegroundColor Cyan

        $tempRepoPath = Join-Path $env:TEMP '.profile-repo'

        if (Test-Path $tempRepoPath) {
            Write-Host "Repository exists. Pulling latest changes..." -ForegroundColor Yellow
            Push-Location $tempRepoPath
            try {
                git pull origin $Branch 2>&1 | Out-Null
                Write-Host "[OK] Repository updated`n" -ForegroundColor Green
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
            git clone "https://github.com/$GitHubRepo.git" $tempRepoPath --branch $Branch --depth 1 2>&1 |
                Out-Null
            Write-Host "[OK] Repository cloned`n" -ForegroundColor Green
        }

        $sourceFile = Join-Path $tempRepoPath "PowerShell\profile.ps1"

        # Copy to PowerShell Core directory if it exists
        if (Test-Path $InstallPath) {
            Write-Host "Installing to PowerShell Core directory..." -ForegroundColor Cyan
            $destPath = Join-Path $InstallPath "profile.ps1"

            if (Test-Path $sourceFile) {
                Copy-Item -Path $sourceFile -Destination $destPath -Force
                Write-Host "  [OK] Installed profile.ps1" -ForegroundColor Green
            }
        }

        # Copy to Windows PowerShell directory
        if ($script:windowsPowerShellPath -and (Test-Path $script:windowsPowerShellPath)) {
            Write-Host "`nInstalling to Windows PowerShell directory..." -ForegroundColor Cyan
            $destPath = Join-Path $script:windowsPowerShellPath "profile.ps1"

            if (Test-Path $sourceFile) {
                Copy-Item -Path $sourceFile -Destination $destPath -Force
                Write-Host "  [OK] Installed profile.ps1" -ForegroundColor Green
            }
        }
    }

    function Install-ProfileWithDownload {
        # Download files directly from GitHub
        if (-not $script:gitAvailable) {
            Write-Host "Git not detected. Using direct download method..." -ForegroundColor Yellow
        }
        else {
            Write-Host "Using direct download method..." -ForegroundColor Yellow
        }

        $url = "https://raw.githubusercontent.com/$GitHubRepo/$Branch/PowerShell/profile.ps1"

        # Download to PowerShell Core directory if it exists
        if (Test-Path $InstallPath) {
            Write-Host "Downloading to PowerShell Core directory..." -ForegroundColor Cyan
            $destPath = Join-Path $InstallPath "profile.ps1"

            try {
                Write-Host "  Downloading profile.ps1..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
                Write-Host "  [OK] Downloaded profile.ps1" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to download profile.ps1: $_"
            }
        }

        # Download to Windows PowerShell directory
        if ($script:windowsPowerShellPath -and (Test-Path $script:windowsPowerShellPath)) {
            Write-Host "`nDownloading to Windows PowerShell directory..." -ForegroundColor Cyan
            $destPath = Join-Path $script:windowsPowerShellPath "profile.ps1"

            try {
                Write-Host "  Downloading profile.ps1..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
                Write-Host "  [OK] Downloaded profile.ps1" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to download profile.ps1: $_"
            }
        }
    }

    function Install-PSReadLineModule {
        # Install latest PSReadLine module (Windows includes an older version by default)
        Write-Host "`nInstalling latest PSReadLine module..." -ForegroundColor Cyan

        try {
            $psReadLine = Get-Module -ListAvailable -Name PSReadLine |
                Sort-Object Version -Descending |
                Select-Object -First 1

            if ($psReadLine) {
                Write-Host "Current PSReadLine version: $($psReadLine.Version)" -ForegroundColor Gray
            }

            Write-Host "Installing latest PSReadLine from PSGallery..." -ForegroundColor Yellow

            # Suppress all prompts during installation
            $originalProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

            Install-Module -Name PSReadLine `
                -Force `
                -AllowClobber `
                -SkipPublisherCheck `
                -Scope AllUsers `
                -Confirm:$false `
                -Repository PSGallery

            $ProgressPreference = $originalProgressPreference

            $newVersion = Get-Module -ListAvailable -Name PSReadLine |
                Sort-Object Version -Descending |
                Select-Object -First 1

            Write-Host "[OK] PSReadLine version $($newVersion.Version) installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to install/update PSReadLine: $_"
            Write-Host "You can manually install it later with: Install-Module PSReadLine -Force -SkipPublisherCheck" -ForegroundColor Yellow
            $ProgressPreference = $originalProgressPreference
        }
    }

    function Update-ProfileScript {
        # Configure PowerShell profile scripts to load installed files
        $profilePaths = @()

        # Always add current PowerShell profile
        $profilePaths += @{
            Path = $PROFILE.CurrentUserAllHosts
            Name = if ($PSVersionTable.PSVersion.Major -ge 6) { "PowerShell Core" } else { "Windows PowerShell" }
        }

        # If on Windows and running PowerShell Core, also configure Windows PowerShell
        if ($script:isWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
            $windowsPowerShellProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\profile.ps1'
            $profilePaths += @{
                Path = $windowsPowerShellProfilePath
                Name = "Windows PowerShell"
            }
        }

        # Create or update profile scripts
        foreach ($profileInfo in $profilePaths) {
            $profilePath = $profileInfo.Path
            $profileName = $profileInfo.Name

            Write-Host "`nConfiguring $profileName profile..." -ForegroundColor Cyan

            # Determine the source path for this profile type
            if ($profileName -eq "Windows PowerShell" -and $script:windowsPowerShellPath) {
                $sourceProfilePath = Join-Path $script:windowsPowerShellPath 'profile.ps1'
            }
            else {
                $sourceProfilePath = Join-Path $InstallPath 'profile.ps1'
            }

            # Copy the installed profile.ps1 to the profile location
            if (Test-Path $sourceProfilePath) {
                Write-Host "Copying profile.ps1 to: $profilePath" -ForegroundColor Yellow

                # Ensure parent directory exists
                $profileDir = Split-Path -Parent $profilePath
                if (-not (Test-Path $profileDir)) {
                    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
                }

                Copy-Item -Path $sourceProfilePath -Destination $profilePath -Force
                Write-Host "[OK] $profileName profile updated" -ForegroundColor Green
            }
            else {
                Write-Host "[WARNING] Source profile not found at: $sourceProfilePath" -ForegroundColor Yellow
            }
        }
    }

    function Enable-ProfileInSession {
        # Inform user to restart session for profile to take effect
        Write-Host "`n[INFO] Profile installation complete!" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To activate your new profile, please close this PowerShell session and open a new one." -ForegroundColor Yellow
        Write-Host ""

        if ($script:isWindows) {
            Write-Host "Your profile has been installed to:" -ForegroundColor Gray
            Write-Host "  - Windows PowerShell: $script:windowsPowerShellPath\profile.ps1" -ForegroundColor Gray

            if (Test-Path $InstallPath) {
                Write-Host "  - PowerShell Core: $InstallPath\profile.ps1" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "Your profile has been installed to: $InstallPath\profile.ps1" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "The profile will load automatically in all new PowerShell sessions." -ForegroundColor Gray
    }

    function Show-InstallComplete {
        # Display completion message
        Write-Host "`n=== Installation Complete ===" -ForegroundColor Cyan
        Write-Host "`nInstalled file:" -ForegroundColor Gray
        Write-Host "  - profile.ps1 (main profile script with all customizations)" -ForegroundColor Gray
        Write-Host ""
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
