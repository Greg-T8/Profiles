# -------------------------------------------------------------------------
# Program: Split-Transcript.ps1
# Description: Split transcript files into chunks based on character limit
# Context: Utility script for processing video transcripts
# Author: Greg Tate
# -------------------------------------------------------------------------

function Split-Transcript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [int]$MaxChars = 20000,

        [int]$PeriodSeconds = 20,

        [string]$OutDir = ".\transcript_chunks_20k"
    )

    # Dot-source the helper functions
    . $SplitTranscriptHelpers

    # Validate input file exists
    if (!(Test-Path $InputFile)) {
        throw "Input file not found: $InputFile"
    }

    # Read and normalize input
    $raw = Get-Content -Path $InputFile -Raw -Encoding UTF8
    $text = $raw -replace "`r`n", "`n" -replace "`r", "`n"

    # Split into timestamp blocks
    $blocks = Get-TimestampBlock -Text $text

    # Consolidate blocks into time periods
    $periods = Join-BlockIntoPeriod -Blocks $blocks -PeriodSeconds $PeriodSeconds

    # Assemble periods into chunks within character limit
    $chunks = Join-BlockIntoChunk -Blocks $periods -MaxChars $MaxChars

    # Split any oversized chunks by line boundaries
    $finalChunks = Split-OversizedChunk -Chunks $chunks -MaxChars $MaxChars

    # Write output files
    $written = Write-ChunkFile -Chunks $finalChunks -OutDir $OutDir -InputFile $InputFile

    # Create zip archive
    $zipPath = New-ChunkArchive -InputFile $InputFile -OutDir $OutDir

    # Display summary
    Show-Summary -Written $written -OutDir $OutDir -ZipPath $zipPath
}

$SplitTranscriptHelpers = {
    function Get-TimestampFromText {
        param([string]$Text)

        # Matches MM:SS or HH:MM:SS at start of line
        [regex]::Matches($Text, '(?m)^(?<ts>\d{1,2}:\d{2}(?::\d{2})?)') |
            ForEach-Object { $_.Groups['ts'].Value }
    }

    function ConvertTo-NormalizedTimestamp([string]$ts) {
        # Convert MM:SS to HH:MM:SS format, or keep HH:MM:SS as-is
        $parts = $ts -split ":"
        if ($parts.Count -eq 2) {
            return "00:{0:D2}:{1:D2}" -f [int]$parts[0], [int]$parts[1]
        } elseif ($parts.Count -eq 3) {
            return "{0:D2}:{1:D2}:{2:D2}" -f [int]$parts[0], [int]$parts[1], [int]$parts[2]
        }
        return $ts
    }

    function ConvertTo-SafeTimestamp([string]$ts) {
        # HH:MM:SS -> HH-MM-SS
        $ts -replace ":", "-"
    }

    function ConvertTo-TotalSeconds([string]$ts) {
        # Convert timestamp to total seconds
        $parts = $ts -split ":"
        if ($parts.Count -eq 2) {
            return [int]$parts[0] * 60 + [int]$parts[1]
        } elseif ($parts.Count -eq 3) {
            return [int]$parts[0] * 3600 + [int]$parts[1] * 60 + [int]$parts[2]
        }
        return 0
    }

    function Get-TimestampBlock {
        param([string]$Text)

        $tsRegex = [regex]'(?m)^(?<ts>\d{1,2}:\d{2}(?::\d{2})?)\s'
        $tsMatches = $tsRegex.Matches($Text)
        $blocks = New-Object System.Collections.Generic.List[string]

        if ($tsMatches.Count -gt 0) {
            # Split by timestamp boundaries
            for ($i = 0; $i -lt $tsMatches.Count; $i++) {
                $start = $tsMatches[$i].Index
                $end = if ($i -lt $tsMatches.Count - 1) { $tsMatches[$i + 1].Index } else { $Text.Length }
                $blk = $Text.Substring($start, $end - $start)
                $blocks.Add($blk)
            }
        } else {
            # Fallback: split by blank lines into paragraph blocks
            $paras = $Text -split "(`n\s*`n)+" | Where-Object { $_.Trim().Length -gt 0 }
            foreach ($p in $paras) { $blocks.Add($p + "`n") }
        }

        return $blocks
    }

    function Join-BlockIntoPeriod {
        param(
            [System.Collections.Generic.List[string]]$Blocks,
            [int]$PeriodSeconds
        )

        $periods = New-Object System.Collections.Generic.List[string]
        $tsRegex = [regex]'^(?<ts>\d{1,2}:\d{2}(?::\d{2})?)'
        $currentPeriodStart = -1
        $currentStartTs = ""
        $currentEndTs = ""
        $currentText = New-Object System.Collections.Generic.List[string]

        foreach ($block in $Blocks) {
            # Extract timestamp and text from block
            $match = $tsRegex.Match($block)
            if ($match.Success) {
                $ts = $match.Groups['ts'].Value
                $seconds = ConvertTo-TotalSeconds $ts
                $textContent = $block.Substring($match.Length).Trim()

                # Skip empty text content
                if ([string]::IsNullOrWhiteSpace($textContent)) { continue }

                # Determine period boundary
                $periodStart = [Math]::Floor($seconds / $PeriodSeconds) * $PeriodSeconds

                if ($currentPeriodStart -eq -1) {
                    # First block
                    $currentPeriodStart = $periodStart
                    $currentStartTs = $ts
                    $currentEndTs = $ts
                    $currentText.Add($textContent)
                } elseif ($periodStart -eq $currentPeriodStart) {
                    # Same period - accumulate text
                    $currentEndTs = $ts
                    $currentText.Add($textContent)
                } else {
                    # New period - flush current and start new
                    $startNorm = ConvertTo-NormalizedTimestamp $currentStartTs
                    $endNorm = ConvertTo-NormalizedTimestamp $currentEndTs
                    $periodContent = "$startNorm-$endNorm `n" + ($currentText -join " ") + "`n`n"
                    $periods.Add($periodContent)

                    $currentPeriodStart = $periodStart
                    $currentStartTs = $ts
                    $currentEndTs = $ts
                    $currentText.Clear()
                    $currentText.Add($textContent)
                }
            }
        }

        # Flush final period
        if ($currentText.Count -gt 0) {
            $startNorm = ConvertTo-NormalizedTimestamp $currentStartTs
            $endNorm = ConvertTo-NormalizedTimestamp $currentEndTs
            $periodContent = "$startNorm-$endNorm `n" + ($currentText -join " ") + "`n`n"
            $periods.Add($periodContent)
        }

        return $periods
    }

    function Join-BlockIntoChunk {
        param(
            [System.Collections.Generic.List[string]]$Blocks,
            [int]$MaxChars
        )

        $chunks = New-Object System.Collections.Generic.List[string]
        $current = ""

        foreach ($b in $Blocks) {
            if (($current.Length + $b.Length) -le $MaxChars) {
                $current += $b
            } else {
                if ($current.Trim().Length -gt 0) { $chunks.Add($current) }
                $current = $b
            }
        }

        if ($current.Trim().Length -gt 0) { $chunks.Add($current) }

        return $chunks
    }

    function Split-OversizedChunk {
        param(
            [System.Collections.Generic.List[string]]$Chunks,
            [int]$MaxChars
        )

        $finalChunks = New-Object System.Collections.Generic.List[string]

        foreach ($c in $Chunks) {
            if ($c.Length -le $MaxChars) {
                $finalChunks.Add($c)
            } else {
                # Split by line boundaries
                $lines = $c -split "`n", -1 | ForEach-Object { $_ + "`n" }
                $tmp = ""
                foreach ($ln in $lines) {
                    if (($tmp.Length + $ln.Length) -le $MaxChars) {
                        $tmp += $ln
                    } else {
                        if ($tmp.Trim().Length -gt 0) { $finalChunks.Add($tmp) }
                        $tmp = $ln
                    }
                }
                if ($tmp.Trim().Length -gt 0) { $finalChunks.Add($tmp) }
            }
        }

        return $finalChunks
    }

    function Write-ChunkFile {
        param(
            [System.Collections.Generic.List[string]]$Chunks,
            [string]$OutDir,
            [string]$InputFile
        )

        # Prepare output directory
        if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
        New-Item -ItemType Directory -Path $OutDir | Out-Null

        $index = 1
        $written = @()

        foreach ($chunk in $Chunks) {
            # Extract timestamps from chunk
            $tsList = Get-TimestampFromText -Text $chunk
            if ($tsList.Count -gt 0) {
                $startTs = ConvertTo-NormalizedTimestamp $tsList[0]
                $endTs = ConvertTo-NormalizedTimestamp $tsList[$tsList.Count - 1]
            } else {
                $startTs = "00:00:00"
                $endTs = "00:00:00"
            }

            $safeStart = ConvertTo-SafeTimestamp $startTs
            $safeEnd = ConvertTo-SafeTimestamp $endTs

            # Write chunk file
            $name = ("Transcript_Part_{0:D2}_{1}_to_{2}.txt" -f $index, $safeStart, $safeEnd)
            $path = Join-Path $OutDir $name
            [System.IO.File]::WriteAllText($path, $chunk, [System.Text.Encoding]::UTF8)
            $written += $path
            $index++
        }

        return $written
    }

    function New-ChunkArchive {
        param(
            [string]$InputFile,
            [string]$OutDir
        )

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
        $zipPath = Join-Path (Split-Path $OutDir -Parent) "$baseName.zip"

        if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
        Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath

        return $zipPath
    }

    function Show-Summary {
        param(
            [array]$Written,
            [string]$OutDir,
            [string]$ZipPath
        )

        $maxLen = ($Written | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Maximum).Maximum
        $minLen = ($Written | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Minimum).Minimum

        Write-Host "Created $($Written.Count) chunk files."
        Write-Host "Output folder: $OutDir"
        Write-Host "ZIP: $ZipPath"
        Write-Host "Max chars (bytes): $maxLen"
        Write-Host "Min chars (bytes): $minLen"
    }
}
