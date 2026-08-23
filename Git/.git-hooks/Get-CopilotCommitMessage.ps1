<#
.SYNOPSIS
Generates a Git commit message from staged changes with GitHub Copilot.

.DESCRIPTION
Uses the complete staged diff for small commits and a bounded metadata summary
for large commits. The script emits only the generated commit message to
standard output.

.CONTEXT
Personal Git workflow - bounded Copilot commit-message generation.

.AUTHOR
Greg Tate

.NOTES
Program: Get-CopilotCommitMessage.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [ValidateNotNullOrEmpty()]
    [string]$Model = 'mai-code-1.1-flash'
)

#region CONFIGURATION
# Limits that preserve the direct fast path and bound the summary fallback.
$DirectPromptMaxChars = 24000
$SummaryMaxChars = 16000
#endregion

#region MAIN WORKFLOW
# Orchestrates staged-change collection, prompt selection, and Copilot output.
$Main = {
    . $Helpers

    Get-StagedDiff
    New-CommitPrompt
    Get-CopilotMessage
}
#endregion

#region HELPER FUNCTIONS
# Functions that build the prompt and retrieve the generated commit message.
$Helpers = {
    function Get-StagedDiff {
        # Collect the complete staged diff for the direct prompt decision.
        $script:StagedDiff = & git -C $RepositoryPath diff `
            --cached `
            --no-ext-diff `
            --no-color `
            --unified=1 |
            Out-String

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to retrieve the staged Git diff.'
        }
    }

    function New-CommitPrompt {
        # Use the complete diff when it remains within the Windows command-line budget.
        $directPrompt = @"

Write only a Git commit message for the staged diff below.

Use an imperative subject of at most 72 characters. Do not use Conventional
Commit prefixes. Add a body only when useful to explain what changed and why.
Do not include Markdown, commentary, trailers, or questions.

Staged diff:

$script:StagedDiff
"@

        if ($directPrompt.Length -le $DirectPromptMaxChars) {
            $script:Prompt = $directPrompt
            $script:PromptMode = 'full diff'
            $script:ReasoningEffort = 'low'
            return
        }

        # Use bounded staged-change metadata for large commits.
        $script:Prompt = Get-StagedSummary
        $script:PromptMode = 'bounded summary'
        $script:ReasoningEffort = 'medium'
    }

    function Get-StagedSummary {
        # Define the summary instruction and reserve space for section labels.
        $summaryHeader = @"

Write only a Git commit message for the staged-change summary below.

Use an imperative subject of at most 72 characters. Do not use Conventional
Commit prefixes. Add a body only when useful to explain what changed and why.
Do not include Markdown, commentary, trailers, or questions. Do not claim
details that cannot be inferred from this summary.

Staged-change summary:

"@
        $sectionMaxChars = [Math]::Floor(
            ($SummaryMaxChars - $summaryHeader.Length - 128) / 3
        )

        # Collect read-only Git metadata for the bounded summary.
        $fileStatus = & git -C $RepositoryPath diff `
            --cached `
            --name-status `
            --no-ext-diff `
            --no-color |
            Out-String
        $lineChanges = & git -C $RepositoryPath diff `
            --cached `
            --numstat `
            --no-ext-diff `
            --no-color |
            Out-String
        $diffStat = & git -C $RepositoryPath diff `
            --cached `
            --stat `
            --no-ext-diff `
            --no-color |
            Out-String

        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to retrieve staged Git summary metadata.'
        }

        # Bound each metadata section before assembling the prompt.
        $summarySections = @(
            "File status:`n$(Get-BoundedText -Text $fileStatus -MaximumChars $sectionMaxChars)",
            "Line changes:`n$(Get-BoundedText -Text $lineChanges -MaximumChars $sectionMaxChars)",
            "Diff stat:`n$(Get-BoundedText -Text $diffStat -MaximumChars $sectionMaxChars)"
        )

        return $summaryHeader + ($summarySections -join "`n`n")
    }

    function Get-BoundedText {
        param(
            [string]$Text,
            [int]$MaximumChars
        )

        # Mark metadata omitted when a section exceeds its allowed size.
        $omissionMarker = "`n[Additional entries omitted.]"

        if ($Text.Length -le $MaximumChars) {
            return $Text
        }

        return $Text.Substring(
            0,
            $MaximumChars - $omissionMarker.Length
        ) + $omissionMarker
    }

    function Get-CopilotMessage {
        # Parse structured CLI output while retaining only a redacted diagnostic count.
        $diagnostics = [System.Collections.Generic.List[string]]::new()
        $messages = @(
            & copilot `
                -p $script:Prompt `
                --model $Model `
                --effort $script:ReasoningEffort `
                --no-auto-update `
                --no-ask-user `
                --no-custom-instructions `
                --disable-builtin-mcps `
                --deny-tool=shell `
                --excluded-tools="bash,powershell,list_bash,list_powershell,read_bash,read_powershell,stop_bash,stop_powershell,write_bash,write_powershell" `
                --output-format=json `
                2>&1 |
                ForEach-Object {
                    try {
                        $event = $_ | ConvertFrom-Json

                        if (
                            $event.type -eq 'assistant.message' -and
                            $event.data.content
                        ) {
                            $event.data.content
                        }
                    }
                    catch {
                        [void]$diagnostics.Add('unparseable output')
                    }
                }
        )
        $copilotStatus = $LASTEXITCODE

        if ($copilotStatus -ne 0) {
            [Console]::Error.WriteLine(
                "Copilot CLI exited with status $copilotStatus while using " +
                "$script:PromptMode reasoning."
            )
            exit $copilotStatus
        }

        if ($messages.Count -eq 0) {
            [Console]::Error.WriteLine(
                "Copilot returned no commit message while using $script:PromptMode " +
                "reasoning. Unparseable output events: $($diagnostics.Count)."
            )
            exit 1
        }

        return $messages[-1]
    }
}
#endregion

#region SCRIPT ENTRY POINT
# Run from the script directory while Git commands target the supplied repository.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
#endregion