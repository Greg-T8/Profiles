---
applyTo: "**/*.ps1"
description: "This file contains the PowerShell scripting standards and guidelines for Copilot."
---

# PowerShell Standards for Copilot

## 1) Modes

### Mode A — Create a new script

* You MAY add code, functions, output, and error handling.
* You MUST follow the Required Script Structure.

### Mode B — Edit an existing script (non-functional changes only)

* You MUST NOT change behavior.
* Allowed changes: comments, whitespace, formatting, line breaks, casing, and expanding aliases.
* You MUST NOT add/remove commands, parameters, logic branches, output, or side effects.

> Default mode: Mode A unless the user explicitly asks for “comment-only”, “format-only”, “no behavior changes”, or similar.

---

## 2) Required Script Structure (Mode A)

All scripts MUST follow this exact order:

1. Comment-based help header (at the very top)
2. `[CmdletBinding()]` then `param()` (even if empty param block is not needed, omit param entirely)
3. Script-level configuration variables (optional)
4. `$Main = { ... }` block (first scriptblock)
5. `$Helpers = { ... }` block (all functions)
6. `try { Push-Location ...; & $Main } finally { Pop-Location }` (at the bottom)

### 2.1 Header template (required)

```powershell
<#
.SYNOPSIS
One-line summary.

.DESCRIPTION
Brief description.

.CONTEXT
Context information (e.g., lab/exam/module).

.AUTHOR
Greg Tate

.NOTES
Program: <script-name>.ps1
#>
```

### 2.2 $Main rules (required)

* `$Main` MUST be the first scriptblock defined in the file.
* The first executable line inside `$Main` MUST be: `. $Helpers`
* `$Main` MUST contain only high-level orchestration calls (no implementation details).
* `$Main` MUST read like an outline (table of contents).

### 2.3 $Helpers rules (required)

* `$Helpers` MUST appear after `$Main`.
* ALL functions MUST be defined inside `$Helpers`.
* Functions MUST be small and single-purpose.
* Functions MUST use approved verbs and singular nouns.

### 2.4 Execution wrapper (required)

```powershell
try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
```

---

## 3) Formatting and Readability

### 3.1 Indentation and braces

* Indent with 4 spaces (no tabs).
* Opening brace on the same line: `if (...) {`
* Closing brace on its own line.

### 3.2 Line breaks

* Prefer pipelines for readability:

  * One pipeline segment per line.
* Use backticks ONLY for long parameter lists when a pipeline is not appropriate.
* Align hashtable keys for readability.

### 3.3 Aliases

* In Mode A and Mode B, expand common aliases:

  * `?` → `Where-Object`
  * `select` → `Select-Object`
  * `%` → `ForEach-Object`
  * `ft` → `Format-Table`
  * `fl` → `Format-List`

### 3.4 Collapsible regions

* Use `#region` and `#endregion` directives to organize major sections of code.
* All major sections SHOULD be wrapped in collapsible regions for better navigation.
* Region names SHOULD be in UPPERCASE for consistency.
* Include a brief comment after the region declaration describing the section's purpose.

Example:

```powershell
#region AZURE CLI PROFILE MANAGEMENT
# Functions for managing multiple Azure CLI contexts across accounts/tenants.
# Uses separate AZURE_CONFIG_DIR per profile to isolate token caches and
# prevent context bleeding between tenants.
# Profiles can be defined in either $Personal.AzureProfiles or $Work.AzureProfiles

function Switch-AzProfile {
    # Implementation
}

function Get-CurrentAzProfile {
    # Implementation
}
#endregion
```

---

## 4) Function Naming

* Use PowerShell approved verbs (Microsoft list).
* Noun MUST be singular.
* Preferred mappings:

  * `Validate` → `Confirm`
  * Display formatting `Format-*` → `Show-*`
  * `Build` → `New-*`

---

## 5) Commenting

### 5.1 Function comment requirement (Mode A)

* Each function MUST start with a one-line comment describing intent (what, not how).

### 5.2 Block comments (Mode A)

* Add a short intent comment above non-trivial blocks:

  * `if/elseif/else`, `switch`, loops, `try/catch/finally`
* Comments describe intent, not mechanics.

### 5.3 Mode B comment rule (non-functional edits only)

* You MAY add comments only if they do not require adding/removing blank lines.
* You MUST NOT insert blank lines solely to justify a comment.

---

## 6) Output rules

* When generating a script, output ONLY the final `.ps1` content.
* Do not include explanations or analysis unless the user asks.

---

## 7) Example skeleton (Mode A)

```powershell
<#
.SYNOPSIS
<one-line summary>

.DESCRIPTION
<brief description>

.CONTEXT
<context>

.AUTHOR
Greg Tate

.NOTES
Program: <script-name>.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RequiredParam,

    [string]$OptionalParam = 'default'
)

# Configuration
$ConfigVar1 = 'value1'

$Main = {
    . $Helpers

    Initialize-Environment
    Get-Data
    Process-Data
    Save-Result
}

$Helpers = {
    function Initialize-Environment {
        # Validate prerequisites and initialize runtime state
    }

    function Get-Data {
        # Retrieve input data required for processing
    }

    function Process-Data {
        # Transform and filter data into the desired output shape
    }

    function Save-Result {
        # Persist or emit the result
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
```
