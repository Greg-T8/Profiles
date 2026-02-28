#region HEADER
# Script-level help and metadata.
<#
.SYNOPSIS
Updates installed PowerShell modules and writes run logs.

.DESCRIPTION
Runs targeted or broad module maintenance for CurrentUser-installed modules.
The script records update and cleanup output to indexed log files under %APPDATA%.

.CONTEXT
User login maintenance automation (Windows Task Scheduler)

.AUTHOR
Greg Tate

.PARAMETER RetentionDays
Overrides the default log retention period (in days). Use a value from 0 to 3650.

.PARAMETER AllModules
Updates all modules installed in CurrentUser scope, excluding configured ignore list entries.

.PARAMETER Common
Uses the configured common module list (default parameter set).

.PARAMETER ModuleName
Updates only the specified module names when they are installed in CurrentUser scope.

.PARAMETER RecentHistoryLines
Number of recent PSReadLine history lines used by refresh logic (reserved for compatibility).

.PARAMETER ShowTiming
Displays per-module timing diagnostics in console output.

.EXAMPLE
.\Invoke-PowerShellModuleUpdates.ps1 -Common

.EXAMPLE
.\Invoke-PowerShellModuleUpdates.ps1 -AllModules

.EXAMPLE
.\Invoke-PowerShellModuleUpdates.ps1 -ModuleName 'Az.Accounts','Microsoft.Graph.Authentication' -ShowTiming

.NOTES
Program: Invoke-PowerShellModuleUpdates.ps1
#>

# -------------------------------------------------------------------------
# Program: Invoke-PowerShellModuleUpdates.ps1
# Description: Updates PowerShell modules and WinGet packages with per-tool logs for login automation.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------
#endregion

#region PARAMETERS
# Script parameter definitions.
[CmdletBinding(DefaultParameterSetName = 'Common')]
param(
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = -1,

    [Parameter(ParameterSetName = 'AllModules')]
    [switch]$AllModules,

    [Parameter(ParameterSetName = 'Common')]
    [switch]$Common,

    [Parameter(ParameterSetName = 'ModuleName', Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ModuleName,

    [ValidateRange(100, 50000)]
    [int]$RecentHistoryLines = 5000,

    [switch]$ShowTiming
)
#endregion

#region CONFIGURATION
# Script configuration and startup state.
# Configure module scope for PowerShell update and cleanup phases.
$ModuleUpdateConfig = @{
    Scope           = 'Selected'
    SelectedModules = @(
        'Az.Accounts'
        'Az.Compute'
        'Az.Monitor'
        'Az.Network'
        'Az.PolicyInsights'
        'Az.RecoveryServices'
        'Az.Resources'
        'Az.Storage'
        'Microsoft.Graph.Authentication'
        'PSReadLine'
    )
    IgnoreModules   = @(
        'PSReadLine'
    )
}

# Configure log retention for indexed update log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}

# Cache this script path for helper functions that need to persist config changes.
$Script:ModuleUpdateScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

# Capture switch states here because $PSBoundParameters is not visible inside & $Main.
$useAllModules = $PSBoundParameters.ContainsKey('AllModules')
$useModuleNameList = $PSBoundParameters.ContainsKey('ModuleName')
#endregion

#region MAIN
# High-level orchestration flow.
$Main = {
    . $Helpers
    $powerShellChanged = $false
    $refreshLogCreated = $false

    $logContext = New-UpdateLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $RetentionDays

    $moduleScopeMode = 'Common'
    if ($useAllModules) { $moduleScopeMode = 'AllUserScoped' }
    if ($useModuleNameList) { $moduleScopeMode = 'ModuleNameList' }

    $moduleUpdateParameters = New-ModuleUpdateParameters -ModuleUpdateConfig $ModuleUpdateConfig -ScopeMode $moduleScopeMode -ModuleName $ModuleName -RecentHistoryLines $RecentHistoryLines -ShowTiming:$ShowTiming
    $powerShellChanged = Invoke-PowerShellModuleUpdates -PowerShellLogPath $logContext.PowerShellLogPath -ModuleUpdateParameters $moduleUpdateParameters

    Open-UpdateLogs -PowerShellLogPath $logContext.PowerShellLogPath -RefreshedModulesLogPath $logContext.RefreshedModulesLogPath -PowerShellChanged:$powerShellChanged -RefreshLogCreated:$refreshLogCreated
}
#endregion

#region HELPERS
# Supporting helper functions.
$Helpers = {
    function New-ModuleUpdateParameters {
        param(
            [Parameter(Mandatory)]
            [hashtable]$ModuleUpdateConfig,

            [ValidateSet('Common', 'AllUserScoped', 'ModuleNameList')]
            [string]$ScopeMode = 'Common',

            [string[]]$ModuleName = @(),

            [int]$RecentHistoryLines = 5000,

            [switch]$ShowTiming
        )

        # Build a lookup of modules installed in CurrentUser scope only.
        $currentUserModules = Get-CurrentUserInstalledModuleNames
        $ignoredModules = @($ModuleUpdateConfig.IgnoreModules |
            Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
            Select-Object -Unique)

        # Return all user-scoped modules.
        if ($ScopeMode -eq 'AllUserScoped') {
            $allUserScopedModules = @($currentUserModules | Where-Object { $ignoredModules -notcontains $_ })

            if (-not $allUserScopedModules) {
                throw '-AllModules found no modules in CurrentUser scope.'
            }

            return @{ Name = @($allUserScopedModules); ShowTiming = [bool]$ShowTiming; ScopeMode = 'AllUserScoped' }
        }

        # Honor explicit module list for targeted update and cleanup.
        if ($ScopeMode -eq 'ModuleNameList') {
            $requestedModules = @($ModuleName |
                Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
                Select-Object -Unique)

            if (-not $requestedModules) {
                throw '-ModuleName is required when ScopeMode is ModuleNameList.'
            }

            $matchedModules = @($requestedModules | Where-Object { $currentUserModules -contains $_ })
            if (-not $matchedModules) {
                throw '-ModuleName values were not found in CurrentUser scope.'
            }

            return @{ Name = $matchedModules; ShowTiming = [bool]$ShowTiming; ScopeMode = 'ModuleNameList' }
        }

        # Use common selected module list from config.
        if ($ScopeMode -eq 'Common') {
            $selectedModulesFromConfig = @($ModuleUpdateConfig.SelectedModules |
                Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } |
                Where-Object { $currentUserModules -contains $_ } |
                Where-Object { $ignoredModules -notcontains $_ } |
                Select-Object -Unique)

            if (-not $selectedModulesFromConfig) {
                throw '-Common found no configured modules in CurrentUser scope.'
            }

            return @{ Name = $selectedModulesFromConfig; ShowTiming = [bool]$ShowTiming; ScopeMode = 'Common' }
        }

        throw "Invalid scope mode '$ScopeMode'. Use 'Common', 'AllUserScoped', or 'ModuleNameList'."
    }

    function Get-CurrentUserInstalledModuleNames {
        # Return unique module names installed in CurrentUser scope.
        $userModuleRoots = @(
            (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules'),
            (Join-Path -Path $HOME -ChildPath 'Documents\WindowsPowerShell\Modules')
        )

        $moduleNames = @()

        $userPathModules = Get-Module -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            $moduleBase = "$($_.ModuleBase)"
            $userModuleRoots | Where-Object { $moduleBase -like "$($_)*" }
        }
        if ($userPathModules) {
            $moduleNames += $userPathModules | Select-Object -ExpandProperty Name -Unique
        }

        if (Get-Command Get-InstalledPSResource -ErrorAction SilentlyContinue) {
            $currentUserResources = Get-InstalledPSResource -Scope CurrentUser -ErrorAction SilentlyContinue
            if ($currentUserResources) {
                $moduleNames += $currentUserResources |
                    Where-Object { "$($_.Type)" -eq 'Module' } |
                    Select-Object -ExpandProperty Name -Unique
            }
        }

        return @($moduleNames | Sort-Object -Unique)
    }

    function Get-RecentUserScopeModules {
        param(
            [Parameter(Mandatory)]
            [int]$RecentHistoryLines,

            [AllowEmptyCollection()]
            [string[]]$CurrentUserModules = @()
        )

        if (-not $CurrentUserModules -or $CurrentUserModules.Count -eq 0) {
            return @()
        }

        # Resolve the PSReadLine history file path and read recent lines.
        $historyPath = (Get-PSReadLineOption).HistorySavePath
        if (-not (Test-Path -Path $historyPath)) {
            return @()
        }

        $recentLines = Get-Content -Path $historyPath -Tail $RecentHistoryLines -ErrorAction SilentlyContinue
        if (-not $recentLines) {
            return @()
        }

        # Extract first tokens that look like cmdlet names.
        $tokens = $recentLines |
            ForEach-Object {
                if ([string]::IsNullOrWhiteSpace($_)) { return }
                ($_ -split '\s+')[0].Trim()
            } |
            Where-Object { $_ -match '^[A-Za-z]+-[A-Za-z0-9]+' } |
            Select-Object -Unique

        if (-not $tokens) {
            return @()
        }

        # Map command names to module names and keep only CurrentUser-scope modules.
        $resolvedModules = Get-Command -Name $tokens -ErrorAction SilentlyContinue |
            Where-Object { $_.ModuleName } |
            Select-Object -ExpandProperty ModuleName -Unique

        if (-not $resolvedModules) {
            return @()
        }

        return @($resolvedModules | Where-Object { $CurrentUserModules -contains $_ } | Sort-Object -Unique)
    }

    function New-UpdateLogContext {
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        # Create and return update log paths under %APPDATA%.
        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        # Apply retention policy before determining the next same-day index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) { $RetentionDaysOverride } else { [int]$LogRetentionConfig.RetentionDays }
            if ($effectiveRetentionDays -gt 0) {
                Remove-OldUpdateLogs -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
            }
        }

        # Prefix log file names with the run date.
        $datePrefix = Get-Date -Format 'yyyy-MM-dd'

        # Derive next same-day index so each run gets a unique log pair.
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-PowerShellModuleUpdates.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-PowerShellModuleUpdates$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        # Return both log file paths in a single object.
        [PSCustomObject]@{
            LogDirectory       = $logDirectory
            PowerShellLogPath  = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-PowerShellModuleUpdates.log"
            RefreshedModulesLogPath = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-RefreshedSelectedModules.log"
        }
    }

    function Write-RefreshedModuleLog {
        param(
            [Parameter(Mandatory)]
            [string]$RefreshedModulesLogPath,

            [Parameter(Mandatory)]
            [int]$RecentHistoryLines,

            [Parameter(Mandatory)]
            [string[]]$RefreshedModules
        )

        # Write refresh metadata and final selected module list to a dedicated log file.
        "===== Selected module refresh started: $(Get-Date -Format s) =====" | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
        "Source: Recent command history ($RecentHistoryLines lines)" | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
        'Scope filter: CurrentUser modules only' | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
        'Refreshed modules:' | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null

        $RefreshedModules |
            Sort-Object -Unique |
            ForEach-Object { "- $_" } |
            Tee-Object -FilePath $RefreshedModulesLogPath -Append |
            Out-Null

        "===== Selected module refresh completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
    }

    function Save-SelectedModulesConfig {
        param(
            [Parameter(Mandatory)]
            [string[]]$SelectedModules
        )

        # Persist refreshed selected modules into this script's ModuleUpdateConfig block.
        $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-PowerShellModuleUpdates.ps1'

        if (-not (Test-Path -Path $scriptPath)) {
            Write-Warning "Unable to persist selected modules; script path not found: $scriptPath"
            return $false
        }

        $lines = Get-Content -Path $scriptPath -ErrorAction Stop
        $configStart = -1
        $selectedStart = -1
        $selectedEnd = -1

        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($configStart -lt 0 -and $lines[$index] -match '^\$ModuleUpdateConfig\s*=\s*@\{') {
                $configStart = $index
                continue
            }

            if ($configStart -ge 0 -and $selectedStart -lt 0 -and $lines[$index] -match '^\s*SelectedModules\s*=\s*@\(') {
                $selectedStart = $index
                continue
            }

            if ($selectedStart -ge 0 -and $lines[$index] -match '^\s*\)\s*$') {
                $selectedEnd = $index
                break
            }
        }

        if ($selectedStart -lt 0 -or $selectedEnd -lt 0) {
            Write-Warning 'Unable to persist selected modules; SelectedModules config block was not found.'
            return $false
        }

        $sortedModules = $SelectedModules | Sort-Object -Unique
        $moduleLines = @("    SelectedModules = @(")
        $moduleLines += $sortedModules | ForEach-Object { "        '$_'" }
        $moduleLines += '    )'

        $updatedLines = @()
        if ($selectedStart -gt 0) {
            $updatedLines += $lines[0..($selectedStart - 1)]
        }

        $updatedLines += $moduleLines

        if ($selectedEnd + 1 -lt $lines.Count) {
            $updatedLines += $lines[($selectedEnd + 1)..($lines.Count - 1)]
        }

        $updatedContent = $updatedLines -join "`r`n"

        Set-Content -Path $scriptPath -Value $updatedContent -Encoding utf8 -ErrorAction Stop
        return $true
    }

    function Write-RefreshedModulePersistenceStatus {
        param(
            [Parameter(Mandatory)]
            [string]$RefreshedModulesLogPath,

            [switch]$ConfigSaved,

            [Parameter(Mandatory)]
            [string]$ScriptPath
        )

        # Record whether refreshed modules were persisted to the script config.
        $status = if ($ConfigSaved) { 'Persisted selected modules config: SUCCESS' } else { 'Persisted selected modules config: FAILED' }
        $status | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
        "Persist target path: $ScriptPath" | Tee-Object -FilePath $RefreshedModulesLogPath -Append | Out-Null
    }

    function Remove-OldUpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        # Remove indexed log files older than the configured retention period.
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-(PowerShellModuleUpdates|WinGetUpdates)\.log$' -and
                $_.LastWriteTime -lt $cutoff
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
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

            # Track whether cleanup removed any module versions.
            $removedAny = $false

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
                            $removedAny = $true
                            "Cleanup: removed $desc"
                        }
                        catch {
                            Write-Warning "Failed to uninstall $desc`: $($_.Exception.Message)"
                        }
                    }
                }
            }

            # Record when cleanup ran but found nothing to remove.
            if (-not $removedAny) {
                'Cleanup: no older module versions were found.'
            }

            Write-Progress -Id 2 -ParentId 1 -Activity 'PowerShell module maintenance cleanup' -Completed
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
            [switch]$SkipRemoveOldVersions,
            [switch]$ShowTiming,
            [string]$ScopeMode
        )

        # Validate mutually exclusive scope parameters.
        if ($All -and $Name) {
            throw 'Specify either -All or -Name, but not both.'
        }

        # Ensure module update commands are available.
        if (-not (Get-Command Update-Module -ErrorAction SilentlyContinue) -or -not (Get-Command Find-Module -ErrorAction SilentlyContinue)) {
            Write-Error 'PowerShellGet is required. This script needs Update-Module and Find-Module.'
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
            Write-Host " `'$repoName`' is now trusted." -ForegroundColor Green
        }

        # Build explicit module names to process.
        $moduleNamesToProcess = @()
        if ($Name) {
            $moduleNamesToProcess = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | Sort-Object -Unique)
        }
        else {
            $moduleNamesToProcess = @(Get-Module -ListAvailable -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique | Sort-Object)
            $All = $true
        }

        if (-not $moduleNamesToProcess) {
            Write-Host 'No modules found from Get-InstalledModule.' -ForegroundColor Yellow
            return
        }

        $updatedModules = [System.Collections.Generic.List[string]]::new()
        $skippedModules = [System.Collections.Generic.List[string]]::new()
        $totalModules = @($moduleNamesToProcess).Count
        $moduleIndex = 0

        # Detect modules loaded in this session that cannot be updated in-place.
        $loadedModuleNames = @(Get-Module | Select-Object -ExpandProperty Name -Unique)

        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Module update phase starting' -PercentComplete 0

        foreach ($moduleName in $moduleNamesToProcess) {
            $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $moduleIndex++
            $percentComplete = [int](($moduleIndex / $totalModules) * 100)
            Write-Host "Processing module: $moduleName" -ForegroundColor DarkGray
            Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status "Update/Cleanup phase: checking $moduleIndex of $totalModules modules" -PercentComplete $percentComplete

            # Resolve installed module metadata for this specific module name.
            $preLookupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $installedVersions = @(Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending)
            $mod = $installedVersions | Select-Object -First 1
            $preLookupStopwatch.Stop()
            if ($ShowTiming) {
                Write-Host ("Timing: [{0}] Get-Module (pre/all versions): {1:N2}s" -f $moduleName, $preLookupStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
            }

            if (-not $mod) {
                $skippedModules.Add("$moduleName (not-found)")
                Write-Host "Skipping '$moduleName' — module metadata was not found." -ForegroundColor DarkYellow
                $moduleStopwatch.Stop()
                if ($ShowTiming) {
                    Write-Host ("Timing: [{0}] Total (not-found): {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                }
                continue
            }

            # Skip modules currently loaded in the session — they cannot be updated in-place.
            if ($loadedModuleNames -contains $moduleName) {
                $skippedModules.Add("$moduleName (in-use)")
                Write-Host "Skipping '$moduleName' — module is loaded in this session and cannot be updated in-place." -ForegroundColor DarkYellow
                $moduleStopwatch.Stop()
                if ($ShowTiming) {
                    Write-Host ("Timing: [{0}] Total (in-use): {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                }
                continue
            }

            # Check gallery for a newer version before running update.
            $checkUpdateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $galleryModule = Find-Module -Name $moduleName -Repository $repoName -ErrorAction SilentlyContinue
            $checkUpdateStopwatch.Stop()
            if ($ShowTiming) {
                Write-Host ("Timing: [{0}] Find-Module (check): {1:N2}s" -f $moduleName, $checkUpdateStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
            }

            if (-not $galleryModule) {
                $skippedModules.Add("$moduleName (not-in-gallery)")
                Write-Host "Skipping '$moduleName' — no PSGallery listing was found." -ForegroundColor DarkYellow
                $moduleStopwatch.Stop()
                if ($ShowTiming) {
                    Write-Host ("Timing: [{0}] Total (not-in-gallery): {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                }
                continue
            }

            try {
                # Use string comparison to handle prerelease version tags (e.g. 1.0.0-beta4).
                $startingVersionStr = "$($mod.Version)"
                $galleryVersionStr = "$($galleryModule.Version)"

                $hasUpdate = $true
                try {
                    $hasUpdate = ([version]$galleryVersionStr -gt [version]$startingVersionStr)
                }
                catch {
                    $hasUpdate = ($galleryVersionStr -ne $startingVersionStr)
                }

                if (-not $hasUpdate) {
                    $skippedModules.Add("$moduleName (up-to-date)")
                    if ($ShowTiming) {
                        Write-Host ("Timing: [{0}] Update skipped (up-to-date): installed={1}; gallery={2}" -f $moduleName, $startingVersionStr, $galleryVersionStr) -ForegroundColor DarkCyan
                    }
                    $moduleStopwatch.Stop()
                    if ($ShowTiming) {
                        Write-Host ("Timing: [{0}] Total (up-to-date): {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                    }
                    continue
                }

                # Skip modules that are not tracked by PowerShellGet Install-Module.
                $installedByPowerShellGet = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue
                if (-not $installedByPowerShellGet) {
                    $skippedModules.Add("$moduleName (not-installed-via-install-module)")
                    Write-Host "Skipping '$moduleName' — module was not installed using Install-Module." -ForegroundColor DarkYellow
                    $moduleStopwatch.Stop()
                    if ($ShowTiming) {
                        Write-Host ("Timing: [{0}] Total (not-installed-via-install-module): {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                    }
                    continue
                }

                $updateStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                Update-Module -Name $moduleName -ErrorAction Stop
                $updateStopwatch.Stop()
                if ($ShowTiming) {
                    Write-Host ("Timing: [{0}] Update-Module: {1:N2}s" -f $moduleName, $updateStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                }

                $postLookupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $latestInstalled = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue | Sort-Object -Property Version -Descending | Select-Object -First 1
                $postLookupStopwatch.Stop()
                if ($ShowTiming) {
                    Write-Host ("Timing: [{0}] Get-Module (post/all versions): {1:N2}s" -f $moduleName, $postLookupStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                }

                $latestVersionStr = if ($latestInstalled) { "$($latestInstalled.Version)" } else { $startingVersionStr }

                if ($latestVersionStr -ne $startingVersionStr) {
                    $updatedModules.Add("${moduleName}: $startingVersionStr -> $latestVersionStr")
                }
            }
            catch {
                $skippedModules.Add("$moduleName (error)")
                Write-Warning "⚠ Failed to update '$moduleName': $_"
            }

            # Run old-version cleanup for this module immediately after update.
            if (-not $SkipRemoveOldVersions -and (Get-Command Remove-OldModuleVersions -ErrorAction SilentlyContinue)) {
                try {
                    $cleanupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    Remove-OldModuleVersions -Name $moduleName -Confirm:$false
                    $cleanupStopwatch.Stop()
                    if ($ShowTiming) {
                        Write-Host ("Timing: [{0}] Remove-OldModuleVersions: {1:N2}s" -f $moduleName, $cleanupStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
                    }
                }
                catch {
                    Write-Warning "⚠ Failed to remove old module versions for '$moduleName': $_"
                }
            }

            $moduleStopwatch.Stop()
            if ($ShowTiming) {
                Write-Host ("Timing: [{0}] Total: {1:N2}s" -f $moduleName, $moduleStopwatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
            }
        }

        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Update/Cleanup phase completed' -PercentComplete 100

        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Completed

        # Emit summary for logging visibility.
        "Summary: $totalModules modules checked, $($updatedModules.Count) updated, $($skippedModules.Count) skipped."
        if ($skippedModules.Count -gt 0) {
            'Skipped modules:'
            $skippedModules | ForEach-Object { "  - $_" }
        }

        $updatedModules
    }

    function Invoke-PowerShellModuleUpdates {
        param(
            [Parameter(Mandatory)]
            [string]$PowerShellLogPath,

            [Parameter(Mandatory)]
            [hashtable]$ModuleUpdateParameters
        )

        # Write a run header, then update modules and remove old versions in the same log.
        $runHeader = "`n===== PowerShell module maintenance started: $(Get-Date -Format s) ====="
        $runHeader | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null

        # Record scope context with compact module display for non-all modes.
        $scopeMode = if ($ModuleUpdateParameters.ContainsKey('ScopeMode')) { "$($ModuleUpdateParameters.ScopeMode)" } else { 'ModuleNameList' }
        if ($scopeMode -eq 'AllUserScoped') {
            'Scope: All user-scoped modules' | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
        }
        else {
            $scopeLabel = if ($scopeMode -eq 'Common') { 'Common' } else { 'ModuleName' }
            $moduleListInline = @($ModuleUpdateParameters.Name) -join ', '
            "Scope: $scopeLabel | Modules: $moduleListInline" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
        }

        $updatedModuleLines = [System.Collections.Generic.List[string]]::new()
        $cleanupLines = [System.Collections.Generic.List[string]]::new()
        $warningErrorLines = [System.Collections.Generic.List[string]]::new()
        $summaryLines = [System.Collections.Generic.List[string]]::new()
        $skippedLines = [System.Collections.Generic.List[string]]::new()

        # Run module update and cleanup and process all streams in real time.
        & {
            Update-AllInstalledModules @ModuleUpdateParameters
        } *>&1 | ForEach-Object {
            $entry = $_

            if ($entry -is [System.Management.Automation.WarningRecord]) {
                $warningErrorLines.Add("WARNING: $($entry.Message)")
            }
            elseif ($entry -is [System.Management.Automation.ErrorRecord]) {
                $warningErrorLines.Add("ERROR: $($entry.Exception.Message)")
            }
            else {
                $text = "$entry"

                # Show per-module processing status in console only.
                if ($text -match '^Processing module:') {
                    $text | Out-Host
                }
                # Show per-call timing diagnostics in console only.
                elseif ($text -match '^Timing:') {
                    $text | Out-Host
                }
                # Capture module version change lines (Name: old -> new).
                elseif ($text -match '^[^:]+:\s+[^\s]+\s+->\s+[^\s]+$') {
                    $updatedModuleLines.Add($text)
                }
                # Capture cleanup and moved-module changes.
                elseif ($text -match '^Cleanup:') {
                    $cleanupLines.Add($text)
                }
                # Capture summary and skipped module lines.
                elseif ($text -match '^Summary:') {
                    $summaryLines.Add($text)
                }
                elseif ($text -match '^Skipped modules:|^  - ') {
                    $skippedLines.Add($text)
                }
                elseif ($text -like 'WARNING:*' -or $text -like 'ERROR:*') {
                    $warningErrorLines.Add($text)
                }
            }
        }

        # Track whether any module versions changed or old versions were cleaned up.
        $hasModuleChanges = ($updatedModuleLines.Count -gt 0 -or $cleanupLines.Count -gt 0)

        $logLines = [System.Collections.Generic.List[string]]::new()
        $updatedModuleLines | ForEach-Object { $logLines.Add($_) }
        $cleanupLines | ForEach-Object { $logLines.Add($_) }
        $warningErrorLines | ForEach-Object { $logLines.Add($_) }
        $summaryLines | ForEach-Object { $logLines.Add($_) }
        $skippedLines | ForEach-Object { $logLines.Add($_) }

        # Note when there were no module version changes and no warnings/errors.
        if ($logLines.Count -eq 0) {
            $logLines.Add('No PowerShell module version changes detected.')
        }

        $logLines | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Host

        # Record completion timestamp.
        "===== PowerShell module maintenance completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null

        return $hasModuleChanges
    }

    function Open-UpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$PowerShellLogPath,

            [Parameter(Mandatory)]
            [string]$RefreshedModulesLogPath,

            [switch]$PowerShellChanged,
            [switch]$RefreshLogCreated
        )

        # Launch logs only when updates were actually applied.
        if ($PowerShellChanged -and (Test-Path -Path $PowerShellLogPath)) {
            Invoke-Item -Path $PowerShellLogPath
        }

        # Launch refreshed selected modules log when a refresh was performed.
        if ($RefreshLogCreated -and (Test-Path -Path $RefreshedModulesLogPath)) {
            Invoke-Item -Path $RefreshedModulesLogPath
        }
    }
}
#endregion

#region EXECUTION
# Script entrypoint wrapper.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
#endregion
