# -------------------------------------------------------------------------
# Program: functions.ps1
# Description: Provides custom interactive PowerShell profile functions.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PROFILE COMMAND FUNCTIONS
# Commands used by the profile aliases for Git, GitHub, Azure DevOps, and Docker workflows.

function Set-GitRepoRoot { Set-Location (git rev-parse --show-toplevel) }

function Show-GhFailedRunLog {
	param(
		[Alias('R')]
		[string]$Repository
	)

	[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
	$OutputEncoding = [Console]::OutputEncoding

	[System.Text.Encoding]::RegisterProvider(
		[System.Text.CodePagesEncodingProvider]::Instance
	)

	$cp437 = [System.Text.Encoding]::GetEncoding(437)
	$utf8  = [System.Text.UTF8Encoding]::new($false)

	$ansiPattern = '(?:\x1B\[[0-?]*[ -/]*[@-~]|\^\[\[[0-?]*[ -/]*[@-~])'
	$githubPrefix = '^.*?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*'

	# Use an explicit repository when the current location is outside a Git worktree.
	$repositoryArgument = if ($Repository) { @('--repo', $Repository) } else { @() }

	$runId = gh run list `
		@repositoryArgument `
		--status failure `
		--limit 1 `
		--json databaseId `
		--jq '.[0].databaseId'

	gh run view $runId @repositoryArgument --log-failed |
		ForEach-Object {
			$line = $_ -replace $ansiPattern, ''
			$line = $line -replace $githubPrefix, ''

			# Repair UTF-8 text that was incorrectly decoded as CP437.
			if ($line -match 'Γ(?:ö|ò)') {
				$line = $utf8.GetString($cp437.GetBytes($line))
			}

			# Optional: remove Terraform box-drawing characters completely.
			$line = $line -replace '[\u2500-\u257F]', ''

			$line.TrimEnd()
		} |
		Select-String `
			-Pattern 'Error:|Planning failed|Process completed with exit code' `
			-Context 5, 15 |
		ForEach-Object {
			# Output plain strings instead of Select-String's > indicators.
			$_.Context.PreContext
			$_.Line
			$_.Context.PostContext
		}
}

function Show-AdoFailedRunLog {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[Alias('O')]
		[string]$Organization,

		[Parameter(Mandatory)]
		[Alias('P')]
		[string]$Project,

		[Alias('D')]
		[int]$PipelineId,

		[switch]$FullLog
	)

	# Confirm the Azure CLI is available before invoking Azure DevOps commands.
	if (-not (Get-Command -Name az -ErrorAction SilentlyContinue)) {
		throw 'Azure CLI is required. Install it from https://aka.ms/installazurecliwindows.'
	}

	# Normalize a short organization name into the Azure DevOps Services URL expected by the CLI.
	$organizationUrl = $Organization.TrimEnd('/')
	if ($organizationUrl -notmatch '^https?://') {
		$organizationUrl = "https://dev.azure.com/$organizationUrl"
	}

	# Restrict the run query to one pipeline only when the caller supplies its ID.
	$pipelineArgument = @()
	if ($PipelineId) {
		$pipelineArgument = @('--pipeline-ids', $PipelineId)
	}

	# Retrieve the most recent failed pipeline run.
	$runOutput = az pipelines runs list `
		--organization $organizationUrl `
		--project $Project `
		@pipelineArgument `
		--status completed `
		--result failed `
		--top 1 `
		--query '[0]' `
		--output json
	if ($LASTEXITCODE -ne 0) {
		throw 'Unable to retrieve Azure DevOps pipeline runs.'
	}

	# Stop cleanly when the filtered run query returned no results.
	if ([string]::IsNullOrWhiteSpace(($runOutput -join [Environment]::NewLine)) -or
		($runOutput -join [Environment]::NewLine) -eq 'null') {
		Write-Warning 'No failed Azure DevOps pipeline runs were found.'
		return
	}

	# Retrieve timeline records so only failed task logs are requested.
	$run = $runOutput | ConvertFrom-Json
	$timelineOutput = az devops invoke `
		--area build `
		--resource timeline `
		--route-parameters "project=$Project" "buildId=$($run.id)" `
		--organization $organizationUrl `
		--api-version 7.1 `
		--output json
	if ($LASTEXITCODE -ne 0) {
		throw "Unable to retrieve the timeline for Azure DevOps run $($run.id)."
	}

	# Select failed timeline records that reference an individual task log.
	$timeline = $timelineOutput | ConvertFrom-Json
	$failedRecord = @(
		$timeline.records |
			Where-Object { $_.result -eq 'failed' -and $_.log.id }
	)
	if (-not $failedRecord) {
		Write-Warning "Run $($run.id) failed, but Azure DevOps did not return a failed task log."
		return
	}

	# Retrieve and display the logs for every failed task.
	foreach ($record in $failedRecord) {
		Write-Host "`n--- Failed task: $($record.name) ---" -ForegroundColor Red

		# Request plain-text content for the failed task's individual build log.
		# Azure CLI requires a file destination for this plain-text REST response.
		$logPath = Join-Path `
			-Path ([System.IO.Path]::GetTempPath()) `
			-ChildPath "ado-run-$($run.id)-log-$($record.log.id)-$([guid]::NewGuid()).log"
		try {
			# Write the failed task log to a unique temporary file.
			$null = az devops invoke `
				--area build `
				--resource logs `
				--route-parameters "project=$Project" "buildId=$($run.id)" "logId=$($record.log.id)" `
				--organization $organizationUrl `
				--api-version 7.1 `
				--accept-media-type text/plain `
				--out-file $logPath

			# Skip a task when its log cannot be retrieved and continue with the next failed task.
			if ($LASTEXITCODE -ne 0) {
				Write-Warning "Unable to retrieve log $($record.log.id) for task '$($record.name)'."
				continue
			}

			# Read the downloaded task log before removing its temporary file.
			$logOutput = Get-Content -LiteralPath $logPath
		}
		finally {
			# Remove the uniquely named temporary log file after every retrieval attempt.
			if (Test-Path -LiteralPath $logPath) {
				Remove-Item -LiteralPath $logPath -Force
			}
		}

		# Strip terminal color codes that may be present in task output.
		$cleanLog = @(
			$logOutput |
				ForEach-Object { $_ -replace '\x1B\[[0-?]*[ -/]*[@-~]', '' }
		)

		# Remove Azure Pipelines UTC timestamps from the beginning of each log line.
		$cleanLog = @(
			$cleanLog |
				ForEach-Object {
					$_ -replace '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s*', ''
				}
		)

		# Remove Terraform box-drawing glyphs and their incorrectly decoded equivalents.
		$cleanLog = @(
			$cleanLog |
				ForEach-Object {
					$_ -replace 'Γ(?:ò╖|öé|ò╡)\s?', '' -replace '[\u2500-\u257F]', ''
				}
		)
		if ($FullLog) {
			$cleanLog
			continue
		}

		# Highlight error context, while retaining the full log when no known marker exists.
		$failureContext = $cleanLog |
			Select-String `
				-Pattern '##\[error\]|##vso\[task\.logissue type=error|^ERROR:|Error:|Planning failed|Process completed with exit code' `
				-Context 5, 15
		if ($failureContext) {
			$failureContext |
				ForEach-Object {
					$_.Context.PreContext
					$_.Line
					$_.Context.PostContext
				}
		}
		else {
			$cleanLog
		}

		# Prevent the legacy direct-stream attempt below from running for this task.
		continue
		$logOutput = az devops invoke `
			--area build `
			--resource logs `
			--route-parameters "project=$Project" "buildId=$($run.id)" "logId=$($record.log.id)" `
			--organization $organizationUrl `
			--api-version 7.1 `
			--accept-media-type text/plain `
			--output tsv
		if ($LASTEXITCODE -ne 0) {
			Write-Warning "Unable to retrieve log $($record.log.id) for task '$($record.name)'."
			continue
		}

		# Strip terminal color codes that may be present in task output.
		$cleanLog = @(
			$logOutput |
				ForEach-Object { $_ -replace '\x1B\[[0-?]*[ -/]*[@-~]', '' }
		)
		if ($FullLog) {
			$cleanLog
			continue
		}

		# Highlight error context, while retaining the full log when no known marker exists.
		$failureContext = $cleanLog |
			Select-String `
				-Pattern '##\[error\]|##vso\[task\.logissue type=error|^ERROR:|Error:|Planning failed|Process completed with exit code' `
				-Context 5, 15
		if ($failureContext) {
			$failureContext |
				ForEach-Object {
					$_.Context.PreContext
					$_.Line
					$_.Context.PostContext
				}
		}
		else {
			$cleanLog
		}
	}
}

function DockerExec { docker exec -it @args }

function DockerImageList { docker image ls -a --no-trunc @args }

function DockerContainerList { docker container ls -a --no-trunc @args }

function RegCtlCmd { docker run --rm regclient/regctl @args }

#endregion

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


# Calculates the elapsed time between two clock values with AM implied unless PM is specified.
function Get-TimeDifference {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Start,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$End
    )

    # Convert the supported clock syntax into today's DateTime value.
    $convertToTime = {
        param(
            [string]$Value,

            [string]$ParameterName
        )

        # Reject dates, 24-hour values, and explicit AM to keep AM implicit.
        if ($Value -notmatch '^\s*(?<Hour>0?[1-9]|1[0-2])(?::(?<Minute>[0-5][0-9]))?\s*(?<Period>pm)?\s*$') {
            throw "$ParameterName must be H, H:mm, Hpm, or H:mmpm. AM is implicit; use pm for PM."
        }

        # Normalize the captured 12-hour value to its 24-hour equivalent.
        $hour = [int]$matches.Hour
        $minute = if ($matches.Minute) { [int]$matches.Minute } else { 0 }
        if ($matches.Period) {
            $hour = if ($hour -eq 12) { 12 } else { $hour + 12 }
        }
        elseif ($hour -eq 12) {
            $hour = 0
        }

        return [datetime]::Today.AddHours($hour).AddMinutes($minute)
    }

    # Parse both values before determining whether the interval passes midnight.
    $startTime = & $convertToTime -Value $Start -ParameterName 'Start'
    $endTime = & $convertToTime -Value $End -ParameterName 'End'

    # Treat an earlier end time as occurring on the following day.
    if ($endTime -lt $startTime) {
        $endTime = $endTime.AddDays(1)
    }

    # Return a compact duration that retains total hours without wrapping at 24.
    $duration = $endTime - $startTime
    '{0}:{1:D2}' -f [math]::Floor($duration.TotalHours), $duration.Minutes
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

#region AZURE BILLING FUNCTIONS
# Functions for retrieving Azure billing information from the loaded personal configuration.

# Retrieves billing subscriptions for the configured personal billing account.
function Get-BillingSubscriptions {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Verify the Azure CLI is available before making the billing API request.
    if (-not (Get-Command -Name az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI is required. Install it from https://aka.ms/installazurecliwindows.'
    }

    # Require the billing account ID supplied by the personal profile configuration.
    if (
        -not $Personal -or
        -not $Personal.ContainsKey('BillingAccountId') -or
        [string]::IsNullOrWhiteSpace($Personal.BillingAccountId)
    ) {
        throw 'Personal.BillingAccountId is not configured. Add it to PersonalConfig.psd1 and reload the profile.'
    }

    # Initialize the billing API request and the accumulated subscription results.
    $billingAccountId = [string]$Personal.BillingAccountId
    $apiVersion = '2024-04-01'
    $requestUrl = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$billingAccountId/billingSubscriptions?api-version=$apiVersion"
    $subscriptions = @()

    # Follow each continuation link so the command returns every billing subscription.
    do {
        $restOutput = az rest `
            --method get `
            --url $requestUrl `
            --headers 'x-ms-service-tenant-info=true' `
            --output json 2>&1

        # Stop with Azure CLI details when the billing request fails.
        if ($LASTEXITCODE -ne 0) {
            $details = ($restOutput | Out-String).Trim()
            throw "Unable to retrieve billing subscriptions. $details"
        }

        # Convert the page response before reading its values and continuation link.
        try {
            $response = $restOutput | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Unable to parse the billing subscriptions response. $($_.Exception.Message)"
        }

        # Shape each API result into the profile command's stable output contract.
        foreach ($billingSubscription in @($response.value)) {
            if ($null -eq $billingSubscription) {
                continue
            }

            $properties = $billingSubscription.properties
            $subscriptions += [PSCustomObject][ordered]@{
                SubscriptionName  = $properties.displayName
                SubscriptionId    = $properties.subscriptionId
                TenantId          = $properties.provisioningTenantId
                BillingProfile    = $properties.billingProfileDisplayName
                BillingProfileId  = $properties.billingProfileName
                InvoiceSection    = $properties.invoiceSectionDisplayName
                ProductType       = $properties.productType
                Status            = $properties.status
                PurchaseDate      = $properties.purchaseDate
                TermStartDate     = $properties.termStartDate
                TermEndDate       = $properties.termEndDate
                AutoRenew         = $properties.autoRenew
            }
        }

        $requestUrl = $response.nextLink
    }
    while ($requestUrl)

    return $subscriptions | Sort-Object -Property SubscriptionName
}

#endregion
