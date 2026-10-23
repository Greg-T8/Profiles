<#
.SYNOPSIS
Generates a Git commit message from staged changes with an AI API.

.DESCRIPTION
Uses the complete staged diff for small commits and a bounded metadata summary
for large commits. The script emits only the generated commit message to
standard output.

.CONTEXT
Personal Git workflow - bounded API commit-message generation.

.AUTHOR
Greg Tate

.NOTES
Program: Get-AICommitMessage.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryPath,

    [string]$Model = $env:AI_COMMIT_MODEL,

    [string]$BaseUrl = $env:AI_COMMIT_BASE_URL,

    [string]$ApiKey = $env:AI_COMMIT_API_KEY
)

#region CONFIGURATION
# Limits that preserve the direct fast path and bound the summary fallback.
$DirectPromptMaxChars = 24000
$SummaryMaxChars = 16000
#endregion

#region MAIN WORKFLOW
# Orchestrates staged-change collection, prompt selection, and API output.
$Main = {
    . $Helpers

    Confirm-ApiConfiguration
    Get-StagedDiff
    New-CommitPrompt
    Get-AIMessage
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
        # Use the complete diff when it remains within the configured disclosure and usage budget.
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
            return
        }

        # Use bounded staged-change metadata for large commits.
        $script:Prompt = Get-StagedSummary
        $script:PromptMode = 'bounded summary'
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

    function Confirm-ApiConfiguration {
        # Require explicit model selection before reading staged content.
        if ([string]::IsNullOrWhiteSpace($Model)) {
            throw 'Set AI_COMMIT_MODEL to a model ID supported by your provider.'
        }

        # Keep credentials outside the tracked hook files.
        if ([string]::IsNullOrWhiteSpace($ApiKey)) {
            throw 'Set AI_COMMIT_API_KEY outside the repository before generating a message.'
        }

        # Default to OpenRouter while allowing compatible hosted providers.
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
            $script:BaseUrl = 'https://openrouter.ai/api/v1'
        }

        # Require HTTPS and reject credentials or query strings in the endpoint.
        $baseUri = $null
        if (
            -not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$baseUri) -or
            $baseUri.Scheme -ne 'https' -or
            $baseUri.UserInfo -or $baseUri.Query -or $baseUri.Fragment
        ) {
            throw 'AI_COMMIT_BASE_URL must be an HTTPS base URL without credentials, a query, or a fragment.'
        }

        # Append the Chat Completions route to the configured base URL.
        $script:CompletionUri = $BaseUrl.TrimEnd('/') + '/chat/completions'
    }

    function Get-AIMessage {
        # Serialize a minimal compatible request without provider-specific reasoning options.
        $requestBody = @{
            model    = $Model
            stream   = $false
            messages = @(
                @{
                    role    = 'user'
                    content = $script:Prompt
                }
            )
        } | ConvertTo-Json -Depth 5 -Compress

        # Bound the wait and disable retries so a commit makes only one API attempt.
        $request = @{
            Uri                = $script:CompletionUri
            Method             = 'Post'
            Headers            = @{ Authorization = "Bearer $ApiKey" }
            ContentType        = 'application/json; charset=utf-8'
            Body               = [Text.Encoding]::UTF8.GetBytes($requestBody)
            TimeoutSec         = 60
            MaximumRetryCount  = 0
            MaximumRedirection = 0
            ErrorAction        = 'Stop'
        }

        # Bound response I/O separately on PowerShell versions that expose an operation timeout.
        if ('OperationTimeoutSeconds' -in (Get-Command Invoke-RestMethod).Parameters.Keys) {
            $request.OperationTimeoutSeconds = 60
        }

        # Replace HTTP exception details with diagnostics that cannot expose response bodies.
        try {
            $response = Invoke-RestMethod @request
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode

            # Report only the status code when the service supplied one.
            if ($null -ne $statusCode) {
                throw "AI API request failed (HTTP $([int]$statusCode))."
            }

            throw 'AI API request failed or timed out; no commit message was written.'
        }

        # Reject missing, non-text, or blank message content before the hook writes anything.
        $choices = @($response.choices)
        $message = $null
        if ($choices.Count -gt 0) {
            $message = $choices[0].message.content
        }
        if ($message -isnot [string] -or [string]::IsNullOrWhiteSpace($message)) {
            throw 'AI API returned no usable commit message.'
        }

        return $message.Trim()
    }
}
#endregion

#region SCRIPT ENTRY POINT
# Run from the script directory while Git commands target the supplied repository.
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
catch {
    # Emit concise errors after HTTP details have been sanitized.
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
finally {
    Pop-Location
}
#endregion
