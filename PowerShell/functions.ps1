# Reverts to the default dir function in cmd.exe
function dir {
    cmd /c dir $args
}


# Converts tab-delimited clipboard data to PowerShell objects (for Excel copy-paste).
function Get-ClipboardExcel {
    Get-Clipboard | ConvertFrom-Csv -Delimiter "`t"
}

# Opens the VS Code PowerShell profile in a new window.
function ep {
    code -n --profile 'PowerShell' $PROFILE.CurrentUserAllHosts
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

# Removes Snagit files older than one month from the OneDriveConsumer/Snagit folder.
function CleanUpSnagitFolder {
    $folderPath = "$env:USERPROFILE/Snagit Captures"
    $cutoffDate = (Get-Date).AddMonths(-1)
    Get-ChildItem -Path $folderPath -File | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force
}

# Removes all but the latest version of each installed PowerShell module for the current user.
function RemoveOldModules {
    [OutputType()]
    $psresources = Get-InstalledPSResource -Scope CurrentUser
    $groupedResources = $psresources | Group-Object -Property Name
    foreach ($group in $groupedResources) {
        $latestVersion = $group.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        $oldVersions = $group.Group | Where-Object { $_.Version -ne $latestVersion.Version }
        foreach ($oldVersion in $oldVersions) {
            Write-Host "Uninstalling $($oldVersion.Name) version $($oldVersion.Version)"
            try {
                Uninstall-PSResource -Name $oldVersion.Name -Version $oldVersion.Version -ProgressAction SilentlyContinue
            }
            catch {
                $err = $_.Exception.Message
                Write-Host "Failed to uninstall $($oldVersion.Name) version $($oldVersion.Version): $err" -ForegroundColor Red
                continue
            }
        }
    }
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

function Update-AllInstalledModules {
    <#
    .SYNOPSIS
        Updates all installed PowerShell modules using PowerShellGet v2.
    .DESCRIPTION
        Ensures PSGallery is trusted, then updates all modules installed via Install-Module.
    #>

    [CmdletBinding()]
    param()

    # Ensure PowerShellGet v2 is available
    if (-not (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue)) {
        Write-Error 'PowerShellGet v2 not detected. This script requires the PowerShellGet module (v2).'
        return
    }

    $repoName = 'PSGallery'
    $repo = Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue

    if (-not $repo) {
        Write-Error "Repository '$repoName' not found. Use Register-PSRepository to add it."
        return
    }

    if (-not $repo.Trusted) {
        Write-Host "Marking '$repoName' as a trusted repository..." -ForegroundColor Yellow
        Set-PSRepository -Name $repoName -InstallationPolicy Trusted -ErrorAction Stop
        # Write-Host "✓ `'$repoName`' is now trusted." -ForegroundColor Green
        Write-Host " `'$repoName`' is now trusted." -ForegroundColor Green
    }



    $modules = Get-InstalledModule

    foreach ($mod in $modules) {
        try {
            Write-Host "Updating module '$($mod.Name)'..." -ForegroundColor Cyan
            Update-Module -Name $mod.Name -ErrorAction Stop
            Write-Host "✓ Updated '$($mod.Name)'" -ForegroundColor Green
        }
        catch {
            Write-Warning "⚠ Failed to update '$($mod.Name)': $_"
        }
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
    Get-WinGetPackage |
        Where-Object IsUpdateAvailable |
        Select-Object Name, Id, InstalledVersion, IsUpdateAvailable,
            @{n='AvailableVersions'; e={ $_.AvailableVersions | Select-Object -First 1 }}
}

function Remove-OldModuleVersions {
    <#
    .SYNOPSIS
      Uninstalls older versions of modules, keeping the newest per module name.

    .DESCRIPTION
      Uses PowerShellGet's Get-InstalledModule/Uninstall-Module to remove all
      but the latest installed version of each target module. Targets can be:
        - Specific names/patterns via -Name (supports wildcards)
        - All Microsoft Graph modules via -IncludeGraph
        - All Az modules via -IncludeAz

      If modules are currently loaded, the function removes them from the session
      first so they can be uninstalled cleanly.

    .EXAMPLE
      Remove-OldModuleVersions -IncludeGraph -IncludeAz -WhatIf

    .EXAMPLE
      Remove-OldModuleVersions -Name 'Pester','PSReadLine'

    .EXAMPLE
      Remove-OldModuleVersions -Name 'Microsoft.Graph.*','Az.*' -Confirm:$false

    .NOTES
      - Run as Administrator if some modules were installed to Program Files.
      - Only modules installed via PowerShellGet are returned by Get-InstalledModule.
  #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]] $Name,

        [switch] $IncludeGraph,
        [switch] $IncludeAz,

        # If set, also remove the latest (i.e., remove ALL versions).
        [switch] $RemoveAll
    )

    begin {
        # Build the target name list
        $targets = @()
        if ($IncludeGraph) { $targets += 'Microsoft.Graph*' }
        if ($IncludeAz) { $targets += 'Az*' }
        if ($Name) { $targets += $Name }

        if (-not $targets) {
            throw 'Specify at least one target via -Name, -IncludeGraph, or -IncludeAz.'
        }

        Write-Verbose ('Targets: {0}' -f (($targets | Select-Object -Unique) -join ', '))
    }

    process {
        # Discover all installed module entries (all versions) for the targets
        $installed = foreach ($pattern in ($targets | Select-Object -Unique)) {
            try {
                Get-Module -Name $pattern -ListAvailable -ErrorAction Stop
            }
            catch {
                Write-Verbose "No installed modules matched pattern '$pattern'."
            }
        }

        if (-not $installed) {
            Write-Verbose 'No matching installed modules found.'
            return
        }

        # Group by module name to compare versions
        $byName = $installed | Group-Object Name

        foreach ($group in $byName) {
            $name = $group.Name
            $versions = $group.Group | Sort-Object Version -Descending

            # Determine which entries to remove
            $toRemove = if ($RemoveAll) {
                $versions
            }
            else {
                $latest = $versions | Select-Object -First 1
                $versions | Where-Object { $_.Version -ne $latest.Version }
            }

            if (-not $toRemove -or $toRemove.Count -eq 0) {
                Write-Verbose "Nothing to remove for $name (already only latest)."
                continue
            }

            # Ensure no version of this module is loaded in the current session
            $loaded = Get-Module -Name $name -All
            if ($loaded) {
                Write-Verbose "Removing loaded module(s) for $name from the session..."
                foreach ($lm in $loaded) {
                    try {
                        Remove-Module -ModuleInfo $lm -Force -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "Failed to Remove-Module $($lm.Name) $($lm.Version): $($_.Exception.Message)"
                    }
                }
            }

            # Uninstall targeted versions
            foreach ($m in $toRemove) {
                $desc = "$($m.Name) $($m.Version)"
                if ($PSCmdlet.ShouldProcess($desc, 'Uninstall-Module')) {
                    try {
                        Uninstall-Module -Name $m.Name -RequiredVersion $m.Version -Force -ErrorAction Stop
                        Write-Verbose "Uninstalled $desc"
                    }
                    catch {
                        Write-Warning "Failed to uninstall $desc`: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
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

# ============================================================================
# AZURE CLI PROFILE MANAGEMENT
# ============================================================================
# Functions for managing multiple Azure CLI contexts across accounts/tenants.
# Uses separate AZURE_CONFIG_DIR per profile to isolate token caches and
# prevent context bleeding between tenants.
# Profiles can be defined in either $Personal.AzureProfiles or $Work.AzureProfiles
# ============================================================================

function Get-AllAzureProfileConfigs {
    <#
    .SYNOPSIS
        Returns a merged hashtable of Azure profiles from Personal and Work configs.
    .DESCRIPTION
        Combines AzureProfiles from $Personal and $Work configurations.
        Personal profiles take precedence if there's a name conflict.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $merged = @{}

    # Add Work profiles first (lower precedence)
    if ($Work -and $Work.AzureProfiles) {
        foreach ($key in $Work.AzureProfiles.Keys) {
            $merged[$key] = $Work.AzureProfiles[$key]
        }
    }

    # Add Personal profiles (higher precedence, overwrites Work if conflict)
    if ($Personal -and $Personal.AzureProfiles) {
        foreach ($key in $Personal.AzureProfiles.Keys) {
            $merged[$key] = $Personal.AzureProfiles[$key]
        }
    }

    return $merged
}

function Get-AzProfiles {
    <#
    .SYNOPSIS
        Lists Azure CLI profiles from both WorkConfig and the profiles directory.
    .DESCRIPTION
        Scans ~/.azure/profiles directory for existing profile directories and
        combines with profiles defined in WorkConfig.psd1. Shows login status
        and configuration details for each profile.
    .PARAMETER ConfiguredOnly
        Shows only profiles defined in WorkConfig.psd1.
    .PARAMETER DiscoveredOnly
        Shows only profiles found in ~/.azure/profiles directory.
    .EXAMPLE
        Get-AzProfiles
        Lists all profiles from both sources.
    .EXAMPLE
        Get-AzProfiles -ConfiguredOnly
        Shows only profiles defined in WorkConfig.psd1.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$ConfiguredOnly,

        [Parameter()]
        [switch]$DiscoveredOnly
    )

    $profilesDir = Join-Path $HOME ".azure\profiles"
    $allProfiles = @{}

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

            $allProfiles[$name] = [PSCustomObject]@{
                Name        = $name
                Description = $null
                Account     = $null
                LoggedIn    = $isLoggedIn
                CurrentUser = $currentUser
                TenantId    = $tenantId
                Source      = 'Discovered'
                Configured  = $false
            }
        }
    }

    # Merge with configured profiles from Personal and Work configs
    $configuredProfiles = Get-AllAzureProfileConfigs
    if (-not $DiscoveredOnly.IsPresent -and $configuredProfiles.Count -gt 0) {
        foreach ($name in $configuredProfiles.Keys) {
            $profile = $configuredProfiles[$name]
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

            # Update or add profile
            if ($allProfiles.ContainsKey($name)) {
                # Enhance discovered profile with config info
                $allProfiles[$name].Description = $profile.Description
                $allProfiles[$name].Account = $profile.Account
                $allProfiles[$name].Source = 'Both'
                $allProfiles[$name].Configured = $true
            }
            else {
                # Add configured profile
                $allProfiles[$name] = [PSCustomObject]@{
                    Name        = $name
                    Description = $profile.Description
                    Account     = $profile.Account
                    LoggedIn    = $isLoggedIn
                    CurrentUser = $currentUser
                    TenantId    = $profile.TenantId
                    Source      = 'Configured'
                    Configured  = $true
                }
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

    # Get current config directory
    $currentConfigDir = $env:AZURE_CONFIG_DIR
    if (-not $currentConfigDir) {
        $currentConfigDir = Join-Path $HOME ".azure\default"
    }

    # Determine profile name from config dir
    $profileName = Split-Path -Leaf $currentConfigDir
    if ($profileName -eq ".azure") {
        $profileName = "(default)"
    }

    # Try to get current account info
    $accountInfo = $null
    try {
        $accountJson = az account show 2>$null
        if ($accountJson) {
            $accountInfo = $accountJson | ConvertFrom-Json
        }
    }
    catch {
        # Not logged in or az CLI not available
    }

    # Return current context
    [PSCustomObject]@{
        ProfileName    = $profileName
        ConfigDir      = $currentConfigDir
        LoggedIn       = ($null -ne $accountInfo)
        User           = $accountInfo.user.name
        TenantId       = $accountInfo.tenantId
        Subscription   = $accountInfo.name
        SubscriptionId = $accountInfo.id
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
        The profile name as defined in WorkConfig.psd1 AzureProfiles section.
    .PARAMETER Force
        Forces re-authentication even if already logged in.
    .PARAMETER SelectAccount
        Prompts for account selection during login (useful for MFA/CA).
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

    # Get all configured profiles from Personal and Work configs
    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    if ($allConfiguredProfiles.Count -eq 0) {
        Write-Error "No Azure profiles configured. Add AzureProfiles section to PersonalConfig.psd1 or WorkConfig.psd1"
        return
    }

    # Get the profile configuration
    $profile = $allConfiguredProfiles[$Name]
    if (-not $profile) {
        $availableProfiles = $allConfiguredProfiles.Keys -join ', '
        Write-Error "Profile '$Name' not found. Available profiles: $availableProfiles"
        return
    }

    # Set the config directory for this profile
    $configDir = Join-Path $HOME ".azure\profiles\$Name"
    $env:AZURE_CONFIG_DIR = $configDir

    Write-Host "Switching to profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan -NoNewline
    Write-Host " ($($profile.Description))"

    # Check if we need to login
    $needsLogin = $Force.IsPresent

    if (-not $needsLogin) {
        try {
            $null = az account show 2>$null
            if ($LASTEXITCODE -ne 0) {
                $needsLogin = $true
            }
        }
        catch {
            $needsLogin = $true
        }
    }

    # Perform login if needed
    if ($needsLogin) {
        Write-Host "Logging in to tenant: $($profile.TenantId)" -ForegroundColor Yellow

        $loginArgs = @('login', '--tenant', $profile.TenantId)

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
    }

    # Set subscription if configured
    if ($profile.SubscriptionId) {
        az account set --subscription $profile.SubscriptionId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not set subscription: $($profile.SubscriptionId)"
        }
    }

    # Show current context
    $accountInfo = az account show -o json 2>$null | ConvertFrom-Json

    # Validate we're in the expected tenant
    if ($accountInfo.tenantId -ne $profile.TenantId) {
        Write-Warning "Tenant mismatch! Expected: $($profile.TenantId), Got: $($accountInfo.tenantId)"
    }

    # Return context info
    [PSCustomObject]@{
        Profile        = $Name
        User           = $accountInfo.user.name
        TenantId       = $accountInfo.tenantId
        Subscription   = $accountInfo.name
        SubscriptionId = $accountInfo.id
    }
}

# Create alias for quick access
Set-Alias -Name azp -Value Use-AzProfile -Scope Global

# Register argument completer for Use-AzProfile profile names (for both function and alias)
$azProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $allProfiles = Get-AllAzureProfileConfigs
    if ($allProfiles.Count -gt 0) {
        $allProfiles.Keys | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            $description = $allProfiles[$_].Description
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $description)
        }
    }
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
    .EXAMPLE
        New-AzProfile -Name 'contoso' -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Description 'Contoso Corp'
        Creates a new profile and logs in.
    .EXAMPLE
        New-AzProfile -Name 'newclient' -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -Description 'New Client' -Save
        Creates a profile and saves it to WorkConfig.psd1.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [switch]$Save
    )

    # Check if profile already exists in either config
    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    if ($allConfiguredProfiles.ContainsKey($Name)) {
        Write-Error "Profile '$Name' already exists. Use a different name or remove the existing profile first."
        return
    }

    # Set the config directory for this profile
    $configDir = Join-Path $HOME ".azure\profiles\$Name"
    $env:AZURE_CONFIG_DIR = $configDir

    Write-Host "Creating new profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan
    Write-Host "Logging in to tenant: $TenantId" -ForegroundColor Yellow

    # Perform login with account selection
    az login --tenant $TenantId --prompt select_account

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Login failed. Profile not created."
        return
    }

    # Get account info after login
    $accountInfo = az account show -o json 2>$null | ConvertFrom-Json

    if (-not $accountInfo) {
        Write-Error "Could not retrieve account information. Profile not created."
        return
    }

    # If subscription ID provided, set it
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not set subscription: $SubscriptionId. Using default."
            $SubscriptionId = $accountInfo.id
        }
        else {
            # Refresh account info after setting subscription
            $accountInfo = az account show -o json 2>$null | ConvertFrom-Json
        }
    }
    else {
        $SubscriptionId = $accountInfo.id
    }

    # Create the profile entry
    $newProfile = @{
        Account        = $accountInfo.user.name
        TenantId       = $accountInfo.tenantId
        SubscriptionId = $SubscriptionId
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
            SubscriptionId = '$SubscriptionId'
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

            # Find the AzureProfiles section and add the new profile
            $profileEntry = @"

        '$Name' = @{
            Account        = '$($newProfile.Account)'
            TenantId       = '$($newProfile.TenantId)'
            SubscriptionId = '$SubscriptionId'
            Description    = '$Description'
        }
"@
            # Insert before the closing of AzureProfiles (look for the template comment or closing brace)
            $insertPattern = "        # Template for adding new"
            if ($content -match [regex]::Escape($insertPattern)) {
                $content = $content -replace [regex]::Escape($insertPattern), "$profileEntry`n`n        # Template for adding new"
                Set-Content -Path $configPath -Value $content -NoNewline
                Write-Host "Profile saved to config file" -ForegroundColor Green
            }
            else {
                Write-Warning "Could not auto-insert. Please add manually."
            }
        }
    }

    # Return the profile info
    [PSCustomObject]@{
        Profile        = $Name
        Account        = $newProfile.Account
        TenantId       = $newProfile.TenantId
        Subscription   = $accountInfo.name
        SubscriptionId = $SubscriptionId
        Description    = $Description
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

    # Remove from in-memory config unless KeepConfig is specified
    if (-not $KeepConfig.IsPresent) {
        $removed = $false

        if ($Personal -and $Personal.AzureProfiles -and $Personal.AzureProfiles.ContainsKey($Name)) {
            $Personal.AzureProfiles.Remove($Name)
            Write-Host "Removed profile from Personal in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from PersonalConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if ($Work -and $Work.AzureProfiles -and $Work.AzureProfiles.ContainsKey($Name)) {
            $Work.AzureProfiles.Remove($Name)
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
