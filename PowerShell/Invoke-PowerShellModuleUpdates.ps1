# -------------------------------------------------------------------------
# Program: Invoke-PowerShellModuleUpdates.ps1
# Description: Updates PowerShell modules and WinGet packages with per-tool logs for login automation.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

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
    [int]$RecentHistoryLines = 5000
)

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

$Main = {
    . $Helpers
    $powerShellChanged = $false
    $refreshLogCreated = $false

    $logContext = New-UpdateLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $RetentionDays

    $moduleScopeMode = 'Common'
    if ($useAllModules) { $moduleScopeMode = 'AllUserScoped' }
    if ($useModuleNameList) { $moduleScopeMode = 'ModuleNameList' }

    $moduleUpdateParameters = New-ModuleUpdateParameters -ModuleUpdateConfig $ModuleUpdateConfig -ScopeMode $moduleScopeMode -ModuleName $ModuleName -RecentHistoryLines $RecentHistoryLines
    $powerShellChanged = Invoke-PowerShellModuleUpdates -PowerShellLogPath $logContext.PowerShellLogPath -ModuleUpdateParameters $moduleUpdateParameters

    Open-UpdateLogs -PowerShellLogPath $logContext.PowerShellLogPath -RefreshedModulesLogPath $logContext.RefreshedModulesLogPath -PowerShellChanged:$powerShellChanged -RefreshLogCreated:$refreshLogCreated
}

$Helpers = {
    function New-ModuleUpdateParameters {
        param(
            [Parameter(Mandatory)]
            [hashtable]$ModuleUpdateConfig,

            [ValidateSet('Common', 'AllUserScoped', 'ModuleNameList')]
            [string]$ScopeMode = 'Common',

            [string[]]$ModuleName = @(),

            [int]$RecentHistoryLines = 5000
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

            return @{ Name = @($allUserScopedModules) }
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

            return @{ Name = $matchedModules }
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

            return @{ Name = $selectedModulesFromConfig }
        }

        throw "Invalid scope mode '$ScopeMode'. Use 'Common', 'AllUserScoped', or 'ModuleNameList'."
    }

    function Get-CurrentUserInstalledModuleNames {
        # Return unique module names installed in CurrentUser scope.
        $userModuleRoots = @(
            (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules'),
            (Join-Path -Path $HOME -ChildPath 'Documents\WindowsPowerShell\Modules')
        )

        $supportsScope = (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue).Parameters.ContainsKey('Scope')

        if ($supportsScope) {
            $currentUserInstalled = Get-InstalledModule -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        else {
            $allInstalled = Get-InstalledModule -ErrorAction SilentlyContinue
            $currentUserInstalled = $allInstalled | Where-Object {
                $installRoot = "$($_.InstalledLocation)"
                $userModuleRoots | Where-Object { $installRoot -like "$($_)*" }
            }
        }

        $moduleNames = @()
        if ($currentUserInstalled) {
            $moduleNames += $currentUserInstalled | Select-Object -ExpandProperty Name -Unique
        }

        if (Get-Command Get-InstalledPSResource -ErrorAction SilentlyContinue) {
            $currentUserResources = Get-InstalledPSResource -Scope CurrentUser -ErrorAction SilentlyContinue
            if ($currentUserResources) {
                $moduleNames += $currentUserResources | Select-Object -ExpandProperty Name -Unique
            }
        }

        $userPathModules = Get-Module -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            $moduleBase = "$($_.ModuleBase)"
            $userModuleRoots | Where-Object { $moduleBase -like "$($_)*" }
        }
        if ($userPathModules) {
            $moduleNames += $userPathModules | Select-Object -ExpandProperty Name -Unique
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
            [switch]$SkipRemoveOldVersions
        )

        # Validate mutually exclusive scope parameters.
        if ($All -and $Name) {
            throw 'Specify either -All or -Name, but not both.'
        }

        # Ensure PowerShellGet v2 is available.
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
        $skippedModules = [System.Collections.Generic.List[string]]::new()
        $totalModules = @($modules).Count
        $moduleIndex = 0

        # Detect modules loaded in this session that cannot be updated in-place.
        $loadedModuleNames = @(Get-Module | Select-Object -ExpandProperty Name -Unique)

        Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status 'Module update phase starting' -PercentComplete 0

        foreach ($mod in $modules) {
            $moduleIndex++
            $percentComplete = [int](($moduleIndex / $totalModules) * 100)
            Write-Host "Processing module: $($mod.Name)" -ForegroundColor DarkGray
            Write-Progress -Id 1 -Activity 'PowerShell module maintenance' -Status "Update/Cleanup phase: checking $moduleIndex of $totalModules modules" -PercentComplete $percentComplete

            # Skip modules currently loaded in the session — they cannot be updated in-place.
            if ($loadedModuleNames -contains $mod.Name) {
                $skippedModules.Add("$($mod.Name) (in-use)")
                Write-Warning "Skipping '$($mod.Name)' — module is loaded in this session and cannot be updated in-place."
                continue
            }

            try {
                # Use string comparison to handle prerelease version tags (e.g. 1.0.0-beta4).
                $startingVersionStr = "$($mod.Version)"
                Update-Module -Name $mod.Name -ErrorAction Stop

                $latestInstalled = Get-InstalledModule -Name $mod.Name -ErrorAction SilentlyContinue
                $latestVersionStr = if ($latestInstalled) { "$($latestInstalled.Version)" } else { $startingVersionStr }

                if ($latestVersionStr -ne $startingVersionStr) {
                    $updatedModules.Add("$($mod.Name): $startingVersionStr -> $latestVersionStr")
                }
            }
            catch {
                $skippedModules.Add("$($mod.Name) (error)")
                Write-Warning "⚠ Failed to update '$($mod.Name)': $_"
            }

            # Run old-version cleanup for this module immediately after update.
            if (-not $SkipRemoveOldVersions -and (Get-Command Remove-OldModuleVersions -ErrorAction SilentlyContinue)) {
                try {
                    Remove-OldModuleVersions -Name $mod.Name -Confirm:$false
                }
                catch {
                    Write-Warning "⚠ Failed to remove old module versions for '$($mod.Name)': $_"
                }
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

        # Record whether this run targets all modules or only a configured subset.
        if ($ModuleUpdateParameters.ContainsKey('All')) {
            'Scope: All installed modules' | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
        }
        else {
            'Scope: Selected modules' | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
            $ModuleUpdateParameters.Name |
                ForEach-Object { "- $_" } |
                Tee-Object -FilePath $PowerShellLogPath -Append |
                Out-Null
        }

        $logLines = [System.Collections.Generic.List[string]]::new()

        # Run module update and cleanup and process all streams in real time.
        & {
            Update-AllInstalledModules @ModuleUpdateParameters
        } *>&1 | ForEach-Object {
            $entry = $_

            if ($entry -is [System.Management.Automation.WarningRecord]) {
                $logLines.Add("WARNING: $($entry.Message)")
            }
            elseif ($entry -is [System.Management.Automation.ErrorRecord]) {
                $logLines.Add("ERROR: $($entry.Exception.Message)")
            }
            else {
                $text = "$entry"

                # Show per-module processing status in console only.
                if ($text -match '^Processing module:') {
                    $text | Out-Host
                }
                # Capture module version change lines (Name: old -> new).
                elseif ($text -match '^[^:]+:\s+[^\s]+\s+->\s+[^\s]+$') {
                    $logLines.Add($text)
                }
                # Capture summary, cleanup, and skipped module lines.
                elseif ($text -match '^(Summary:|Skipped modules:|Cleanup:|  - )') {
                    $logLines.Add($text)
                }
                elseif ($text -like 'WARNING:*' -or $text -like 'ERROR:*') {
                    $logLines.Add($text)
                }
            }
        }

        # Track whether any module versions changed or old versions were cleaned up.
        $hasModuleChanges = $logLines | Where-Object { $_ -match '^[^:]+:\s+[^\s]+\s+->\s+[^\s]+$' -or $_ -match '^Cleanup:' } | Select-Object -First 1

        # Note when there were no module version changes and no warnings/errors.
        if ($logLines.Count -eq 0) {
            $logLines.Add('No PowerShell module version changes detected.')
        }

        $logLines | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Host

        # Record completion timestamp.
        "===== PowerShell module maintenance completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null

        return [bool]$hasModuleChanges
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

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
