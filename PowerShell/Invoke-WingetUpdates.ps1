# -------------------------------------------------------------------------
# Program: Invoke-WingetUpdates.ps1
# Description: Updates WinGet packages with indexed logs for login automation.
# Context: User login maintenance automation (Windows Task Scheduler)
# Author: Greg Tate
# ------------------------------------------------------------------------

[CmdletBinding()]
param(
    [ValidateRange(0, 3650)]
    [int]$RetentionDays = -1
)

# Configure log retention for indexed update log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}

$Main = {
    . $Helpers

    $wingetChanged = $false
    $logContext = New-UpdateLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $RetentionDays

    $wingetChanged = Invoke-WinGetUpdates -WinGetLogPath $logContext.WinGetLogPath
    Open-UpdateLogs -WinGetLogPath $logContext.WinGetLogPath -WingetChanged:$wingetChanged
}

$Helpers = {
    function New-UpdateLogContext {
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        # Create and return update log path under %APPDATA%.
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

        # Derive next same-day index so each run gets a unique log.
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-WinGetUpdates.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-WinGetUpdates$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        # Return log file context.
        [PSCustomObject]@{
            LogDirectory  = $logDirectory
            WinGetLogPath = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-WinGetUpdates.log"
        }
    }

    function Remove-OldUpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        # Remove indexed winget log files older than the configured retention period.
        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-WinGetUpdates\.log$' -and
                $_.LastWriteTime -lt $cutoff
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
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
            $originalConsoleEncoding = [Console]::OutputEncoding
            $originalOutputEncoding = $OutputEncoding
            $stdoutPath = Join-Path -Path $env:TEMP -ChildPath ("winget-update-{0}.stdout.log" -f ([guid]::NewGuid().ToString('N')))
            $stderrPath = Join-Path -Path $env:TEMP -ChildPath ("winget-update-{0}.stderr.log" -f ([guid]::NewGuid().ToString('N')))
            try {
                # Force UTF-8 so winget progress characters render correctly.
                [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
                $OutputEncoding = [System.Text.UTF8Encoding]::new($false)

                # Run winget with redirected output, then sanitize noisy progress/spinner lines.
                $wingetProcess = Start-Process -FilePath 'winget.exe' -ArgumentList @(
                    'update'
                    '--all'
                    '--silent'
                    '--disable-interactivity'
                    '--accept-package-agreements'
                    '--accept-source-agreements'
                ) -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

                $rawOutput = @()
                if (Test-Path -Path $stdoutPath) {
                    $rawOutput += Get-Content -Path $stdoutPath -ErrorAction SilentlyContinue
                }
                if (Test-Path -Path $stderrPath) {
                    $rawOutput += Get-Content -Path $stderrPath -ErrorAction SilentlyContinue
                }

                $cleanOutput = $rawOutput |
                    ForEach-Object { "$($_)".TrimEnd() } |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_) -and
                        $_ -notmatch '^\s*[-\\|/]\s*$' -and
                        $_ -notmatch 'Γû'
                    }

                if ($cleanOutput) {
                    $cleanOutput | Tee-Object -FilePath $WinGetLogPath -Append | Out-Host
                }
                else {
                    'No clean winget output lines were produced.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                }

                # Determine whether winget actually changed any package(s).
                $hasWingetChanges = $cleanOutput | Where-Object {
                    $_ -match '^Successfully installed$' -or
                    $_ -match '^Successfully upgraded$'
                } | Select-Object -First 1

                "winget exit code: $($wingetProcess.ExitCode)" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
                return [bool]$hasWingetChanges
            }
            finally {
                [Console]::OutputEncoding = $originalConsoleEncoding
                $OutputEncoding = $originalOutputEncoding

                if (Test-Path -Path $stdoutPath) {
                    Remove-Item -Path $stdoutPath -Force -ErrorAction SilentlyContinue
                }

                if (Test-Path -Path $stderrPath) {
                    Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        'winget.exe was not found on PATH.' | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        "===== WinGet update completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $WinGetLogPath -Append | Out-Null
        return $false
    }

    function Open-UpdateLogs {
        param(
            [Parameter(Mandatory)]
            [string]$WinGetLogPath,

            [switch]$WingetChanged
        )

        # Launch WinGet log only when package updates were actually applied.
        if ($WingetChanged -and (Test-Path -Path $WinGetLogPath)) {
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
