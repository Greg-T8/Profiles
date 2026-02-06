---
applyTo: "**/*.ps1"
description: "This file contains the PowerShell scripting standards and guidelines for Copilot."
---

# Generating a PowerShell Script with Proper Style

Refactor the PowerShell script so that it adheres to the following style guidelines:

## Formatting PowerShell Commands for Revision

When providing a PowerShell command that is longer than one line, follow these guidelines to ensure proper style and readability:

### Line Breaking Guidelines

1. **Break long one-liners across multiple lines** to improve readability
2. **Prioritize using the pipeline (`|`) for line breaks** - place each pipeline segment on its own line
3. **Use the backtick (`` ` ``) character for line continuation** when breaking lines that don't naturally break at a pipeline or comma
4. **Indent continuation lines** to show logical grouping and hierarchy
5. **Expand aliases to full cmdlet names** for clarity (e.g., `Where-Object` instead of `?`, `Select-Object` instead of `select`)
6. **Use consistent casing** - PascalCase for cmdlets and parameters

### Formatting Examples

#### Example 1: Pipeline with Hashtable

**Before:**
```powershell
get-AzPolicyDefinition | ? displayname -match 'Configure virtual machines to be onboarded' | select displayname, @{n='Effect';e={$_.PolicyRule.then.effect}}
```

**After:**
```powershell
Get-AzPolicyDefinition |
    Where-Object DisplayName -match 'Configure virtual machines to be onboarded' |
    Select-Object DisplayName, @{
        Name       = 'Effect'
        Expression = { $_.PolicyRule.then.effect }
    }
```

#### Example 2: Complex Hashtable

**Before:**
```powershell
New-AzResourceGroupDeployment -ResourceGroupName "rg-prod" -TemplateFile .\template.json -TemplateParameterObject @{location='eastus';vmSize='Standard_D2s_v3';adminUsername='azureuser'}
```

**After:**
```powershell
New-AzResourceGroupDeployment `
    -ResourceGroupName "rg-prod" `
    -TemplateFile .\template.json `
    -TemplateParameterObject @{
        location      = 'eastus'
        vmSize        = 'Standard_D2s_v3'
        adminUsername = 'azureuser'
    }
```

#### Example 3: Long Parameter List

**Before:**
```powershell
New-AzVM -ResourceGroupName "myRG" -Name "myVM" -Location "eastus" -ImageName "Win2019Datacenter" -Size "Standard_D2s_v3" -Credential $cred -VirtualNetworkName "myVnet" -SubnetName "mySubnet"
```

**After:**
```powershell
New-AzVM `
    -ResourceGroupName "myRG" `
    -Name "myVM" `
    -Location "eastus" `
    -ImageName "Win2019Datacenter" `
    -Size "Standard_D2s_v3" `
    -Credential $cred `
    -VirtualNetworkName "myVnet" `
    -SubnetName "mySubnet"
```

### Key Improvements to Apply

- **Expand common aliases:**
  - `?` → `Where-Object`
  - `select` → `Select-Object`
  - `%` → `ForEach-Object`
  - `ft` → `Format-Table`
  - `fl` → `Format-List`

- **Align hashtable properties** for visual clarity
- **Use meaningful indentation** (typically 4 spaces)
- **Keep related parameters together** when breaking lines
- **Place opening braces on the same line** and closing braces on their own line



## General Program Structure

```pwsh
$Main = {
	# Main function block that includes a small number of high-level commands.
	# Each command should be a call to a function defined elsewhere in the script.
	# Intention is for the reader to quickly understand what the script does in this block.

	# Dot-source the helper functions
	. $Helpers

	Get-Data
	Process-Data
	Save-Results
}

$Helpers = {
	# Helper functions that perform specific tasks.
	# Each function should be small and focused on a single task.

	function Get-Data {
		# Function to retrieve data from a source.
		# Implementation details go here.
	}

	function Process-Data {
		# Function to process the retrieved data.
		# Implementation details go here.
	}

	function Save-Results {
		# Function to save the processed results to a destination.
		# Implementation details go here.
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

### Notes on general structure

* The `$Main` block always comes first before the `$Helpers` block.

## Other requirements

* Use PowerShell-approved verbs in function names, namely verbs from this list: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5
* In function names, keep the noun part singular (e.g., use `Get-Item` instead of `Get-Items`).
	* When in doubt, use the following mapping:
		* Validate -> Confirm
	* When displaying output, use the verb `Show` instead of `Format`
