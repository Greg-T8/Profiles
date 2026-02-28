# -------------------------------------------------------------------------
# Program: Invoke-UserPackageAndModuleUpdates.ps1
# Description: Updates PowerShell modules and WinGet packages with per-tool logs for login automation.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

[CmdletBinding()]
param()

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
        'PowerShellGet'
    )
}

$Main = {
    . $Helpers

    $logContext = New-UpdateLogContext
    $moduleUpdateParameters = New-ModuleUpdateParameters -ModuleUpdateConfig $ModuleUpdateConfig
    Invoke-PowerShellModuleUpdates -PowerShellLogPath $logContext.PowerShellLogPath -ModuleUpdateParameters $moduleUpdateParameters
    Invoke-WinGetUpdates -WinGetLogPath $logContext.WinGetLogPath
    Open-UpdateLogs -PowerShellLogPath $logContext.PowerShellLogPath -WinGetLogPath $logContext.WinGetLogPath
}

$Helpers = {
    function New-ModuleUpdateParameters {
        param(
            [Parameter(Mandatory)]
            [hashtable]$ModuleUpdateConfig
        )

        # Validate scope and return mutually exclusive parameter set for module maintenance.
        $scope = "$($ModuleUpdateConfig.Scope)"
        if ($scope -ieq 'All') {
            return @{ All = $true }
        }

        if ($scope -ieq 'Selected') {
            $selectedModules = @($ModuleUpdateConfig.SelectedModules | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
            if (-not $selectedModules) {
                throw "ModuleUpdateConfig.Scope is 'Selected' but SelectedModules is empty."
            }

            return @{ Name = $selectedModules }
        }

        throw "Invalid ModuleUpdateConfig.Scope '$scope'. Use 'Selected' or 'All'."
    }

    function New-UpdateLogContext {
        # Create and return update log paths under %APPDATA%.
        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        # Prefix log file names with the run date.
        $datePrefix = Get-Date -Format 'yyyy-MM-dd'

        # Return both log file paths in a single object.
        [PSCustomObject]@{
            LogDirectory       = $logDirectory
            PowerShellLogPath  = Join-Path -Path $logDirectory -ChildPath "$datePrefix-PowerShellModuleUpdates.log"
            WinGetLogPath      = Join-Path -Path $logDirectory -ChildPath "$datePrefix-WinGetUpdates.log"
        }
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
            "Scope: Selected modules ($($ModuleUpdateParameters.Name -join ', '))" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
        }

        # Load functions and run module maintenance pipeline.
        $functionsPath = Join-Path -Path $PSScriptRoot -ChildPath 'functions.ps1'
        if (-not (Test-Path -Path $functionsPath)) {
            "functions.ps1 not found at $functionsPath" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
            return
        }

        # Run module update and cleanup and capture all streams for selective logging.
        $moduleMaintenanceOutput = & {
            . $functionsPath
            Update-AllInstalledModules @ModuleUpdateParameters
        } *>&1

        # Keep only update lines and warning/error content in the PowerShell log.
        $logLines = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $moduleMaintenanceOutput) {
            if ($entry -is [System.Management.Automation.WarningRecord]) {
                $logLines.Add("WARNING: $($entry.Message)")
                continue
            }

            if ($entry -is [System.Management.Automation.ErrorRecord]) {
                $logLines.Add("ERROR: $($entry.Exception.Message)")
                continue
            }

            $text = "$entry"
            if ($text -match '^[^:]+:\s+[^\s]+\s+->\s+[^\s]+$') {
                $logLines.Add($text)
                continue
            }

            if ($text -like 'WARNING:*' -or $text -like 'ERROR:*') {
                $logLines.Add($text)
            }
        }

        # Note when there were no module version changes and no warnings/errors.
        if ($logLines.Count -eq 0) {
            $logLines.Add('No PowerShell module version changes detected.')
        }

        $logLines | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Host

        # Record completion timestamp.
        "===== PowerShell module maintenance completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $PowerShellLogPath -Append | Out-Null
    }

    function Invoke-WinGetUpdates {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Write a run header for this WinGet update pass.
        $runHeader = "`n===== WinGet update started: $(Get-Date -Format s) ====="
        $runHeader | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null

        # Execute WinGet updates silently and capture output to the WinGet log.
        if (Get-Command -Name winget.exe -ErrorAction SilentlyContinue) {
            & winget update --all --silent 2>&1 | Tee-Object -FilePath $WinGetLogPath -Append | Out-Host
            "winget exit code: $LASTEXITCODE" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        }
        else {
            'winget.exe was not found on PATH.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        }

        # Record completion timestamp.
        "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
    }

    function Open-UpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$PowerShellLogPath,

            [Parameter(Mandatory)]
            [string]$WinGetLogPath
        )

        # Launch both logs so results are immediately visible after task execution.
        if (Test-Path -Path $PowerShellLogPath) {
            Invoke-Item -Path $PowerShellLogPath
        }

        # Launch the WinGet log as well.
        if (Test-Path -Path $WinGetLogPath) {
            Invoke-Item -Path $WinGetLogPath
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