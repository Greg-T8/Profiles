#region UTILITY FUNCTIONS

# Reverts to the default dir function in cmd.exe
function dir {
    cmd /c dir $args
}


# Converts tab-delimited clipboard data to PowerShell objects (for Excel copy-paste).
function Get-ClipboardExcel {
    Get-Clipboard | ConvertFrom-Csv -Delimiter "`t"
}

# Opens VSCode with a temporary user data directory, or cleans up the temp directory if -Clean is specified.
function tempcode {
    param (
        [switch]$Clean
    )
    $tempDir = "$env:TEMP/tempvscode"
    if (-not $Clean) {
        # Open a new VSCode window with the current directory as the working directory
        & code --user-data-dir=$tempDir --extensions-dir="$tempDir/extensions"
        return
    }
    else {
        # Remove the temp VSCode user data and extensions directories
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}


# Downloads and outputs the Microsoft license catalog as PowerShell objects.
function GetMicrosoftLicenseCatalog {
    [OutputType([PSCustomObject[]])]
    $url = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
    $response = Invoke-WebRequest -Uri $Url
    $csvLink = $response.Links | Select-Object href | Where-Object { $_ -match 'csv' } |
        Select-Object -ExpandProperty href
    $licenseCatalog = Invoke-RestMethod -Uri $csvLink
    $licenseCatalog = $licenseCatalog | ConvertFrom-Csv
    Write-Output $licenseCatalog
}

# Runs Snagit capture cleanup via the dedicated maintenance script.
function CleanUpSnagitFolder {
    $cleanupScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Maintenance\Invoke-SnagitCaptureFolderCleanup.ps1'

    if (-not (Test-Path -Path $cleanupScriptPath)) {
        Write-Error "Cleanup script not found: $cleanupScriptPath"
        return
    }

    & $cleanupScriptPath
}

# Creates a file if it doesn't exist, or updates its last modified time if it does (like Unix 'touch').
function touch {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        # Update last modified time
        (Get-Item $Path).LastWriteTime = Get-Date
    }
    else {
        # Create the file
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

# Retrieves the Windows Experience Index (WEI) score and assessment date.
function Get-WinExperienceIndex {
    [CmdletBinding()]
    param (
        [switch]$Recalculate
    )

    if ($Recalculate) {
        Write-Host 'Running WinSAT assessment... This may take several minutes.' -ForegroundColor Yellow
        winsat formal | Out-Null
    }

    # Retrieve the latest WinSAT data
    $result = Get-CimInstance -ClassName Win32_WinSAT

    if (-not $result) {
        Write-Error 'No WinSAT results found. Try running with -Recalculate.'
        return
    }

    # Get latest assessment date from DataStore
    $dataStore = Get-ChildItem "$env:WinDir\Performance\WinSAT\DataStore" `
        -Filter '*Formal.Assessment*.WinSAT.xml' `
    | Sort-Object LastWriteTime -Descending `
    | Select-Object -First 1

    $assessmentDate = if ($dataStore) { $dataStore.LastWriteTime } else { $null }

    # Output results
    [PSCustomObject]@{
        CPUScore        = $result.CPUScore
        D3DScore        = $result.D3DScore
        DiskScore       = $result.DiskScore
        GraphicsScore   = $result.GraphicsScore
        MemoryScore     = $result.MemoryScore
        WinSPRLevel     = $result.WinSPRLevel
        AssessmentDate  = $assessmentDate
    }
}

function Get-WinGetUpdates {
    param(
        [switch]$IncludeUnknown
    )

    Get-WinGetPackage |
        Where-Object {
            $_.IsUpdateAvailable -or
            (
                $IncludeUnknown -and
                [string]::Equals("$($_.InstalledVersion)", 'Unknown', [System.StringComparison]::OrdinalIgnoreCase)
            )
        } |
        Select-Object Name, Id, InstalledVersion, IsUpdateAvailable,
            @{n='AvailableVersions'; e={ $_.AvailableVersions | Select-Object -First 1 }}
}

function Measure-ProfileLoad {
    <#
    .SYNOPSIS
        Measures PowerShell profile loading time with detailed metrics.

    .DESCRIPTION
        Measures baseline PowerShell startup vs. profile load time and uses
        Measure-Script to identify the slowest operations in the profile.

        With -ShowTiming, displays section-by-section timing checkpoints to help
        identify which parts of your profile are slow (module imports, PSReadLine
        configuration, etc.).

    .PARAMETER Iterations
        Number of iterations to run for averaging. Default is 3.

    .PARAMETER ShowTiming
        Shows detailed timing checkpoints for each profile section. Requires adding
        timing instrumentation to your profile.ps1 (see NOTES).

    .EXAMPLE
        Measure-ProfileLoad

    .EXAMPLE
        Measure-ProfileLoad -Iterations 5

    .EXAMPLE
        Measure-ProfileLoad -ShowTiming -Iterations 1

    .NOTES
        To enable -ShowTiming, add this to the top of your profile.ps1:

        $script:ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
        function script:Write-ProfileTime($label) {
            if ($env:PROFILE_TIMING) {
                $elapsed = $script:ProfileTimer.Elapsed.TotalMilliseconds
                Write-Host ("  [{0,6:N1}ms] {1}" -f $elapsed, $label) -ForegroundColor DarkGray
            }
        }

        Then add checkpoints throughout:
        Write-ProfileTime "After PSReadLine import"
        Write-ProfileTime "After PSReadLine config"
        etc.
    #>
    [CmdletBinding()]
    param(
        [int]$Iterations = 3,
        [switch]$ShowTiming
    )

    # Ensure PSProfiler module is available
    if (-not (Get-Command Measure-Script -ErrorAction SilentlyContinue)) {
        Write-Warning "PSProfiler module not found. Install with: Install-Module PSProfiler"
        Write-Warning "Falling back to basic timing only..."
    }

    Write-Host "`nMeasuring PowerShell profile load times..." -ForegroundColor Cyan
    if ($ShowTiming) {
        Write-Host "Timing mode: Detailed section breakdown enabled" -ForegroundColor Yellow
    }
    Write-Host "Running $Iterations iterations...`n" -ForegroundColor Gray

    # Enable timing flag if requested
    if ($ShowTiming) {
        $env:PROFILE_TIMING = "1"
    }

    # Measure baseline (no profile)
    $baselineTimes = 1..$Iterations | ForEach-Object {
        Write-Host "  Baseline $_/$Iterations..." -NoNewline
        $ms = (Measure-Command { pwsh -NoProfile -Command "exit" }).TotalMilliseconds
        Write-Host " $([math]::Round($ms, 2))ms" -ForegroundColor Gray
        $ms
    }

    # Measure with profile
    $profileTimes = 1..$Iterations | ForEach-Object {
        if ($ShowTiming) {
            Write-Host "`n  Profile $_/$Iterations with section timing:" -ForegroundColor Yellow
            $ms = (Measure-Command { pwsh -Command "exit" }).TotalMilliseconds
            Write-Host ("  Total: {0}ms`n" -f [math]::Round($ms, 2)) -ForegroundColor Gray
        } else {
            Write-Host "  Profile $_/$Iterations..." -NoNewline
            $ms = (Measure-Command { pwsh -Command "exit" }).TotalMilliseconds
            Write-Host " $([math]::Round($ms, 2))ms" -ForegroundColor Gray
        }
        $ms
    }

    # Clean up timing flag
    if ($ShowTiming) {
        Remove-Item Env:\PROFILE_TIMING -ErrorAction SilentlyContinue
    }

    $avgBaseline = ($baselineTimes | Measure-Object -Average).Average
    $avgWithProfile = ($profileTimes | Measure-Object -Average).Average
    $avgOverhead = $avgWithProfile - $avgBaseline

    # Get detailed line timing using Measure-Script
    $topOpsTable = $null
    if ((Test-Path $PROFILE.CurrentUserAllHosts) -and (Get-Command Measure-Script -ErrorAction SilentlyContinue)) {
        Write-Host "`n  Analyzing profile with Measure-Script..." -ForegroundColor Gray
        try {
            $queue = [System.Collections.Generic.Queue[string]]::new()
            $seen  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $root  = (Resolve-Path $PROFILE.CurrentUserAllHosts).ProviderPath
            $queue.Enqueue($root)

            $allResults = @()

            while ($queue.Count -gt 0) {
                $scriptPath = $queue.Dequeue()
                if (-not (Test-Path $scriptPath)) { continue }
                if (-not $seen.Add($scriptPath)) { continue }

                try {
                    $results = Measure-Script -Path $scriptPath
                    if ($results) {
                        $allResults += $results | ForEach-Object {
                            $_ | Add-Member -NotePropertyName Source -NotePropertyValue $scriptPath -PassThru
                        }
                    }
                }
                catch {
                    Write-Verbose "Measure-Script failed for $scriptPath`: $_"
                }

                try {
                    $dir = Split-Path $scriptPath
                    Get-Content $scriptPath | ForEach-Object {
                        if ($_ -match '^\s*\.\s+(.+?)\s*(#.*)?$') {
                            $raw = $matches[1].Trim().Trim("'`"")
                            if (-not $raw) { return }
                            $expanded = $ExecutionContext.InvokeCommand.ExpandString($raw)
                            $candidate = if (Test-Path $expanded) { $expanded } else { Join-Path $dir $expanded }
                            if (Test-Path $candidate) {
                                $resolved = (Resolve-Path $candidate -ErrorAction SilentlyContinue).ProviderPath
                                if ($resolved) { $queue.Enqueue($resolved) }
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "Failed to inspect dot-sourced paths in $scriptPath`: $_"
                }
            }

            if ($allResults) {
                $topOps = $allResults |
                    Sort-Object -Property {
                        $et = $_.ExecutionTime
                        if ($et -is [TimeSpan])       { $et.TotalMilliseconds }
                        elseif ($et -is [double])     { [TimeSpan]::FromSeconds($et).TotalMilliseconds }
                        elseif ($et -is [decimal])    { [TimeSpan]::FromSeconds([double]$et).TotalMilliseconds }
                        elseif ($et -is [int] -or $et -is [long]) { [double]$et }
                        else { 0 }
                    } -Descending |
                    Select-Object -First 5

                if ($topOps) {
                    $topOpsTable = $topOps |
                        ForEach-Object {
                            $execution = $_.ExecutionTime
                            $timeSpan =
                                if     ($execution -is [TimeSpan]) { $execution }
                                elseif ($execution -is [double])   { [TimeSpan]::FromSeconds($execution) }
                                elseif ($execution -is [decimal])  { [TimeSpan]::FromSeconds([double]$execution) }
                                elseif ($execution -is [int] -or $execution -is [long]) { [TimeSpan]::FromMilliseconds($execution) }
                                else { [TimeSpan]::Zero }

                            [pscustomobject]@{
                                Line        = $_.Line
                                'Time Taken' = $timeSpan.ToString("mm':'ss'.'fffffff")
                                Source      = if ($_.Source) { $_.Source } else { $root }
                            }
                        } |
                        Format-Table -Property Line, 'Time Taken', Source -AutoSize | Out-String
                }
            }
        }
        catch {
            Write-Warning "Measure-Script analysis failed: $_"
        }
    }

    # Display results
    Write-Host "`n=== Profile Load Performance ===" -ForegroundColor Cyan
    Write-Host ("Baseline (no profile):  {0}ms" -f [math]::Round($avgBaseline, 2)) -ForegroundColor Green
    Write-Host ("With profile:           {0}ms" -f [math]::Round($avgWithProfile, 2)) -ForegroundColor Yellow

    $color = if ($avgOverhead -lt 500) { 'Green' } elseif ($avgOverhead -lt 1000) { 'Yellow' } else { 'Red' }
    Write-Host ("Profile overhead:       {0}ms" -f [math]::Round($avgOverhead, 2)) -ForegroundColor $color

    Write-Host "`nNote: Measure-Script only captures executable lines. Missing from timing:" -ForegroundColor Gray
    Write-Host "  • Script parsing/compilation overhead" -ForegroundColor DarkGray
    Write-Host "  • Function definition overhead" -ForegroundColor DarkGray
    Write-Host "  • Module import internal operations" -ForegroundColor DarkGray
    Write-Host "  • PSReadLine configuration (~100-200ms typical)" -ForegroundColor DarkGray
    Write-Host "  • Subexpression evaluation overhead" -ForegroundColor DarkGray

    if ($topOpsTable) {
        Write-Host "`n=== Top 5 Slowest Operations ===" -ForegroundColor Cyan
        Write-Host ($topOpsTable.TrimEnd())
    }
    elseif ((Test-Path $PROFILE.CurrentUserAllHosts) -and (Get-Command Measure-Script -ErrorAction SilentlyContinue)) {
        Write-Host "`n  (Measure-Script returned no data)" -ForegroundColor Gray
    }

    # Return summary
    [PSCustomObject]@{
        BaselineAvg     = [math]::Round($avgBaseline, 2)
        WithProfileAvg  = [math]::Round($avgWithProfile, 2)
        ProfileOverhead = [math]::Round($avgOverhead, 2)
        BaselineTimes   = $baselineTimes | ForEach-Object { [math]::Round($_, 2) }
        ProfileTimes    = $profileTimes  | ForEach-Object { [math]::Round($_, 2) }
    }
}

function Install-WSLDistribution {
    <#
    .SYNOPSIS
        Installs a WSL distribution to a custom location.

    .DESCRIPTION
        Installs a WSL distribution using web-download, then exports and re-imports
        it to a custom location under D:\WSL\<name>. This allows you to store WSL
        distributions on a non-system drive and use custom names.

    .PARAMETER Distribution
        The distribution to install (e.g., Ubuntu, Debian, kali-linux).
        If not provided, you will be prompted to enter it.

    .PARAMETER Name
        The custom name for the distribution (no spaces allowed).
        If not provided, you will be prompted to enter it.

    .PARAMETER BasePath
        The base path where WSL distributions will be stored.
        Defaults to D:\WSL.

    .EXAMPLE
        Install-WSLDistribution -Distribution Ubuntu -Name MyUbuntu

    .EXAMPLE
        Install-WSLDistribution
        # Prompts for distribution and name

    .NOTES
        Requires WSL to be enabled and administrative privileges may be required
        for the initial installation.
    #>
    [CmdletBinding()]
    param(
        [string]$Distribution,
        [string]$Name,
        [string]$BasePath = 'D:\WSL'
    )

    # Prompt for distribution if not provided
    if (-not $Distribution) {
        $Distribution = Read-Host 'Enter the WSL distribution to install (e.g., Ubuntu, Debian, kali-linux)'
    }

    # Prompt for custom name if not provided
    if (-not $Name) {
        $Name = Read-Host 'Enter a custom name for the distribution (no spaces)'
    }

    # Validate name has no spaces
    if ($Name -match '\s') {
        Write-Error 'Distribution name cannot contain spaces. Please use a name without spaces.'
        return
    }

    # Validate distribution name is not empty
    if ([string]::IsNullOrWhiteSpace($Distribution)) {
        Write-Error 'Distribution name cannot be empty.'
        return
    }

    # Validate custom name is not empty
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Error 'Custom name cannot be empty.'
        return
    }

    # Check if the target distribution name already exists
    $existingDistros = wsl --list --quiet
    if ($existingDistros -contains $Name) {
        Write-Error "A distribution named '$Name' already exists. Please choose a different name."
        return
    }

    # Create target directory
    $targetPath = Join-Path $BasePath $Name
    if (-not (Test-Path $targetPath)) {
        Write-Host "Creating directory: $targetPath" -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }

    # Use a unique temporary name to avoid conflicts
    $tempName = "TEMP_$Distribution_$(Get-Date -Format 'yyyyMMddHHmmss')"

    # Install the distribution with web-download using temporary name
    Write-Host "`nInstalling $Distribution as temporary distribution '$tempName'..." -ForegroundColor Cyan
    try {
        wsl --install -d $Distribution --web-download --name $tempName --no-launch
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install $Distribution. Exit code: $LASTEXITCODE"
            return
        }
    }
    catch {
        Write-Error "Failed to install $Distribution`: $_"
        return
    }

    # Wait for installation to complete
    Write-Host 'Waiting for installation to complete...' -ForegroundColor Yellow
    Start-Sleep -Seconds 5

    # Export the distribution
    $tarPath = Join-Path $targetPath "$Name.tar"
    Write-Host "`nExporting $tempName to $tarPath..." -ForegroundColor Cyan
    try {
        wsl --export $tempName $tarPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to export $tempName. Exit code: $LASTEXITCODE"
            return
        }
    }
    catch {
        Write-Error "Failed to export $tempName`: $_"
        return
    }

    # Unregister the temporary distribution
    Write-Host "`nUnregistering temporary distribution $tempName..." -ForegroundColor Cyan
    try {
        wsl --unregister $tempName
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to unregister $tempName. Exit code: $LASTEXITCODE"
        }
    }
    catch {
        Write-Warning "Failed to unregister $tempName`: $_"
    }

    # Import to the custom location with custom name
    Write-Host "`nImporting $Name to $targetPath..." -ForegroundColor Cyan
    try {
        wsl --import $Name $targetPath $tarPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to import $Name. Exit code: $LASTEXITCODE"
            return
        }
    }
    catch {
        Write-Error "Failed to import $Name`: $_"
        return
    }

    # Success message
    Write-Host "`n✓ Successfully installed $Name to $targetPath" -ForegroundColor Green

    # Run initialization script
    $initScript = "$PSScriptRoot\..\Linux\init-wsl.sh"
    if (Test-Path $initScript) {
        Write-Host "`nRunning initialization script..." -ForegroundColor Cyan

        # Convert Windows path to WSL path
        $windowsInitPath = (Resolve-Path $initScript).Path
        $wslInitPath = ($windowsInitPath -replace '\\', '/' -replace '^([A-Z]):', '/mnt/$1').ToLower()

        # Copy script to /tmp and make it executable
        Write-Host "Copying init-wsl.sh to WSL distribution..." -ForegroundColor Cyan
        $bashCmd = "cp '$wslInitPath' /tmp/init-wsl.sh; chmod +x /tmp/init-wsl.sh"
        wsl -d $Name -- bash -c $bashCmd

        # Run the script as root
        Write-Host "Running initialization script as root..." -ForegroundColor Cyan
        wsl -d $Name --user root -- /tmp/init-wsl.sh

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n✓ Initialization script completed successfully" -ForegroundColor Green

            # Get the default user from the script output
            $defaultUser = wsl -d $Name --user root -- cat /tmp/wsl-default-user.txt 2>$null
            if ($defaultUser) {
                $defaultUser = $defaultUser.Trim()
                Write-Host "Setting default user to: $defaultUser" -ForegroundColor Cyan

                # Set default user in /etc/wsl.conf
                $bashCmd = "echo '[user]' > /etc/wsl.conf; echo 'default=$defaultUser' >> /etc/wsl.conf"
                wsl -d $Name --user root -- bash -c $bashCmd

                # Terminate the distribution to apply settings
                Write-Host "Restarting WSL distribution to apply settings..." -ForegroundColor Cyan
                wsl --terminate $Name
                Start-Sleep -Seconds 2

                Write-Host "`n✓ Default user set to: $defaultUser" -ForegroundColor Green
            }
        } else {
            Write-Warning "Initialization script completed with warnings or errors"
        }
    } else {
        Write-Warning "Initialization script not found at: $initScript"
        Write-Host "Expected location: $initScript" -ForegroundColor Yellow
    }

    Write-Host "`nTo start the distribution, run: wsl -d $Name" -ForegroundColor Yellow
    Write-Host "To set it as default, run: wsl" '--set-default' "$Name" -ForegroundColor Yellow
}

#endregion

#region AZURE & GRAPH PROFILE MANAGEMENT
# Functions for managing multiple Azure CLI contexts and Microsoft Graph /
# Microsoft Entra contexts across accounts/tenants. The Azure CLI side uses a
# per-profile AZURE_CONFIG_DIR; the Graph/Entra side uses per-profile file-swap
# isolation under ~/.mg/profiles/<name>/ because the Microsoft.Graph SDK has no
# config-dir environment variable. Az and Mg profile switching are independent.
# Profiles are defined as top-level keys in $Personal and $Work configs.

function Get-AzProfiles {
    <#
    .SYNOPSIS
        Lists Azure CLI profiles from both PersonalConfig and WorkConfig and the profiles directory.
    .DESCRIPTION
        Scans ~/.azure/profiles directory for existing profile directories and
        combines with profiles defined in PersonalConfig.psd1 and/or WorkConfig.psd1.
        Shows login status and configuration details for each profile.

        ConfigSource values:
        - PersonalConfig: Defined in PersonalConfig.psd1 only
        - WorkConfig: Defined in WorkConfig.psd1 only
        - Both: Defined in both config files (Personal takes precedence)
        - DiskOnly: Config directory exists but not in any config file
    .PARAMETER ConfiguredOnly
        Shows only profiles defined in PersonalConfig or WorkConfig.psd1.
    .PARAMETER DiscoveredOnly
        Shows only profiles found in ~/.azure/profiles directory without config.
    .EXAMPLE
        Get-AzProfiles
        Lists all profiles from both sources.
    .EXAMPLE
        Get-AzProfiles -ConfiguredOnly
        Shows only profiles defined in config files.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$ConfiguredOnly,

        [Parameter()]
        [switch]$DiscoveredOnly
    )

    . $script:AzureCliProfileHelpers

    $profilesDir = Join-Path $HOME ".azure\profiles"
    $allProfiles = @{}
    $configSources = @{}  # Track which configs define each profile

    $azModuleAvailable = $null -ne (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)
    $azModuleCurrentContext = $null
    $azModuleContexts = @()

    if ($azModuleAvailable) {
        try {
            $azModuleCurrentContext = Get-AzContext -ErrorAction SilentlyContinue
            $azModuleContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue)
        }
        catch {
            $azModuleCurrentContext = $null
            $azModuleContexts = @()
        }
    }

    # Check for default Azure profile (used when AZURE_CONFIG_DIR is not set)
    if (-not $ConfiguredOnly.IsPresent) {
        $defaultConfigDir = Join-Path $HOME ".azure"
        $defaultConfigFile = Join-Path $defaultConfigDir "azureProfile.json"
        $isLoggedIn = Test-Path $defaultConfigFile
        $currentUser = $null
        $tenantId = $null

        if ($isLoggedIn) {
            try {
                $azProfile = Get-Content $defaultConfigFile | ConvertFrom-Json
                if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                    $currentUser = $azProfile.subscriptions[0].user.name
                    $tenantId = $azProfile.subscriptions[0].tenantId
                }
            }
            catch {
                $currentUser = "(cached)"
            }
        }

        # Always show default profile if .azure directory exists
        if (Test-Path $defaultConfigDir) {
            $allProfiles['(default)'] = [PSCustomObject][ordered]@{
                Name        = '(default)'
                Description = 'Default Azure CLI profile'
                Account     = $null
                SubscriptionId = $null
                AzConfigDir = $defaultConfigDir
                LoggedIn    = $isLoggedIn
                CurrentUser = $currentUser
                TenantId    = $tenantId
                ConfigSource = 'Default'
                AzCliAccount = $null
                AzCliSubscriptionId = $null
                AzCliConfigDir = $defaultConfigDir
                AzCliIsLoggedIn = $isLoggedIn
                AzCliLoggedIn = $isLoggedIn
                AzCliCurrentUser = $currentUser
                AzCliUser = $currentUser
                AzCliTenantId = $tenantId
                HasAzModule = $azModuleAvailable
                AzModuleLoggedIn = $false
                AzModuleContextName = $null
                AzModuleAccount = $null
                AzModuleTenantId = $null
                AzModuleSubscription = $null
                AzModuleSubscriptionId = $null
                AzModuleIsCurrent = $false
            }
        }
    }

    # Discover profiles from disk
    if (-not $ConfiguredOnly.IsPresent -and (Test-Path $profilesDir)) {
        $discoveredDirs = Get-ChildItem -Path $profilesDir -Directory

        foreach ($dir in $discoveredDirs) {
            $name = $dir.Name
            $configFile = Join-Path $dir.FullName "azureProfile.json"
            $isLoggedIn = Test-Path $configFile
            $currentUser = $null
            $tenantId = $null

            if ($isLoggedIn) {
                try {
                    $azProfile = Get-Content $configFile | ConvertFrom-Json
                    if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                        $currentUser = $azProfile.subscriptions[0].user.name
                        $tenantId = $azProfile.subscriptions[0].tenantId
                    }
                }
                catch {
                    $currentUser = "(cached)"
                }
            }

            $allProfiles[$name] = [PSCustomObject][ordered]@{
                Name        = $name
                Description = $null
                Account     = $null
                SubscriptionId = $null
                AzConfigDir = $dir.FullName
                LoggedIn    = $isLoggedIn
                CurrentUser = $currentUser
                TenantId    = $tenantId
                ConfigSource = $null  # Will be set based on config files
                AzCliAccount = $null
                AzCliSubscriptionId = $null
                AzCliConfigDir = $dir.FullName
                AzCliIsLoggedIn = $isLoggedIn
                AzCliLoggedIn = $isLoggedIn
                AzCliCurrentUser = $currentUser
                AzCliUser = $currentUser
                AzCliTenantId = $tenantId
                HasAzModule = $azModuleAvailable
                AzModuleLoggedIn = $false
                AzModuleContextName = $null
                AzModuleAccount = $null
                AzModuleTenantId = $null
                AzModuleSubscription = $null
                AzModuleSubscriptionId = $null
                AzModuleIsCurrent = $false
            }
            # Initialize tracking - this is discovered but not yet in any config
            $configSources[$name] = @()
        }
    }

    # Merge with configured profiles from Personal and Work configs
    if (-not $DiscoveredOnly.IsPresent) {
        # Check Personal config
        $personalProfiles = Get-AzureProfilesFromConfig -Config $Personal
        if ($personalProfiles.Count -gt 0) {
            foreach ($name in $personalProfiles.Keys) {
                $profileConfig = $personalProfiles[$name]
                $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
                $configDir = Join-Path $HOME ".azure\profiles\$name"
                $configFile = Join-Path $configDir "azureProfile.json"
                $isLoggedIn = Test-Path $configFile
                $currentUser = $null

                if ($isLoggedIn) {
                    try {
                        $azProfile = Get-Content $configFile | ConvertFrom-Json
                        if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                            $currentUser = $azProfile.subscriptions[0].user.name
                        }
                    }
                    catch {
                        $currentUser = "(cached)"
                    }
                }

                # Track that this profile is in Personal config
                if (-not $configSources.ContainsKey($name)) {
                    $configSources[$name] = @()
                }
                $configSources[$name] += 'PersonalConfig'

                if ($allProfiles.ContainsKey($name)) {
                    # Profile already exists (was on disk), update it
                    $allProfiles[$name].Description = $profileConfig.Description
                    $allProfiles[$name].Account = $profileConfig.Account
                    $allProfiles[$name].AzCliAccount = $profileConfig.Account
                    $allProfiles[$name].TenantId = $profileConfig.TenantId
                    $allProfiles[$name].SubscriptionId = $configuredPrimarySub
                    $allProfiles[$name].AzCliSubscriptionId = $configuredPrimarySub
                }
                else {
                    # Add Personal config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $configuredPrimarySub
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $configuredPrimarySub
                        AzCliConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        AzCliIsLoggedIn = $isLoggedIn
                        AzCliLoggedIn = $isLoggedIn
                        AzCliCurrentUser = $currentUser
                        AzCliUser = $currentUser
                        AzCliTenantId = $profileConfig.TenantId
                        HasAzModule = $azModuleAvailable
                        AzModuleLoggedIn = $false
                        AzModuleContextName = $null
                        AzModuleAccount = $null
                        AzModuleTenantId = $null
                        AzModuleSubscription = $null
                        AzModuleSubscriptionId = $null
                        AzModuleIsCurrent = $false
                    }
                }
            }
        }

        # Check Work config
        $workProfiles = Get-AzureProfilesFromConfig -Config $Work
        if ($workProfiles.Count -gt 0) {
            foreach ($name in $workProfiles.Keys) {
                $profileConfig = $workProfiles[$name]
                $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
                $configDir = Join-Path $HOME ".azure\profiles\$name"
                $configFile = Join-Path $configDir "azureProfile.json"
                $isLoggedIn = Test-Path $configFile
                $currentUser = $null

                if ($isLoggedIn) {
                    try {
                        $azProfile = Get-Content $configFile | ConvertFrom-Json
                        if ($azProfile.subscriptions -and $azProfile.subscriptions.Count -gt 0) {
                            $currentUser = $azProfile.subscriptions[0].user.name
                        }
                    }
                    catch {
                        $currentUser = "(cached)"
                    }
                }

                # Track that this profile is in Work config
                if (-not $configSources.ContainsKey($name)) {
                    $configSources[$name] = @()
                }
                $configSources[$name] += 'WorkConfig'

                if ($allProfiles.ContainsKey($name)) {
                    # Profile already exists, update it
                    $allProfiles[$name].Description = $profileConfig.Description
                    $allProfiles[$name].Account = $profileConfig.Account
                    $allProfiles[$name].AzCliAccount = $profileConfig.Account
                    $allProfiles[$name].TenantId = $profileConfig.TenantId
                    $allProfiles[$name].SubscriptionId = $configuredPrimarySub
                    $allProfiles[$name].AzCliSubscriptionId = $configuredPrimarySub
                }
                else {
                    # Add Work config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $configuredPrimarySub
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $configuredPrimarySub
                        AzCliConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        AzCliIsLoggedIn = $isLoggedIn
                        AzCliLoggedIn = $isLoggedIn
                        AzCliCurrentUser = $currentUser
                        AzCliUser = $currentUser
                        AzCliTenantId = $profileConfig.TenantId
                        HasAzModule = $azModuleAvailable
                        AzModuleLoggedIn = $false
                        AzModuleContextName = $null
                        AzModuleAccount = $null
                        AzModuleTenantId = $null
                        AzModuleSubscription = $null
                        AzModuleSubscriptionId = $null
                        AzModuleIsCurrent = $false
                    }
                }
            }
        }
    }

    # Set ConfigSource based on which config files define each profile
    foreach ($name in $allProfiles.Keys) {
        if ($configSources.ContainsKey($name) -and $configSources[$name].Count -gt 0) {
            if ($configSources[$name].Count -eq 2) {
                $allProfiles[$name].ConfigSource = 'Both'
            }
            elseif ($configSources[$name] -contains 'PersonalConfig') {
                $allProfiles[$name].ConfigSource = 'PersonalConfig'
            }
            else {
                $allProfiles[$name].ConfigSource = 'WorkConfig'
            }
        }
        elseif ($null -ne $allProfiles[$name].AzConfigDir -and -not $configSources.ContainsKey($name)) {
            $allProfiles[$name].ConfigSource = 'DiskOnly'
        }

        if ($azModuleAvailable -and $azModuleContexts.Count -gt 0) {
            $profileRecord = $allProfiles[$name]
            $matchingContext = $null

            if ($profileRecord.SubscriptionId) {
                $subscriptionMatches = @($azModuleContexts | Where-Object {
                    $_.Subscription -and $_.Subscription.Id -eq $profileRecord.SubscriptionId
                })

                if ($profileRecord.Account) {
                    $subscriptionMatches = @($subscriptionMatches | Where-Object {
                        $_.Account -and $_.Account.Id -eq $profileRecord.Account
                    })
                }

                if ($subscriptionMatches.Count -gt 0) {
                    $matchingContext = $subscriptionMatches | Where-Object {
                        $_.Name -ieq $name
                    } | Select-Object -First 1

                    if (-not $matchingContext) {
                        $matchingContext = $subscriptionMatches | Select-Object -First 1
                    }
                }
            }

            if (-not $matchingContext -and $profileRecord.TenantId) {
                $tenantMatches = @($azModuleContexts | Where-Object {
                    $_.Tenant -and $_.Tenant.Id -eq $profileRecord.TenantId -and
                    (
                        -not $profileRecord.Account -or
                        ($_.Account -and $_.Account.Id -eq $profileRecord.Account)
                    )
                })

                if ($tenantMatches.Count -gt 0) {
                    $matchingContext = $tenantMatches | Where-Object {
                        $_.Name -ieq $name
                    } | Select-Object -First 1

                    if (-not $matchingContext) {
                        $matchingContext = $tenantMatches | Select-Object -First 1
                    }
                }
            }

            if ($matchingContext) {
                $profileRecord.AzModuleLoggedIn = $true
                $profileRecord.AzModuleContextName = $matchingContext.Name
                $profileRecord.AzModuleAccount = $matchingContext.Account.Id
                $profileRecord.AzModuleTenantId = $matchingContext.Tenant.Id
                $profileRecord.AzModuleSubscription = $matchingContext.Subscription.Name
                $profileRecord.AzModuleSubscriptionId = $matchingContext.Subscription.Id
                $profileRecord.AzModuleIsCurrent = (
                    $azModuleCurrentContext -and
                    $azModuleCurrentContext.Name -eq $matchingContext.Name
                )
            }
        }
    }

    # Return sorted profiles
    return $allProfiles.Values | Sort-Object Name
}

function Get-CurrentAzProfile {
    <#
    .SYNOPSIS
        Shows the current Azure CLI context and profile.
    .DESCRIPTION
        Displays which Azure profile is currently active based on AZURE_CONFIG_DIR,
        and shows the current account/subscription information.
    .EXAMPLE
        Get-CurrentAzProfile
        Shows the current Azure context.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    . $script:AzureCliProfileHelpers

    # Get current CLI config directory
    $currentConfigDir = $env:AZURE_CONFIG_DIR
    if (-not $currentConfigDir) {
        $currentConfigDir = Join-Path $HOME ".azure"
    }

    # Determine profile name from config dir
    $profileName = Split-Path -Leaf $currentConfigDir
    if ($profileName -eq ".azure") {
        $profileName = "(default)"
    }

    # Try to get current Azure CLI account info
    $cliAccountInfo = $null
    try {
        $accountJson = az account show 2>$null
        if ($accountJson) {
            $cliAccountInfo = $accountJson | ConvertFrom-Json
        }
    }
    catch {
        # Not logged in or az CLI not available
    }

    # Get current Az module context info
    $moduleContext = Get-AzModuleCurrentContext

    # Determine whether CLI and Az module are aligned
    $isSynchronized = $false
    if ($cliAccountInfo -and $moduleContext.LoggedIn) {
        $isSynchronized = (
            $cliAccountInfo.tenantId -eq $moduleContext.TenantId -and
            $cliAccountInfo.id -eq $moduleContext.SubscriptionId
        )
    }

    # Return current context
    [PSCustomObject][ordered]@{
        ProfileName    = $profileName
        ConfigDir      = $currentConfigDir
        LoggedIn       = ($null -ne $cliAccountInfo)
        User           = $cliAccountInfo.user.name
        TenantId       = $cliAccountInfo.tenantId
        Subscription   = $cliAccountInfo.name
        SubscriptionId = $cliAccountInfo.id
        ContextSynchronized = $isSynchronized
        AzCliConfigDir = $currentConfigDir
        AzCliIsLoggedIn = ($null -ne $cliAccountInfo)
        AzCliLoggedIn  = ($null -ne $cliAccountInfo)
        AzCliCurrentUser = $cliAccountInfo.user.name
        AzCliUser      = $cliAccountInfo.user.name
        AzCliTenantId  = $cliAccountInfo.tenantId
        AzCliSubscription = $cliAccountInfo.name
        AzCliSubscriptionId = $cliAccountInfo.id
        HasAzModule    = $moduleContext.HasAzModule
        AzModuleLoggedIn = $moduleContext.LoggedIn
        AzModuleContextName = $moduleContext.ContextName
        AzModuleUser   = $moduleContext.Account
        AzModuleTenantId = $moduleContext.TenantId
        AzModuleSubscription = $moduleContext.Subscription
        AzModuleSubscriptionId = $moduleContext.SubscriptionId
    }
}

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
        azp lab
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

    . $script:AzureCliProfileHelpers

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

# Temporarily switches the active Azure subscription for the current profile/session.
function Use-AzProfileSubscription {
    <#
    .SYNOPSIS
        Switches the active Azure subscription for the current profile.
    .DESCRIPTION
        Changes the active Azure CLI subscription in the current AZURE_CONFIG_DIR
        context without modifying configured profile defaults in PersonalConfig
        or WorkConfig.
    .PARAMETER SubscriptionID
        Subscription ID or subscription name.
    .EXAMPLE
        Use-AzProfileSubscription -SubscriptionID '00000000-0000-0000-0000-000000000000'
        Switches the current profile/session to the specified subscription.
    .EXAMPLE
        Use-AzProfileSubscription -SubscriptionID 'Contoso-Prod'
        Switches the current profile/session to a subscription by name.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Subscription')]
        [string]$SubscriptionID
    )

    . $script:AzureCliProfileHelpers

    $accountInfo = $null
    try {
        $accountJson = az account show -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $accountJson) {
            $accountInfo = $accountJson | ConvertFrom-Json
        }
    }
    catch {
        $accountInfo = $null
    }

    if (-not $accountInfo) {
        Write-Error "Not logged in to Azure CLI for the current profile. Run 'Use-AzProfile <name>' or 'az login' first."
        return
    }

    $setOutput = az account set --subscription $SubscriptionID 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($setOutput | Out-String).Trim()
        if ($details) {
            Write-Error "Could not switch to subscription '$SubscriptionID'. $details"
        }
        else {
            Write-Error "Could not switch to subscription '$SubscriptionID'."
        }
        return
    }

    $updatedAccountInfo = $null
    try {
        $updatedAccountJson = az account show -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $updatedAccountJson) {
            $updatedAccountInfo = $updatedAccountJson | ConvertFrom-Json
        }
    }
    catch {
        $updatedAccountInfo = $null
    }

    if (-not $updatedAccountInfo) {
        Write-Error "Subscription switched, but current account context could not be read."
        return
    }

    $profileName = (Get-CurrentAzProfile).ProfileName
    $accountId = if ($updatedAccountInfo.user) { $updatedAccountInfo.user.name } else { $null }
    $azModuleContext = Sync-AzModuleContext -ProfileName $profileName -TenantId $updatedAccountInfo.tenantId -SubscriptionId $updatedAccountInfo.id -AccountId $accountId

    if ($azModuleContext.HasAzModule -and $azModuleContext.SubscriptionId -ne $updatedAccountInfo.id) {
        $setAzContextCommand = Get-Command -Name Set-AzContext -ErrorAction SilentlyContinue

        if ($setAzContextCommand) {
            try {
                $setAzContextParams = @{
                    Subscription = $updatedAccountInfo.id
                    Tenant = $updatedAccountInfo.tenantId
                    ErrorAction = 'Stop'
                }

                $supportsAccountId = $setAzContextCommand.Parameters.ContainsKey('AccountId')
                if ($accountId -and $supportsAccountId) {
                    $setAzContextParams.AccountId = $accountId
                }

                Set-AzContext @setAzContextParams | Out-Null
            }
            catch {
                Write-Warning "Failed to set Az module context to subscription '$($updatedAccountInfo.id)': $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Az PowerShell module is available but Set-AzContext was not found."
        }

        $azModuleContext = Get-AzModuleCurrentContext
        if ($azModuleContext.LoggedIn -and $azModuleContext.SubscriptionId -ne $updatedAccountInfo.id) {
            Write-Warning "Az module context is still on subscription '$($azModuleContext.SubscriptionId)' while Azure CLI is on '$($updatedAccountInfo.id)'."
        }
    }

    [PSCustomObject][ordered]@{
        AzCliIsLoggedIn = $true
        AzCliUser = $updatedAccountInfo.user.name
        AzCliTenantId = $updatedAccountInfo.tenantId
        AzCliSubscription = $updatedAccountInfo.name
        AzCliSubscriptionId = $updatedAccountInfo.id
        HasAzModule = $azModuleContext.HasAzModule
        AzModuleContextName = $azModuleContext.ContextName
        AzModuleUser = $azModuleContext.Account
        AzModuleTenantId = $azModuleContext.TenantId
        AzModuleSubscription = $azModuleContext.Subscription
        AzModuleSubscriptionId = $azModuleContext.SubscriptionId
    }
}


# Register argument completer for Use-AzProfile profile names (for both function and alias)
$azProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    . $script:AzureCliProfileHelpers

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

Register-ArgumentCompleter -CommandName Use-AzProfile, azp -ParameterName Name -ScriptBlock $azProfileCompleter

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

    . $script:AzureCliProfileHelpers


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

function Remove-AzProfile {
    <#
    .SYNOPSIS
        Removes an Azure CLI profile configuration directory.
    .DESCRIPTION
        Removes the Azure CLI config directory for the specified profile and
        optionally removes it from the in-memory configuration.
    .PARAMETER Name
        The profile name to remove.
    .PARAMETER KeepConfig
        Keeps the profile in WorkConfig (only removes the local config dir).
    .EXAMPLE
        Remove-AzProfile -Name 'oldclient'
        Removes the profile's config directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig
    )

    . $script:AzureCliProfileHelpers

    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    $profileConfig = $null
    if ($allConfiguredProfiles.ContainsKey($Name)) {
        $profileConfig = $allConfiguredProfiles[$Name]
    }

    $configDir = Join-Path $HOME ".azure\profiles\$Name"

    # Remove config directory if it exists
    if (Test-Path $configDir) {
        if ($PSCmdlet.ShouldProcess($configDir, "Remove Azure config directory")) {
            Remove-Item -Path $configDir -Recurse -Force
            Write-Host "Removed config directory: $configDir" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Config directory not found: $configDir" -ForegroundColor Yellow
    }

    # Remove matching Az PowerShell module contexts for this profile
    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    $removeAzContextCommand = Get-Command -Name Remove-AzContext -ErrorAction SilentlyContinue

    if ($getAzContextCommand -and $removeAzContextCommand -and $profileConfig) {
        $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
        $matchingContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            ($configuredPrimarySub -and $_.Subscription -and $_.Subscription.Id -eq $configuredPrimarySub) -or
            (
                $profileConfig.TenantId -and
                $_.Tenant -and
                $_.Tenant.Id -eq $profileConfig.TenantId -and
                (
                    -not $profileConfig.Account -or
                    ($_.Account -and $_.Account.Id -eq $profileConfig.Account)
                )
            )
        })

        if ($matchingContexts.Count -gt 0) {
            $contextNames = $matchingContexts | Select-Object -ExpandProperty Name -Unique

            foreach ($contextName in $contextNames) {
                if ($PSCmdlet.ShouldProcess($contextName, "Remove Az PowerShell context")) {
                    try {
                        Remove-AzContext -Name $contextName -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
                        Remove-AzContext -Name $contextName -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "Removed Az PowerShell context: $contextName" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Could not remove Az PowerShell context '$contextName': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # Remove from in-memory config unless KeepConfig is specified
    if (-not $KeepConfig.IsPresent) {
        $removed = $false
        $personalProfiles = Get-AzureProfilesFromConfig -Config $Personal
        $workProfiles = Get-AzureProfilesFromConfig -Config $Work

        if ($personalProfiles.ContainsKey($Name)) {
            if ($Personal.ContainsKey('AzureProfiles') -and $Personal.AzureProfiles -is [hashtable]) {
                $Personal.AzureProfiles.Remove($Name)
            }
            else {
                $Personal.Remove($Name)
            }
            Write-Host "Removed profile from Personal in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from PersonalConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if ($workProfiles.ContainsKey($Name)) {
            if ($Work.ContainsKey('AzureProfiles') -and $Work.AzureProfiles -is [hashtable]) {
                $Work.AzureProfiles.Remove($Name)
            }
            else {
                $Work.Remove($Name)
            }
            Write-Host "Removed profile from Work in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from WorkConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if (-not $removed) {
            Write-Host "Profile '$Name' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completer for Remove-AzProfile
Register-ArgumentCompleter -CommandName Remove-AzProfile -ParameterName Name -ScriptBlock $azProfileCompleter

function Get-MgProfiles {
    <#
    .SYNOPSIS
        Lists Microsoft Graph / Entra profiles from configs and from the on-disk profile cache.
    .DESCRIPTION
        Returns one record per known profile, combining entries from PersonalConfig.psd1,
        WorkConfig.psd1, and any cached profile directories under ~/.mg/profiles/.
        ConfigSource is one of: PersonalConfig, WorkConfig, Both, DiskOnly.
    .EXAMPLE
        Get-MgProfiles
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    . $script:AzureCliProfileHelpers

    # Pull entries from each loaded config and tag their source.
    $personalProfiles = Get-AzureProfilesFromConfig -Config $Personal
    $workProfiles     = Get-AzureProfilesFromConfig -Config $Work

    $combined = @{}

    foreach ($entry in $personalProfiles.GetEnumerator()) {
        $combined[$entry.Key] = @{ Config = $entry.Value; Source = 'PersonalConfig' }
    }

    foreach ($entry in $workProfiles.GetEnumerator()) {
        if ($combined.ContainsKey($entry.Key)) {
            $combined[$entry.Key].Source = 'Both'
        }
        else {
            $combined[$entry.Key] = @{ Config = $entry.Value; Source = 'WorkConfig' }
        }
    }

    # Add disk-only profiles (directories without a matching config entry).
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $combined.ContainsKey($_.Name)) {
                $combined[$_.Name] = @{ Config = $null; Source = 'DiskOnly' }
            }
        }
    }

    $activeName = Get-MgActiveProfileName

    # Project to output records sorted by name.
    $combined.Keys | Sort-Object | ForEach-Object {
        $name   = $_
        $entry  = $combined[$name]
        $cfg    = $entry.Config
        $cached = Get-MgProfileCachedContext -ProfileName $name

        [PSCustomObject][ordered]@{
            Name         = $name
            IsActive     = ($name -ieq $activeName)
            ConfigSource = $entry.Source
            Account      = if ($cfg) { $cfg.Account } else { $cached.Account }
            TenantId     = if ($cfg) { $cfg.TenantId } else { $cached.TenantId }
            MgClientId   = if ($cfg -and $cfg.ContainsKey('MgClientId')) { $cfg.MgClientId } else { $cached.ClientId }
            MgScopes     = if ($cfg -and $cfg.ContainsKey('MgScopes')) { $cfg.MgScopes } else { $cached.Scopes }
            Description  = if ($cfg) { $cfg.Description } else { $null }
            HasCache     = ($null -ne $cached)
        }
    }
}

function Get-CurrentMgProfile {
    <#
    .SYNOPSIS
        Shows the currently active Microsoft Graph / Entra profile and live context.
    .DESCRIPTION
        Reports the active profile name (tracked under ~/.mg/profiles/.active) and
        the live Microsoft.Graph and Microsoft.Entra contexts, if those modules are
        loaded and connected.
    .EXAMPLE
        Get-CurrentMgProfile
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    . $script:AzureCliProfileHelpers

    # Resolve names and gather live contexts from each SDK.
    $activeName   = Get-MgActiveProfileName
    $mgContext    = Get-MgModuleCurrentContext
    $entraContext = Get-EntraModuleCurrentContext

    [PSCustomObject][ordered]@{
        ProfileName        = $activeName
        HasMgModule        = $mgContext.HasMgModule
        MgLoggedIn         = $mgContext.LoggedIn
        MgAccount          = $mgContext.Account
        MgTenantId         = $mgContext.TenantId
        MgClientId         = $mgContext.ClientId
        MgScopes           = $mgContext.Scopes
        MgAuthType         = $mgContext.AuthType
        HasEntraModule     = $entraContext.HasEntraModule
        EntraLoggedIn      = $entraContext.LoggedIn
        EntraAccount       = $entraContext.Account
        EntraTenantId      = $entraContext.TenantId
        EntraClientId      = $entraContext.ClientId
        ContextSynchronized = (
            $mgContext.LoggedIn -and $entraContext.LoggedIn -and
            $mgContext.TenantId -eq $entraContext.TenantId
        )
    }
}

function Use-MgProfile {
    <#
    .SYNOPSIS
        Switches the active Microsoft Graph / Entra profile.
    .DESCRIPTION
        Saves the live ~/.mg files for the previously-active profile, restores any
        cached files for the requested profile, then runs Connect-MgGraph and
        Connect-Entra against the profile's tenant. The Microsoft.Graph SDK has no
        AZURE_CONFIG_DIR equivalent, so per-profile isolation is implemented by
        copying mg.authrecord.json / mg.context.json / mg.graphoptions.json in and
        out of ~/.mg/ for each switch.
    .PARAMETER Name
        Profile name defined as a top-level key in PersonalConfig.psd1 or WorkConfig.psd1.
    .PARAMETER Scopes
        Optional delegated scopes for Connect-MgGraph. Falls back to the profile's
        MgScopes field; if neither is supplied, Connect-MgGraph uses its default scopes.
    .PARAMETER ClientId
        Optional client (application) ID for app-only auth. Falls back to MgClientId.
    .PARAMETER NoWelcome
        Suppresses the Connect-MgGraph welcome banner.
    .PARAMETER Force
        Forces disconnect/reconnect even when the live context already matches.
    .EXAMPLE
        Use-MgProfile qu
    .EXAMPLE
        mgp lab -Scopes 'User.Read.All','Group.Read.All'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string[]]$Scopes,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [switch]$NoWelcome,

        [Parameter()]
        [switch]$Force
    )

    . $script:AzureCliProfileHelpers

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

    # Resolve profile configuration.
    $allProfiles = Get-AllAzureProfileConfigs
    if (-not $allProfiles.ContainsKey($Name)) {
        throw "Profile '$Name' not found in PersonalConfig.psd1 or WorkConfig.psd1."
    }
    $profileConfig = $allProfiles[$Name]
    & $writeStepTiming "Resolved profile config"

    if (-not $profileConfig.TenantId) {
        throw "Profile '$Name' is missing a TenantId."
    }

    # Validate Connect-MgGraph availability.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available. Install-Module Microsoft.Graph.Authentication."
    }

    # Determine effective Connect-MgGraph parameters from explicit args + config.
    $effectiveScopes = $Scopes
    if (-not $effectiveScopes -and $profileConfig.ContainsKey('MgScopes')) {
        $effectiveScopes = $profileConfig.MgScopes
    }
    $effectiveClientId = $ClientId
    if (-not $effectiveClientId -and $profileConfig.ContainsKey('MgClientId')) {
        $effectiveClientId = $profileConfig.MgClientId
    }

    # Check current live Mg context to decide whether reconnect is needed.
    $currentMg = Get-MgModuleCurrentContext
    $alreadyMatches = Resolve-MgProfileMatch -ProfileConfig $profileConfig -Context $currentMg
    & $writeStepTiming "Inspected current Mg context"

    $previousActive = Get-MgActiveProfileName

    if ($alreadyMatches -and -not $Force.IsPresent -and $previousActive -ieq $Name) {
        Write-Host "Already on Mg profile '$Name'. Use -Force to reconnect." -ForegroundColor Yellow
        if ($slowestStepName) {
            Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
        }
        Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)
        return Get-CurrentMgProfile
    }

    Write-Host "Switching to Mg profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan

    # Save the currently-live files into the previous profile's cache dir.
    if ($previousActive -and $previousActive -ne '(default)') {
        Save-MgProfileCache -ProfileName $previousActive
        & $writeStepTiming "Saved previous profile cache ($previousActive)"
    }

    # Disconnect any active session before swapping files so live state is clean.
    if ($currentMg.LoggedIn) {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
        & $writeStepTiming "Disconnected previous Mg session"
    }

    # Swap live files to the requested profile.
    Clear-MgGraphLiveCache
    $restored = Restore-MgProfileCache -ProfileName $Name
    Set-MgActiveProfileName -ProfileName $Name
    & $writeStepTiming "Restored profile cache (restored=$restored)"

    # Build Connect-MgGraph parameter set.
    $connectParams = @{
        TenantId    = $profileConfig.TenantId
        ErrorAction = 'Stop'
    }
    if ($effectiveScopes)   { $connectParams.Scopes   = $effectiveScopes }
    if ($effectiveClientId) { $connectParams.ClientId = $effectiveClientId }
    if ($NoWelcome.IsPresent) { $connectParams.NoWelcome = $true }

    try {
        Connect-MgGraph @connectParams | Out-Null
        & $writeStepTiming "Connected Microsoft.Graph"
    }
    catch {
        Write-Error "Connect-MgGraph failed for profile '$Name': $_"
        throw
    }

    # Connect Microsoft.Entra against the same tenant (optional module).
    $connectEntraCommand = Get-Command -Name Connect-Entra -ErrorAction SilentlyContinue
    if ($connectEntraCommand) {
        $entraParams = @{
            TenantId    = $profileConfig.TenantId
            ErrorAction = 'Stop'
        }
        if ($effectiveScopes)   { $entraParams.Scopes   = $effectiveScopes }
        if ($effectiveClientId) { $entraParams.ClientId = $effectiveClientId }
        if ($NoWelcome.IsPresent) { $entraParams.NoWelcome = $true }

        try {
            Connect-Entra @entraParams | Out-Null
            & $writeStepTiming "Connected Microsoft.Entra"
        }
        catch {
            Write-Warning "Connect-Entra failed for profile '$Name': $_"
        }
    }
    else {
        Write-Warning "Microsoft.Entra module not found. Install-Module Microsoft.Entra to enable Entra cmdlets."
    }

    # Capture refreshed live files for this profile.
    Save-MgProfileCache -ProfileName $Name
    & $writeStepTiming "Saved refreshed profile cache"

    if ($slowestStepName) {
        Write-Verbose ("Use-MgProfile slowest step: {0} ({1:N1} ms)" -f $slowestStepName, $slowestStepMs)
    }
    Write-Verbose ("Use-MgProfile total duration: {0:N1} ms" -f $overallTimer.Elapsed.TotalMilliseconds)

    Get-CurrentMgProfile
}


function New-MgProfile {
    <#
    .SYNOPSIS
        Creates a new Microsoft Graph / Entra profile or initializes an existing config entry.
    .DESCRIPTION
        In NewProfile mode, prompts for tenant/account details, runs Connect-MgGraph (and
        Connect-Entra if available), captures the resulting context, and optionally saves
        the entry to PersonalConfig.psd1 or WorkConfig.psd1. In FromConfig mode, takes an
        existing config entry and creates its on-disk cache directory by performing the
        initial sign-in via Use-MgProfile.
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
        Initializes the cache directory for a profile already defined in config.
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

    . $script:AzureCliProfileHelpers

    if ($FromConfig.IsPresent) {
        # Delegate to Use-MgProfile to perform initial sign-in and cache creation.
        $allProfiles = Get-AllAzureProfileConfigs
        if (-not $allProfiles.ContainsKey($Name)) {
            throw "Profile '$Name' not found in any config."
        }
        Use-MgProfile -Name $Name
        return Get-CurrentMgProfile
    }

    # NewProfile mode: connect, then optionally write to config.
    $connectMgCommand = Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue
    if (-not $connectMgCommand) {
        throw "Microsoft.Graph.Authentication module is not available."
    }

    # Disconnect any current session so the new profile starts clean.
    $currentMg = Get-MgModuleCurrentContext
    $previousActive = Get-MgActiveProfileName
    if ($previousActive -and $previousActive -ne '(default)') {
        Save-MgProfileCache -ProfileName $previousActive
    }
    if ($currentMg.LoggedIn) {
        try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
    }
    Clear-MgGraphLiveCache
    Set-MgActiveProfileName -ProfileName $Name

    $connectParams = @{ TenantId = $TenantId; ErrorAction = 'Stop' }
    if ($Scopes)   { $connectParams.Scopes   = $Scopes }
    if ($ClientId) { $connectParams.ClientId = $ClientId }

    Connect-MgGraph @connectParams | Out-Null

    $connectEntraCommand = Get-Command -Name Connect-Entra -ErrorAction SilentlyContinue
    if ($connectEntraCommand) {
        $entraParams = @{ TenantId = $TenantId; ErrorAction = 'Continue' }
        if ($Scopes)   { $entraParams.Scopes   = $Scopes }
        if ($ClientId) { $entraParams.ClientId = $ClientId }
        try { Connect-Entra @entraParams | Out-Null } catch { Write-Warning "Connect-Entra failed: $_" }
    }

    $newContext = Get-MgModuleCurrentContext
    $effectiveAccount = if ($Account) { $Account } else { $newContext.Account }

    Save-MgProfileCache -ProfileName $Name

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

function Remove-MgProfile {
    <#
    .SYNOPSIS
        Removes a Microsoft Graph / Entra profile cache and optionally its config entry.
    .DESCRIPTION
        Deletes the on-disk cache directory under ~/.mg/profiles/<name>/ and, unless
        -KeepConfig is specified, removes the matching in-memory entries from
        $Personal and $Work. The config psd1 files are NOT edited (matching the
        behavior of Remove-AzProfile). If the profile is currently active, the live
        Mg/Entra sessions are disconnected first.
    .PARAMETER Name
        Profile name to remove.
    .PARAMETER KeepConfig
        Leaves the in-memory config entries intact.
    .PARAMETER KeepCache
        Leaves the on-disk ~/.mg/profiles/<name>/ directory intact.
    .EXAMPLE
        Remove-MgProfile lab
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig,

        [Parameter()]
        [switch]$KeepCache
    )

    . $script:AzureCliProfileHelpers

    $activeName = Get-MgActiveProfileName

    # If the target is the active profile, disconnect live sessions first.
    if ($Name -ieq $activeName) {
        if (-not $PSCmdlet.ShouldProcess("active Mg/Entra session for '$Name'", 'Disconnect')) { return }

        $disconnectMgCommand = Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue
        if ($disconnectMgCommand) {
            try { Disconnect-MgGraph -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-MgGraph failed: $_" }
        }

        $disconnectEntraCommand = Get-Command -Name Disconnect-Entra -ErrorAction SilentlyContinue
        if ($disconnectEntraCommand) {
            try { Disconnect-Entra -ErrorAction Stop | Out-Null } catch { Write-Verbose "Disconnect-Entra failed: $_" }
        }

        Clear-MgGraphLiveCache
        Set-MgActiveProfileName -ProfileName '(default)'
    }

    # Remove on-disk cache directory unless told otherwise.
    if (-not $KeepCache.IsPresent) {
        $cacheDir = Get-MgGraphProfileDir -ProfileName $Name
        if (Test-Path -LiteralPath $cacheDir) {
            if ($PSCmdlet.ShouldProcess($cacheDir, 'Remove profile cache directory')) {
                Remove-Item -LiteralPath $cacheDir -Recurse -Force
                Write-Host "Removed cache: $cacheDir" -ForegroundColor Green
            }
        }
    }

    # Remove from in-memory configs unless told otherwise.
    if (-not $KeepConfig.IsPresent) {
        $removed = $false
        foreach ($varName in @('Personal','Work')) {
            $configVar = Get-Variable -Name $varName -Scope Global -ErrorAction SilentlyContinue
            if ($configVar -and $configVar.Value -is [hashtable] -and $configVar.Value.ContainsKey($Name)) {
                if ($PSCmdlet.ShouldProcess("`$$varName[$Name]", 'Remove in-memory profile entry')) {
                    $configVar.Value.Remove($Name)
                    Write-Host "Removed in-memory entry: `$$varName[$Name]" -ForegroundColor Green
                    $removed = $true
                }
            }
        }
        if (-not $removed) {
            Write-Host "Profile '$Name' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completer for Mg profile names (shared across commands).
$mgProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    . $script:AzureCliProfileHelpers

    $results = @()

    $allProfiles = Get-AllAzureProfileConfigs
    if ($allProfiles.Count -gt 0) {
        $results += $allProfiles.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $description = $allProfiles[$_].Description
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
        }
    }

    # Also include disk-only profiles for completion.
    $profilesRoot = Get-MgGraphProfilesRoot
    if (Test-Path -LiteralPath $profilesRoot) {
        Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$wordToComplete*" -and -not $allProfiles.ContainsKey($_.Name) } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', 'Disk-only Mg profile cache')
            }
    }

    $results
}

Register-ArgumentCompleter -CommandName Use-MgProfile, mgp -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName Remove-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter
Register-ArgumentCompleter -CommandName New-MgProfile -ParameterName Name -ScriptBlock $mgProfileCompleter

# Helper functions for Azure CLI profile management.
$script:AzureCliProfileHelpers = {
    function Get-AzureProfilesFromConfig {
        <#
        .SYNOPSIS
            Extracts Azure profile entries from a loaded config hashtable.
        .DESCRIPTION
            Returns profile records from top-level config keys. For backward compatibility,
            this also supports legacy configs that still nest profiles under AzureProfiles.
        .PARAMETER Config
            The loaded config hashtable from PersonalConfig.psd1 or WorkConfig.psd1.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter()]
            [hashtable]$Config
        )

        $profiles = @{}
        if (-not $Config) {
            return $profiles
        }

        $profileTable = if ($Config.ContainsKey('AzureProfiles') -and $Config.AzureProfiles -is [hashtable]) {
            $Config.AzureProfiles
        }
        else {
            $Config
        }

        foreach ($entry in $profileTable.GetEnumerator()) {
            $profileName = [string]$entry.Key
            $profileValue = $entry.Value

            if (
                $profileName -ne 'AzureProfiles' -and
                $profileValue -is [hashtable] -and
                (
                    $profileValue.ContainsKey('TenantId') -or
                    $profileValue.ContainsKey('Account') -or
                    $profileValue.ContainsKey('PrimarySub') -or
                    $profileValue.ContainsKey('SubscriptionId') -or
                    $profileValue.ContainsKey('Description')
                )
            ) {
                $profiles[$profileName] = $profileValue
            }
        }

        return $profiles
    }

    function Get-AllAzureProfileConfigs {
        <#
        .SYNOPSIS
            Returns a merged hashtable of Azure profiles from Personal and Work configs.
        .DESCRIPTION
            Combines top-level profile entries from $Personal and $Work configurations.
            Personal profiles take precedence if there's a name conflict.
        #>
        [CmdletBinding()]
        [OutputType([hashtable])]
        param()

        $merged = @{}
        $workProfiles = Get-AzureProfilesFromConfig -Config $Work
        $personalProfiles = Get-AzureProfilesFromConfig -Config $Personal

        # Add Work profiles first (lower precedence)
        if ($workProfiles.Count -gt 0) {
            foreach ($key in $workProfiles.Keys) {
                $merged[$key] = $workProfiles[$key]
            }
        }

        # Add Personal profiles (higher precedence, overwrites Work if conflict)
        if ($personalProfiles.Count -gt 0) {
            foreach ($key in $personalProfiles.Keys) {
                $merged[$key] = $personalProfiles[$key]
            }
        }

        return $merged
    }

    function Get-AzModuleCurrentContext {
        <#
        .SYNOPSIS
            Gets the current Az PowerShell module context, if available.
        .DESCRIPTION
            Returns details about the current Az module context and login state.
            If Az module cmdlets are not available, HasAzModule is false.
        #>
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
        if (-not $getAzContextCommand) {
            return [PSCustomObject][ordered]@{
                HasAzModule     = $false
                LoggedIn        = $false
                ContextName     = $null
                Account         = $null
                TenantId        = $null
                Subscription    = $null
                SubscriptionId  = $null
            }
        }

        $currentContext = $null
        try {
            $currentContext = Get-AzContext -ErrorAction Stop
        }
        catch {
            # No active Az context
        }

        return [PSCustomObject][ordered]@{
            HasAzModule     = $true
            LoggedIn        = ($null -ne $currentContext)
            ContextName     = $currentContext.Name
            Account         = $currentContext.Account.Id
            TenantId        = $currentContext.Tenant.Id
            Subscription    = $currentContext.Subscription.Name
            SubscriptionId  = $currentContext.Subscription.Id
        }
    }

    function Sync-AzModuleContext {
        <#
        .SYNOPSIS
            Aligns Az PowerShell module context with the selected profile.
        .DESCRIPTION
            Selects an existing Az context when one matches the provided tenant,
            subscription, or account. If no match exists, attempts Connect-AzAccount
            to register/select a context for the same identity scope.
        .PARAMETER ProfileName
            Friendly profile name being activated.
        .PARAMETER TenantId
            Target tenant ID.
        .PARAMETER SubscriptionId
            Target subscription ID.
        .PARAMETER AccountId
            Optional account UPN/email to constrain context matching.
        #>
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [string]$ProfileName,

            [Parameter(Mandatory)]
            [string]$TenantId,

            [Parameter(Mandatory)]
            [string]$SubscriptionId,

            [Parameter()]
            [string]$AccountId
        )

        $syncOverallTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $syncStepTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $syncSlowestStepName = $null
        $syncSlowestStepMs = 0.0
        $writeSyncStepTiming = {
            param([string]$Step)
            $elapsedMs = $syncStepTimer.Elapsed.TotalMilliseconds
            if ($elapsedMs -gt $syncSlowestStepMs) {
                $syncSlowestStepMs = $elapsedMs
                $syncSlowestStepName = $Step
            }
            Write-Verbose ("Sync-AzModuleContext: {0,-35} {1,8:N1} ms (total {2,8:N1} ms)" -f $Step, $elapsedMs, $syncOverallTimer.Elapsed.TotalMilliseconds)
            $syncStepTimer.Restart()
        }

        $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
        $selectAzContextCommand = Get-Command -Name Select-AzContext -ErrorAction SilentlyContinue
        $connectAzAccountCommand = Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue
        & $writeSyncStepTiming "Discovered Az cmdlets"

        if (-not $getAzContextCommand -or -not $selectAzContextCommand -or -not $connectAzAccountCommand) {
            Write-Warning "Az PowerShell module is not available. Install/import Az.Accounts to enable module context switching."
            if ($syncSlowestStepName) {
                Write-Verbose ("Sync-AzModuleContext slowest step: {0} ({1:N1} ms)" -f $syncSlowestStepName, $syncSlowestStepMs)
            }
            Write-Verbose ("Sync-AzModuleContext total duration: {0:N1} ms" -f $syncOverallTimer.Elapsed.TotalMilliseconds)
            return [PSCustomObject][ordered]@{
                HasAzModule      = $false
                Switched         = $false
                ContextName      = $null
                Account          = $null
                TenantId         = $null
                Subscription     = $null
                SubscriptionId   = $null
            }
        }

        $allContexts = @()
        try {
            $allContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue)
        }
        catch {
            $allContexts = @()
        }
        & $writeSyncStepTiming "Loaded available Az contexts"

        $matchingContext = $null
        if ($allContexts.Count -gt 0) {
            $subscriptionMatches = @($allContexts | Where-Object {
                $_.Subscription -and $_.Subscription.Id -eq $SubscriptionId
            })

            if ($AccountId) {
                $subscriptionMatches = @($subscriptionMatches | Where-Object {
                    $_.Account -and $_.Account.Id -eq $AccountId
                })
            }

            if ($subscriptionMatches.Count -gt 0) {
                $matchingContext = $subscriptionMatches | Where-Object {
                    $_.Name -ieq $ProfileName
                } | Select-Object -First 1

                if (-not $matchingContext) {
                    $matchingContext = $subscriptionMatches | Select-Object -First 1
                }
            }

            if (-not $matchingContext) {
                $tenantMatches = @($allContexts | Where-Object {
                    $_.Tenant -and $_.Tenant.Id -eq $TenantId -and
                    (
                        -not $AccountId -or
                        ($_.Account -and $_.Account.Id -eq $AccountId)
                    )
                })

                if ($tenantMatches.Count -gt 0) {
                    $matchingContext = $tenantMatches | Where-Object {
                        $_.Name -ieq $ProfileName
                    } | Select-Object -First 1

                    if (-not $matchingContext) {
                        $matchingContext = $tenantMatches | Select-Object -First 1
                    }
                }
            }
        }
        & $writeSyncStepTiming "Matched context by subscription/tenant"

        if ($matchingContext) {
            Select-AzContext -Name $matchingContext.Name -ErrorAction Stop | Out-Null
            & $writeSyncStepTiming "Selected existing Az context"
        }
        else {
            Write-Host "Connecting Az PowerShell context for profile '$ProfileName'..." -ForegroundColor Yellow

            $connectParams = @{
                Tenant          = $TenantId
                Subscription    = $SubscriptionId
                ErrorAction     = 'Stop'
            }

            if ($AccountId) {
                $connectParams.AccountId = $AccountId
            }

            Connect-AzAccount @connectParams | Out-Null
            & $writeSyncStepTiming "Connected new Az context"
        }

        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        & $writeSyncStepTiming "Read current Az context"
        if ($syncSlowestStepName) {
            Write-Verbose ("Sync-AzModuleContext slowest step: {0} ({1:N1} ms)" -f $syncSlowestStepName, $syncSlowestStepMs)
        }
        Write-Verbose ("Sync-AzModuleContext total duration: {0:N1} ms" -f $syncOverallTimer.Elapsed.TotalMilliseconds)

        return [PSCustomObject][ordered]@{
            HasAzModule      = $true
            Switched         = ($null -ne $currentContext)
            ContextName      = $currentContext.Name
            Account          = $currentContext.Account.Id
            TenantId         = $currentContext.Tenant.Id
            Subscription     = $currentContext.Subscription.Name
            SubscriptionId   = $currentContext.Subscription.Id
        }
    }

    # ----- Microsoft Graph / Entra helpers (file-swap isolation under ~/.mg/profiles/) -----

    $script:MgGraphProfileFiles = @('mg.authrecord.json','mg.context.json','mg.graphoptions.json')

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

    function Get-MgModuleCurrentContext {
        # Returns the live Microsoft.Graph context (or a stub if the module is missing).
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        $cmd = Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue
        if (-not $cmd) {
            return [PSCustomObject][ordered]@{
                HasMgModule  = $false
                LoggedIn     = $false
                TenantId     = $null
                Account      = $null
                ClientId     = $null
                Scopes       = $null
                AuthType     = $null
                ContextScope = $null
            }
        }

        $ctx = $null
        try { $ctx = Get-MgContext -ErrorAction Stop } catch { Write-Verbose "Get-MgContext failed: $_" }

        [PSCustomObject][ordered]@{
            HasMgModule  = $true
            LoggedIn     = ($null -ne $ctx)
            TenantId     = $ctx.TenantId
            Account      = $ctx.Account
            ClientId     = $ctx.ClientId
            Scopes       = $ctx.Scopes
            AuthType     = $ctx.AuthType
            ContextScope = $ctx.ContextScope
        }
    }

    function Get-EntraModuleCurrentContext {
        # Returns the live Microsoft.Entra context (or a stub if the module is missing).
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        $cmd = Get-Command -Name Get-EntraContext -ErrorAction SilentlyContinue
        if (-not $cmd) {
            return [PSCustomObject][ordered]@{
                HasEntraModule = $false
                LoggedIn       = $false
                TenantId       = $null
                Account        = $null
                ClientId       = $null
                Scopes         = $null
            }
        }

        $ctx = $null
        try { $ctx = Get-EntraContext -ErrorAction Stop } catch { Write-Verbose "Get-EntraContext failed: $_" }

        [PSCustomObject][ordered]@{
            HasEntraModule = $true
            LoggedIn       = ($null -ne $ctx)
            TenantId       = $ctx.TenantId
            Account        = $ctx.Account
            ClientId       = $ctx.ClientId
            Scopes         = $ctx.Scopes
        }
    }

    function Resolve-MgProfileMatch {
        # Returns $true if the live context matches the profile's tenant + account (or tenant + clientId for AppOnly).
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)][hashtable]$ProfileConfig,
            [Parameter(Mandatory)][PSCustomObject]$Context
        )

        if (-not $Context.LoggedIn) { return $false }
        if (-not $ProfileConfig.TenantId) { return $false }
        if ($Context.TenantId -ne $ProfileConfig.TenantId) { return $false }

        if ($ProfileConfig.ContainsKey('MgClientId') -and $ProfileConfig.MgClientId) {
            return ($Context.ClientId -eq $ProfileConfig.MgClientId)
        }

        if ($ProfileConfig.ContainsKey('Account') -and $ProfileConfig.Account -and $Context.Account) {
            return ($Context.Account -ieq $ProfileConfig.Account)
        }

        return $true
    }
}

#endregion
