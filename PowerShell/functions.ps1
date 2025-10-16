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
