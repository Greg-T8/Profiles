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

& $Main
```

## Notes on general structure

* The `$Main` block always comes first before the `$Helpers` block.
