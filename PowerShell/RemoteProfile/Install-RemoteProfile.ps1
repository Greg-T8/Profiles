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
    - profile.ps1
    - functions.ps1
    - Modules/MSCloudProfile/MSCloudProfile.psd1
    - Modules/MSCloudProfile/MSCloudProfile.psm1
    - Modules/MSCloudProfile/Public/Get-AllAzProfiles.ps1
    - Modules/MSCloudProfile/Public/Get-CurrentAzProfile.ps1
    - Modules/MSCloudProfile/Public/Use-AzProfile.ps1
    - Modules/MSCloudProfile/Public/Use-AzProfileSubscription.ps1
    - Modules/MSCloudProfile/Public/New-AzProfile.ps1
    - Modules/MSCloudProfile/Public/Remove-AzProfile.ps1
    - Modules/MSCloudProfile/Public/Get-AllMgProfiles.ps1
    - Modules/MSCloudProfile/Public/Get-CurrentMgProfile.ps1
    - Modules/MSCloudProfile/Public/Use-MgProfile.ps1
    - Modules/MSCloudProfile/Public/New-MgProfile.ps1
    - Modules/MSCloudProfile/Public/Remove-MgProfile.ps1
    - Modules/MSCloudProfile/Private/ProfileConfiguration.ps1
    - Modules/MSCloudProfile/Private/AzModuleContext.ps1
    - Modules/MSCloudProfile/Private/MgProfileStore.ps1
    - Modules/MSCloudProfile/Private/MgModuleContext.ps1

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
    Administrator privileges are recommended on Windows for full functionality.
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
    Show-PrivilegeLimitations
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
    $script:onWindows = $null
    $script:isAdmin = $null
    $script:windowsPowerShellPath = $null
    $script:gitAvailable = $null

    function Initialize-PlatformDetection {
        # Detect if running on Windows
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $script:onWindows = Get-Variable -Name 'IsWindows' -ValueOnly -ErrorAction SilentlyContinue
            if ($null -eq $script:onWindows) {
                $script:onWindows = $true
            }
        }
        else {
            $script:onWindows = $true
        }

        # Detect Git once so the requested installation method can be selected consistently.
        $script:gitAvailable = $null -ne (Get-Command -Name git -ErrorAction SilentlyContinue)

        # Check if running as administrator
        $script:isAdmin = $false
        if ($script:onWindows) {
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            $script:isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        # Define Windows PowerShell path if on Windows
        $script:windowsPowerShellPath = if ($script:onWindows) {
            "$HOME\Documents\WindowsPowerShell"
        }
        else {
            $null
        }
    }

    function Show-InstallBanner {
        # Display installation banner with configuration details
        # Normalize path separators for display based on platform
        $displayInstallPath = if ($script:onWindows) { $InstallPath } else { $InstallPath -replace '\\', '/' }

        Write-Host "`n=== PowerShell Profile Installer ===" -ForegroundColor Cyan
        Write-Host "Repository: $GitHubRepo" -ForegroundColor Gray
        Write-Host "Branch: $Branch" -ForegroundColor Gray
        Write-Host "Install Paths:" -ForegroundColor Gray
        Write-Host "  PowerShell Core: $displayInstallPath" -ForegroundColor Gray

        if ($script:windowsPowerShellPath) {
            $displayWindowsPath = $script:windowsPowerShellPath -replace '\\', '/'
            Write-Host "  Windows PowerShell: $displayWindowsPath" -ForegroundColor Gray
        }

        if ($script:onWindows) {
            Write-Host "Running as Administrator: $(if ($script:isAdmin) { '[OK]' } else { '[FAIL]' })" -ForegroundColor $(if ($script:isAdmin) { 'Green' } else { 'Red' })
        }
        Write-Host ""
    }

    function Show-PrivilegeLimitations {
        # Warn when running without Administrator privileges on Windows
        if ($script:onWindows -and -not $script:isAdmin) {
            Write-Host ""
            Write-Host "============================================================" -ForegroundColor Yellow
            Write-Host "[WARNING] Running without Administrator privileges on Windows." -ForegroundColor Yellow
            Write-Host "[WARNING] Installation will continue with limited capabilities." -ForegroundColor Yellow
            Write-Host "============================================================" -ForegroundColor Yellow
            Write-Host "  - LocalMachine execution policy changes are skipped." -ForegroundColor Yellow
            Write-Host "  - Execution policy changes (if needed) are applied only to CurrentUser scope." -ForegroundColor Yellow
            Write-Host "  - Some repository/provider trust operations may fail if machine policy blocks them." -ForegroundColor Yellow
            Write-Host ""
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
                    Write-Host "[INFO] Not elevated: skipping LocalMachine execution policy changes." -ForegroundColor Cyan
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
        # Select Git by default when available unless raw download was explicitly requested.
        if ($script:gitAvailable -and -not $UseRawDownload) {
            Install-ProfileWithGit
        }
        else {
            Install-ProfileWithDownload
        }
    }

    function Get-ProfilePayload {
        # Return the complete relative file set required by profile.ps1 at runtime.
        @(
            'profile.ps1'
            'functions.ps1'
            'Modules/MSCloudProfile/MSCloudProfile.psd1'
            'Modules/MSCloudProfile/MSCloudProfile.psm1'
            'Modules/MSCloudProfile/Public/Get-AllAzProfiles.ps1'
            'Modules/MSCloudProfile/Public/Get-CurrentAzProfile.ps1'
            'Modules/MSCloudProfile/Public/Use-AzProfile.ps1'
            'Modules/MSCloudProfile/Public/Use-AzProfileSubscription.ps1'
            'Modules/MSCloudProfile/Public/New-AzProfile.ps1'
            'Modules/MSCloudProfile/Public/Remove-AzProfile.ps1'
            'Modules/MSCloudProfile/Public/Get-AllMgProfiles.ps1'
            'Modules/MSCloudProfile/Public/Get-CurrentMgProfile.ps1'
            'Modules/MSCloudProfile/Public/Use-MgProfile.ps1'
            'Modules/MSCloudProfile/Public/New-MgProfile.ps1'
            'Modules/MSCloudProfile/Public/Remove-MgProfile.ps1'
            'Modules/MSCloudProfile/Private/ProfileConfiguration.ps1'
            'Modules/MSCloudProfile/Private/AzModuleContext.ps1'
            'Modules/MSCloudProfile/Private/MgProfileStore.ps1'
            'Modules/MSCloudProfile/Private/MgModuleContext.ps1'
        )
    }

    function Copy-ProfilePayload {
        # Copy a previously verified profile payload into one PowerShell profile directory.
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$SourceRoot,

            [Parameter(Mandatory)]
            [string]$DestinationRoot
        )

        $payload = Get-ProfilePayload
        $missingFile = @(
            foreach ($relativePath in $payload) {
                $sourcePath = Join-Path $SourceRoot $relativePath
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                    $sourcePath
                }
            }
        )

        # Refuse partial installation when any required source file is missing.
        if ($missingFile.Count -gt 0) {
            throw "Required profile payload is incomplete: $($missingFile -join ', ')"
        }

        # Recreate the payload's relative directory structure at the destination.
        foreach ($relativePath in $payload) {
            $sourcePath = Join-Path $SourceRoot $relativePath
            $destinationPath = Join-Path $DestinationRoot $relativePath
            $destinationParent = Split-Path -Parent $destinationPath

            if (-not (Test-Path -LiteralPath $destinationParent)) {
                New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
            }

            $resolvedSource = (Resolve-Path -LiteralPath $sourcePath).Path
            $resolvedDestination = if (Test-Path -LiteralPath $destinationPath) {
                (Resolve-Path -LiteralPath $destinationPath).Path
            }
            else {
                $destinationPath
            }

            # Avoid copying a file over itself when the installation and active profile roots match.
            if ($resolvedSource -ne $resolvedDestination) {
                Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
            }
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
                git fetch origin $Branch 2>&1 | Out-Null
                git reset --hard "origin/$Branch" 2>&1 | Out-Null
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

        $sourceRoot = Join-Path $tempRepoPath 'PowerShell'

        # Copy the complete payload to the PowerShell Core directory when available.
        if (Test-Path $InstallPath) {
            Write-Host "Installing to PowerShell Core directory..." -ForegroundColor Cyan
            Copy-ProfilePayload -SourceRoot $sourceRoot -DestinationRoot $InstallPath
            Write-Host "  [OK] Installed profile payload" -ForegroundColor Green
        }

        # Copy the complete payload to the Windows PowerShell directory on Windows.
        if ($script:onWindows -and $script:windowsPowerShellPath) {
            if (-not (Test-Path $script:windowsPowerShellPath)) {
                New-Item -ItemType Directory -Path $script:windowsPowerShellPath -Force | Out-Null
            }
            Write-Host "`nInstalling to Windows PowerShell directory..." -ForegroundColor Cyan
            Copy-ProfilePayload -SourceRoot $sourceRoot -DestinationRoot $script:windowsPowerShellPath
            Write-Host "  [OK] Installed profile payload" -ForegroundColor Green
        }
    }

    function Install-ProfileWithDownload {
        # Download the complete profile payload into an isolated staging directory.
        if (-not $script:gitAvailable) {
            Write-Host "Git not detected. Using direct download method..." -ForegroundColor Yellow
        }
        else {
            Write-Host "Using direct download method..." -ForegroundColor Yellow
        }

        $baseUrl = "https://raw.githubusercontent.com/$GitHubRepo/$Branch/PowerShell"
        $stagingRoot = Join-Path `
            -Path ([System.IO.Path]::GetTempPath()) `
            -ChildPath "PowerShellProfile-$([guid]::NewGuid())"

        try {
            # Download every required file before changing either destination.
            foreach ($relativePath in Get-ProfilePayload) {
                $stagingPath = Join-Path $stagingRoot $relativePath
                $stagingParent = Split-Path -Parent $stagingPath
                if (-not (Test-Path -LiteralPath $stagingParent)) {
                    New-Item -ItemType Directory -Path $stagingParent -Force | Out-Null
                }

                $urlPath = $relativePath.Replace('\', '/')
                Write-Host "  Downloading $relativePath..." -ForegroundColor Yellow
                Invoke-WebRequest `
                    -Uri "$baseUrl/$urlPath" `
                    -OutFile $stagingPath `
                    -UseBasicParsing
            }

            # Install the verified staging payload into each applicable PowerShell directory.
            if (Test-Path $InstallPath) {
                Write-Host "Installing to PowerShell Core directory..." -ForegroundColor Cyan
                Copy-ProfilePayload -SourceRoot $stagingRoot -DestinationRoot $InstallPath
                Write-Host "  [OK] Installed profile payload" -ForegroundColor Green
            }

            if ($script:onWindows -and $script:windowsPowerShellPath) {
                Write-Host "`nInstalling to Windows PowerShell directory..." -ForegroundColor Cyan
                Copy-ProfilePayload -SourceRoot $stagingRoot -DestinationRoot $script:windowsPowerShellPath
                Write-Host "  [OK] Installed profile payload" -ForegroundColor Green
            }

            Write-Host "  [OK] Downloaded complete profile payload" -ForegroundColor Green
        }
        finally {
            # Remove the isolated staging directory after success or failure.
            if (Test-Path -LiteralPath $stagingRoot) {
                Remove-Item -LiteralPath $stagingRoot -Recurse -Force
            }
        }
    }

    function Install-PSReadLineModule {
        # Install latest PSReadLine module for current PowerShell session
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
                -Scope CurrentUser `
                -Confirm:$false `
                -Repository PSGallery

            $ProgressPreference = $originalProgressPreference

            $newVersion = Get-Module -ListAvailable -Name PSReadLine |
                Sort-Object Version -Descending |
                Select-Object -First 1

            Write-Host "[OK] PSReadLine version $($newVersion.Version) installed successfully" -ForegroundColor Green

            # If on Windows and running PowerShell Core, also install for Windows PowerShell
            if ($script:onWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
                Write-Host "`nInstalling PSReadLine for Windows PowerShell..." -ForegroundColor Cyan

                # Find Windows PowerShell executable
                $windowsPSPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

                if (Test-Path $windowsPSPath) {
                    # Build a script block that sets up the environment and installs PSReadLine
                    $installScript = @'
# Set execution policy for this process
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# Install NuGet provider
Write-Host "Checking NuGet provider..." -ForegroundColor Yellow
$nuget = Get-PackageProvider -Name NuGet -Force -ForceBootstrap -ErrorAction SilentlyContinue
if ($nuget) {
    Write-Host "[OK] NuGet provider installed" -ForegroundColor Green
}

# Suppress progress and prompts
$ProgressPreference = 'SilentlyContinue'

# Install PSReadLine
Write-Host "Installing PSReadLine from PSGallery..." -ForegroundColor Yellow
Install-Module -Name PSReadLine -Force -AllowClobber -SkipPublisherCheck -Scope CurrentUser -Confirm:$false -Repository PSGallery

# Verify installation
$psReadLine = Get-Module -ListAvailable -Name PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
if ($psReadLine) {
    Write-Host "[OK] PSReadLine version $($psReadLine.Version) installed" -ForegroundColor Green
}
'@

                    # Execute the installation script in Windows PowerShell
                    $result = & $windowsPSPath -NoProfile -Command $installScript 2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[OK] PSReadLine installed for Windows PowerShell" -ForegroundColor Green
                    }
                    else {
                        Write-Warning "Could not install PSReadLine for Windows PowerShell. Exit code: $LASTEXITCODE"
                        if ($result) {
                            Write-Host "Output: $result" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to install/update PSReadLine: $_"
            Write-Host "You can manually install it later with: Install-Module PSReadLine -Force -SkipPublisherCheck" -ForegroundColor Yellow
            $ProgressPreference = $originalProgressPreference
        }
    }

    function Update-ProfileScript {
        # Copy the installed payload into each active PowerShell profile directory.
        Write-Host "`nConfiguring PowerShell profiles..." -ForegroundColor Cyan

        $profilePaths = @()

        # Select the source matching the edition that is running the installer.
        $currentSourceRoot = if ($PSVersionTable.PSVersion.Major -ge 6) {
            $InstallPath
        }
        else {
            $script:windowsPowerShellPath
        }

        # Always configure the current edition's all-hosts profile directory.
        $profilePaths += @{
            DestinationRoot = Split-Path -Parent $PROFILE.CurrentUserAllHosts
            Name            = if ($PSVersionTable.PSVersion.Major -ge 6) { 'PowerShell Core' } else { 'Windows PowerShell' }
            SourceRoot      = $currentSourceRoot
        }

        # When running PowerShell Core on Windows, configure Windows PowerShell as well.
        if ($script:onWindows -and $PSVersionTable.PSVersion.Major -ge 6 -and $script:windowsPowerShellPath) {
            $windowsPowerShellProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\profile.ps1'
            $profilePaths += @{
                DestinationRoot = Split-Path -Parent $windowsPowerShellProfilePath
                Name            = 'Windows PowerShell'
                SourceRoot      = $script:windowsPowerShellPath
            }
        }

        # Copy the complete payload so profile.ps1 always has its local dependencies.
        foreach ($profileInfo in $profilePaths) {
            $profileName = $profileInfo.Name
            $sourceRoot = $profileInfo.SourceRoot
            $destinationRoot = $profileInfo.DestinationRoot

            if (-not (Test-Path -LiteralPath $sourceRoot)) {
                Write-Host "  [WARNING] Source profile directory not found at: $sourceRoot" -ForegroundColor Yellow
                continue
            }

            if (-not (Test-Path -LiteralPath $destinationRoot)) {
                New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
            }

            $resolvedSource = (Resolve-Path -LiteralPath $sourceRoot).Path
            $resolvedDestination = (Resolve-Path -LiteralPath $destinationRoot).Path
            if ($resolvedSource -eq $resolvedDestination) {
                Write-Host "  $profileName profile payload already in place at: $destinationRoot" -ForegroundColor Green
                continue
            }

            Write-Host "  Updating $profileName profile payload: $destinationRoot" -ForegroundColor Yellow
            Copy-ProfilePayload -SourceRoot $sourceRoot -DestinationRoot $destinationRoot
            Write-Host "  [OK] $profileName profile payload updated" -ForegroundColor Green
        }
    }

    function Enable-ProfileInSession {
        # Activate profile in current session or inform user how to activate
        Write-Host "`n[INFO] Profile installation complete!" -ForegroundColor Cyan
        Write-Host ""

        if ($script:onWindows) {
            Write-Host "Your profile has been installed to:" -ForegroundColor Gray
            if ($script:windowsPowerShellPath) {
                Write-Host "  - Windows PowerShell: $script:windowsPowerShellPath\profile.ps1" -ForegroundColor Gray
            }
            if (Test-Path $InstallPath) {
                Write-Host "  - PowerShell Core: $InstallPath\profile.ps1" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "Your profile has been installed to: $InstallPath/profile.ps1" -ForegroundColor Gray
        }

        Write-Host ""

        # Determine if running PowerShell Core or Windows PowerShell
        if ($PSVersionTable.PSEdition -eq 'Core') {
            # PowerShell Core - reload profile in current session
            Write-Host "Loading profile in current session..." -ForegroundColor Yellow
            try {
                . $PROFILE.CurrentUserAllHosts
                Write-Host "[OK] Profile loaded successfully!" -ForegroundColor Green
                Write-Host "The profile will also load automatically in all new PowerShell sessions." -ForegroundColor Gray
            }
            catch {
                Write-Warning "Failed to load profile: $_"
                Write-Host "Please close this session and open a new one to activate your profile." -ForegroundColor Yellow
            }
        }
        else {
            # Windows PowerShell - advise to restart
            Write-Host "To activate your new profile, please close this PowerShell session and open a new one." -ForegroundColor Yellow
            Write-Host "The profile will load automatically in all new PowerShell sessions." -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "To reload the profile in your current session, run:" -ForegroundColor Cyan
        Write-Host "  . `$PROFILE.CurrentUserAllHosts" -ForegroundColor White
        Write-Host ""
    }

    function Show-InstallComplete {
        # Display completion message
        Write-Host "`n=== Installation Complete ===" -ForegroundColor Cyan
        Write-Host "`nInstalled file:" -ForegroundColor Gray
        Write-Host "  - profile.ps1 (root profile entrypoint)" -ForegroundColor Gray
        Write-Host "  - functions.ps1 (PowerShell 7 productivity commands)" -ForegroundColor Gray
        Write-Host "  - Modules/MSCloudProfile (Az, Graph, and Entra profile management)" -ForegroundColor Gray
        Write-Host ""
    }
}

try {
    # Only change directory if PSScriptRoot is available (not when invoked via iex from URL)
    if ($PSScriptRoot) {
        Push-Location -Path $PSScriptRoot
    }
    & $Main
}
finally {
    if ($PSScriptRoot) {
        Pop-Location
    }
}
