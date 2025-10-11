Refactor the PowerShell script so that it adheres to the following style guidelines:

# General Program Structure

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

## Notes on general structure

* The `$Main` block always comes first before the `$Helpers` block.

# Other requirements

* Use PowerShell-approved verbs in function names, namely verbs from this list: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands?view=powershell-7.5
* In function names, keep the noun part singular (e.g., use `Get-Item` instead of `Get-Items`).
	* When in doubt, use the following mapping:
		* Validate -> Confirm
	* When displaying output, use the verb `Show` instead of `Format`
