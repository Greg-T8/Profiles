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
        Write-Host "✓ '$repoName' is now trusted." -ForegroundColor Green
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

    .PARAMETER Iterations
        Number of iterations to run for averaging. Default is 3.

    .EXAMPLE
        Measure-ProfileLoad

    .EXAMPLE
        Measure-ProfileLoad -Iterations 5
    #>
    [CmdletBinding()]
    param(
        [int]$Iterations = 3
    )

    # Ensure PSProfiler module is available
    if (-not (Get-Command Measure-Script -ErrorAction SilentlyContinue)) {
        Write-Warning "PSProfiler module not found. Install with: Install-Module PSProfiler"
        Write-Warning "Falling back to basic timing only..."
    }

    Write-Host "`nMeasuring PowerShell profile load times..." -ForegroundColor Cyan
    Write-Host "Running $Iterations iterations...`n" -ForegroundColor Gray

    # Measure baseline (no profile)
    $baselineTimes = 1..$Iterations | ForEach-Object {
        Write-Host "  Baseline $_/$Iterations..." -NoNewline
        $ms = (Measure-Command { pwsh -NoProfile -Command "exit" }).TotalMilliseconds
        Write-Host " $([math]::Round($ms, 2))ms" -ForegroundColor Gray
        $ms
    }

    # Measure with profile
    $profileTimes = 1..$Iterations | ForEach-Object {
        Write-Host "  Profile $_/$Iterations..." -NoNewline
        $ms = (Measure-Command { pwsh -Command "exit" }).TotalMilliseconds
        Write-Host " $([math]::Round($ms, 2))ms" -ForegroundColor Gray
        $ms
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

        # Copy script to /tmp and run as root
        Write-Host "Copying init-wsl.sh to WSL distribution..." -ForegroundColor Cyan
        wsl -d $Name -- bash -c "cp '$wslInitPath' /tmp/init-wsl.sh && chmod +x /tmp/init-wsl.sh"

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
                wsl -d $Name --user root -- bash -c "echo '[user]' > /etc/wsl.conf && echo 'default=$defaultUser' >> /etc/wsl.conf"

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
    Write-Host "To set it as default, run: wsl --set-default $Name" -ForegroundColor Yellow
}
