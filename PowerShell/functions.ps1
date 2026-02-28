#region UTILITY FUNCTIONS

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

    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [switch]$All,
        [string[]]$Name,
        [switch]$SkipRemoveOldVersions
    )

    # Validate mutually exclusive scope parameters.
    if ($All -and $Name) {
        throw 'Specify either -All or -Name, but not both.'
    }

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
    # Resolve module scope from parameters.
    $targetPatterns = @()
    if ($Name) {
        $targetPatterns = $Name
    }
    else {
        $targetPatterns = '*'
        $All = $true
    }

    # Discover installed modules for the selected scope.
    $modules = foreach ($pattern in ($targetPatterns | Select-Object -Unique)) {
        try {
            Get-InstalledModule -Name $pattern -ErrorAction Stop
        }
        catch {
            Write-Warning "No installed module matched '$pattern'."
        }
    }

    $modules = $modules | Sort-Object -Property Name -Unique

    if (-not $modules) {
        Write-Host 'No modules found from Get-InstalledModule.' -ForegroundColor Yellow
        return
    }

    $updatedModules = [System.Collections.Generic.List[string]]::new()
    $totalModules = @($modules).Count
    $moduleIndex = 0
    Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Module update phase starting' -PercentComplete 0

    foreach ($mod in $modules) {
        $moduleIndex++
        $percentComplete = [int](($moduleIndex / $totalModules) * 100)
        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status "Update phase: checking $moduleIndex of $totalModules modules" -PercentComplete $percentComplete

        try {
            $startingVersion = [version]$mod.Version
            Update-Module -Name $mod.Name -ErrorAction Stop

            $latestVersion = Get-InstalledModule -Name $mod.Name -AllVersions |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1 -ExpandProperty Version

            if ([version]$latestVersion -gt $startingVersion) {
                $updatedModules.Add("$($mod.Name): $startingVersion -> $latestVersion")
            }
        }
        catch {
            Write-Warning "⚠ Failed to update '$($mod.Name)': $_"
        }
    }

    Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Update phase completed' -PercentComplete 100

    if (-not $SkipRemoveOldVersions -and (Get-Command Remove-OldModuleVersions -ErrorAction SilentlyContinue)) {
        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Cleanup phase: removing old module versions' -PercentComplete 100
        Write-Host 'Removing older module versions...' -ForegroundColor Cyan
        try {
            if ($All) {
                Remove-OldModuleVersions -All -Confirm:$false
            }
            else {
                Remove-OldModuleVersions -Name $targetPatterns -Confirm:$false
            }
            Write-Host 'Old module version cleanup complete.' -ForegroundColor Green
        }
        catch {
            Write-Warning "⚠ Failed to remove old module versions: $_"
        }
    }

    Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Completed

    $updatedModules
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

        [switch] $All,
        [switch] $IncludeGraph,
        [switch] $IncludeAz,

        # If set, also remove the latest (i.e., remove ALL versions).
        [switch] $RemoveAll
    )

    begin {
        # Build the target name list
        $targets = @()
        if ($All) { $targets += '*' }
        if ($IncludeGraph) { $targets += 'Microsoft.Graph*' }
        if ($IncludeAz) { $targets += 'Az*' }
        if ($Name) { $targets += $Name }

        if (-not $targets) {
            throw 'Specify at least one target via -All, -Name, -IncludeGraph, or -IncludeAz.'
        }

        Write-Verbose ('Targets: {0}' -f (($targets | Select-Object -Unique) -join ', '))
    }

    process {
        # Discover all installed module entries (all versions) for the targets
        $installed = foreach ($pattern in ($targets | Select-Object -Unique)) {
            try {
                Get-InstalledModule -Name $pattern -AllVersions -ErrorAction Stop
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

        $groupCount = @($byName).Count
        $groupIndex = 0

        foreach ($group in $byName) {
            $groupIndex++
            $cleanupPercent = [int](($groupIndex / $groupCount) * 100)
            Write-Progress -Id 2 -ParentId 1 -Activity 'PowerShell module maintenance cleanup' -Status "Cleanup phase: checking $groupIndex of $groupCount modules" -PercentComplete $cleanupPercent

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

        Write-Progress -Id 2 -ParentId 1 -Activity 'PowerShell module maintenance cleanup' -Completed
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

#endregion

#region AZURE CLI PROFILE MANAGEMENT
# Functions for managing multiple Azure CLI contexts across accounts/tenants.
# Uses separate AZURE_CONFIG_DIR per profile to isolate token caches and
# prevent context bleeding between tenants.
# Profiles can be defined in either $Personal.AzureProfiles or $Work.AzureProfiles

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

    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    $selectAzContextCommand = Get-Command -Name Select-AzContext -ErrorAction SilentlyContinue
    $connectAzAccountCommand = Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue

    if (-not $getAzContextCommand -or -not $selectAzContextCommand -or -not $connectAzAccountCommand) {
        Write-Warning "Az PowerShell module is not available. Install/import Az.Accounts to enable module context switching."
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

    $matchingContext = $null
    if ($allContexts.Count -gt 0) {
        $matchingContext = $allContexts | Where-Object {
            $_.Subscription -and $_.Subscription.Id -eq $SubscriptionId
        } | Select-Object -First 1

        if (-not $matchingContext) {
            $matchingContext = $allContexts | Where-Object {
                $_.Tenant -and $_.Tenant.Id -eq $TenantId -and
                (
                    -not $AccountId -or
                    ($_.Account -and $_.Account.Id -eq $AccountId)
                )
            } | Select-Object -First 1
        }
    }

    if ($matchingContext) {
        Select-AzContext -Name $matchingContext.Name -ErrorAction Stop | Out-Null
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
    }

    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
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
        if ($Personal -and $Personal.AzureProfiles) {
            foreach ($name in $Personal.AzureProfiles.Keys) {
                $profileConfig = $Personal.AzureProfiles[$name]
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
                    $allProfiles[$name].SubscriptionId = $profileConfig.SubscriptionId
                    $allProfiles[$name].AzCliSubscriptionId = $profileConfig.SubscriptionId
                }
                else {
                    # Add Personal config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $profileConfig.SubscriptionId
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $profileConfig.SubscriptionId
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
        if ($Work -and $Work.AzureProfiles) {
            foreach ($name in $Work.AzureProfiles.Keys) {
                $profileConfig = $Work.AzureProfiles[$name]
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
                    $allProfiles[$name].SubscriptionId = $profileConfig.SubscriptionId
                    $allProfiles[$name].AzCliSubscriptionId = $profileConfig.SubscriptionId
                }
                else {
                    # Add Work config profile
                    $allProfiles[$name] = [PSCustomObject][ordered]@{
                        Name        = $name
                        Description = $profileConfig.Description
                        Account     = $profileConfig.Account
                        SubscriptionId = $profileConfig.SubscriptionId
                        AzConfigDir = if (Test-Path $configDir) { $configDir } else { $null }
                        LoggedIn    = $isLoggedIn
                        CurrentUser = $currentUser
                        TenantId    = $profileConfig.TenantId
                        ConfigSource = $null  # Will be set below
                        AzCliAccount = $profileConfig.Account
                        AzCliSubscriptionId = $profileConfig.SubscriptionId
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
                $matchingContext = $azModuleContexts | Where-Object {
                    $_.Subscription -and $_.Subscription.Id -eq $profileRecord.SubscriptionId
                } | Select-Object -First 1
            }

            if (-not $matchingContext -and $profileRecord.TenantId) {
                $matchingContext = $azModuleContexts | Where-Object {
                    $_.Tenant -and $_.Tenant.Id -eq $profileRecord.TenantId -and
                    (
                        -not $profileRecord.Account -or
                        ($_.Account -and $_.Account.Id -eq $profileRecord.Account)
                    )
                } | Select-Object -First 1
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
        The profile name as defined in WorkConfig.psd1 AzureProfiles section,
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

    # Handle default profile specially
    if ($Name -eq '(default)' -or $Name -eq 'default') {
        # Set to default Azure config directory
        $configDir = Join-Path $HOME ".azure"
        $env:AZURE_CONFIG_DIR = $configDir

        Write-Host "Switching to profile: " -NoNewline
        Write-Host "(default)" -ForegroundColor Cyan -NoNewline
        Write-Host " (Default Azure CLI profile)"

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
        }

        # Show current context
        $accountInfo = az account show -o json 2>$null | ConvertFrom-Json

        # Sync Az module context to match CLI profile context
        $azModuleContext = $null
        if ($accountInfo) {
            $azModuleContext = Sync-AzModuleContext -ProfileName '(default)' -TenantId $accountInfo.tenantId -SubscriptionId $accountInfo.id -AccountId $accountInfo.user.name
        }

        # Return context info
        return [PSCustomObject][ordered]@{
            Profile        = '(default)'
            User           = $accountInfo.user.name
            TenantId       = $accountInfo.tenantId
            Subscription   = $accountInfo.name
            SubscriptionId = $accountInfo.id
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
    if ($allConfiguredProfiles.Count -eq 0) {
        Write-Error "No Azure profiles configured. Add AzureProfiles section to PersonalConfig.psd1 or WorkConfig.psd1"
        return
    }

    # Get the profile configuration
    $profileConfig = $allConfiguredProfiles[$Name]
    if (-not $profileConfig) {
        $availableProfiles = $allConfiguredProfiles.Keys -join ', '
        Write-Error "Profile '$Name' not found. Available profiles: $availableProfiles"
        return
    }

    # Set the config directory for this profile
    $configDir = Join-Path $HOME ".azure\profiles\$Name"
    $env:AZURE_CONFIG_DIR = $configDir

    Write-Host "Switching to profile: " -NoNewline
    Write-Host $Name -ForegroundColor Cyan -NoNewline
    Write-Host " ($($profileConfig.Description))"

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
    }

    # Set subscription if configured
    if ($profileConfig.SubscriptionId) {
        az account set --subscription $profileConfig.SubscriptionId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not set subscription: $($profileConfig.SubscriptionId)"
        }
    }

    # Show current context
    $accountInfo = az account show -o json 2>$null | ConvertFrom-Json

    # Validate we're in the expected tenant
    if ($accountInfo.tenantId -ne $profileConfig.TenantId) {
        Write-Warning "Tenant mismatch! Expected: $($profileConfig.TenantId), Got: $($accountInfo.tenantId)"
    }

    # Sync Az module context to match CLI profile context
    $azModuleContext = Sync-AzModuleContext -ProfileName $Name -TenantId $accountInfo.tenantId -SubscriptionId $accountInfo.id -AccountId $accountInfo.user.name

    # Return context info
    [PSCustomObject][ordered]@{
        Profile        = $Name
        User           = $accountInfo.user.name
        TenantId       = $accountInfo.tenantId
        Subscription   = $accountInfo.name
        SubscriptionId = $accountInfo.id
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

# Create alias for quick access
Set-Alias -Name azp -Value Use-AzProfile -Scope Global

# Register argument completer for Use-AzProfile profile names (for both function and alias)
$azProfileCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

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
        $SubscriptionId = $profileConfig.SubscriptionId

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
        $matchingContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            ($profileConfig.SubscriptionId -and $_.Subscription -and $_.Subscription.Id -eq $profileConfig.SubscriptionId) -or
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

#endregion
