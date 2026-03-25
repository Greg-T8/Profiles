<#
.SYNOPSIS
Removes old files from the Snagit Captures folder and writes indexed logs.

.DESCRIPTION
Deletes files older than a configured age from the Snagit Captures folder,
then outputs cleanup totals for files removed and total size reclaimed.
Logs are written to date-indexed files under %APPDATA%\_UserPackageAndModuleUpdates.

.CONTEXT
User login maintenance automation (Windows Task Scheduler)

.AUTHOR
Greg Tate

.PARAMETER LogRetentionDays
Number of days to retain indexed cleanup log files.
A value of -1 (default) uses the configured retention period.
A value of 0 removes existing cleanup logs before the current run.

.PARAMETER CaptureFolderPath
Optional override for the Snagit capture folder path.
Defaults to $env:USERPROFILE\Snagit Captures.

.PARAMETER AgeInDays
Number of days used to calculate the cleanup cutoff date.
Files older than this threshold are removed.

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1 -LogRetentionDays 7

.EXAMPLE
.\Invoke-SnagitCaptureFolderCleanup.ps1 -AgeInDays 30

.NOTES
Program: Invoke-SnagitCaptureFolderCleanup.ps1
#>

#region PARAMETERS
[CmdletBinding()]
param(
    [ValidateRange(-1, 3650)]
    [int]$LogRetentionDays = -1,

    [ValidateNotNullOrEmpty()]
    [string]$CaptureFolderPath = (Join-Path -Path $env:USERPROFILE -ChildPath 'Snagit Captures'),

    [ValidateRange(1, 3650)]
    [int]$AgeInDays = 30
)
#endregion

#region CONFIGURATION
# Configure default cleanup behavior for capture files.
$SnagitCleanupConfig = @{
    AgeInDays = 14
}

# Configure log retention for indexed cleanup log files.
$LogRetentionConfig = @{
    Enabled       = $true
    RetentionDays = 30
}
#endregion

#region MAIN
# Orchestrate log preparation, cleanup execution, and result output.
$Main = {
    . $Helpers

    # Build indexed log context and apply retention before this run.
    $logContext = New-CleanupLogContext -LogRetentionConfig $LogRetentionConfig -RetentionDaysOverride $LogRetentionDays

    # Compute cutoff date and perform capture folder cleanup.
    $effectiveAgeInDays = $AgeInDays
    if (-not $PSBoundParameters.ContainsKey('AgeInDays')) {
        $effectiveAgeInDays = [int]$SnagitCleanupConfig.AgeInDays
    }

    $cutoffDate = (Get-Date).AddDays(-$effectiveAgeInDays)
    $cleanupResult = Invoke-SnagitCaptureCleanup -CaptureFolderPath $CaptureFolderPath -CutoffDate $cutoffDate -SnagitCleanupLogPath $logContext.SnagitCleanupLogPath

    $cleanupResult
}
#endregion

#region HELPERS
# Define helper functions used by the main orchestration flow.
$Helpers = {
    function New-CleanupLogContext {
        # Create and return indexed cleanup log paths under %APPDATA%.
        param(
            [Parameter(Mandatory)]
            [hashtable]$LogRetentionConfig,

            [int]$RetentionDaysOverride = -1
        )

        $logDirectory = Join-Path -Path $env:APPDATA -ChildPath '_UserPackageAndModuleUpdates'
        if (-not (Test-Path -Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
        }

        # Apply retention policy before calculating the next same-day log index.
        if ($LogRetentionConfig.Enabled) {
            $effectiveRetentionDays = if ($RetentionDaysOverride -ge 0) {
                $RetentionDaysOverride
            }
            else {
                [int]$LogRetentionConfig.RetentionDays
            }

            if ($effectiveRetentionDays -eq 0) {
                Clear-AllCleanupLogs -LogDirectory $logDirectory
            }
            elseif ($effectiveRetentionDays -gt 0) {
                Remove-OldCleanupLogs -LogDirectory $logDirectory -RetentionDays $effectiveRetentionDays
            }
        }

        $datePrefix = Get-Date -Format 'yyyy-MM-dd'
        $existingIndices = Get-ChildItem -Path $logDirectory -File -Filter "$datePrefix-*-SnagitCaptureFolderCleanup.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.BaseName -match "^$datePrefix-(\d+)-SnagitCaptureFolderCleanup$") {
                    [int]$Matches[1]
                }
            } |
            Where-Object { $_ -is [int] }

        [int]$nextIndex = if ($existingIndices) { ($existingIndices | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        $indexPrefix = $nextIndex.ToString('D3')

        [PSCustomObject]@{
            LogDirectory          = $logDirectory
            SnagitCleanupLogPath  = Join-Path -Path $logDirectory -ChildPath "$datePrefix-$indexPrefix-SnagitCaptureFolderCleanup.log"
        }
    }

    function Remove-OldCleanupLogs {
        # Remove indexed cleanup logs older than the configured retention period.
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory,

            [Parameter(Mandatory)]
            [ValidateRange(1, 3650)]
            [int]$RetentionDays
        )

        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-SnagitCaptureFolderCleanup\.log$' -and
                $_.LastWriteTime -lt $cutoff
            } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Clear-AllCleanupLogs {
        # Remove all indexed cleanup logs when retention is explicitly set to zero.
        param(
            [Parameter(Mandatory)]
            [string]$LogDirectory
        )

        Get-ChildItem -Path $LogDirectory -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}-\d{3}-SnagitCaptureFolderCleanup\.log$' } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Invoke-SnagitCaptureCleanup {
        # Remove old files from the capture folder and return cleanup totals.
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$CaptureFolderPath,

            [Parameter(Mandatory)]
            [datetime]$CutoffDate,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$SnagitCleanupLogPath
        )

        "===== Snagit cleanup started: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "Capture folder: $CaptureFolderPath" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "Cutoff date: $($CutoffDate.ToString('s'))" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

        if (-not (Test-Path -Path $CaptureFolderPath)) {
            'Capture folder does not exist. No files removed.' | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
            "===== Snagit cleanup completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

            return [PSCustomObject]@{
                CaptureFolderPath = $CaptureFolderPath
                CutoffDate        = $CutoffDate
                FilesRemoved      = 0
                BytesRemoved      = 0
                SizeRemovedMB     = 0
            }
        }

        $filesToRemove = @(Get-ChildItem -Path $CaptureFolderPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $CutoffDate })
        $filesRemoved = $filesToRemove.Count
        [int64]$bytesRemoved = ($filesToRemove | Measure-Object -Property Length -Sum).Sum

        if (-not $bytesRemoved) {
            $bytesRemoved = 0
        }

        if ($filesRemoved -gt 0) {
            $filesToRemove | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        $sizeRemovedMB = [math]::Round(($bytesRemoved / 1MB), 2)
        "Summary: Removed $filesRemoved files totaling $sizeRemovedMB MB ($bytesRemoved bytes)." | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null
        "===== Snagit cleanup completed: $(Get-Date -Format s) =====" | Tee-Object -FilePath $SnagitCleanupLogPath -Append | Out-Null

        return [PSCustomObject]@{
            CaptureFolderPath = $CaptureFolderPath
            CutoffDate        = $CutoffDate
            FilesRemoved      = $filesRemoved
            BytesRemoved      = $bytesRemoved
            SizeRemovedMB     = $sizeRemovedMB
        }
    }

    function Open-CleanupLog {
        # Open the cleanup log file only when files were removed in this run.
        param(
            [Parameter(Mandatory)]
            [string]$SnagitCleanupLogPath,

            [Parameter(Mandatory)]
            [int]$FilesRemoved
        )

        if ($FilesRemoved -gt 0 -and (Test-Path -Path $SnagitCleanupLogPath)) {
            Invoke-Item -Path $SnagitCleanupLogPath
        }
    }
}
#endregion

#region EXECUTION
# Execute from script root and always restore caller location.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
#endregion
