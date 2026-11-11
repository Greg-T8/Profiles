# ---------------------------------------------------------------------------
# Description   : Load cloud profile configuration and deferred commands.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Separate Utility module and personal data-file timings.
#   2026-11-11 - Add timings around personal configuration file loading.
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

# Resolve profile-owned configuration paths for profile configuration loading.
Write-ProfileTime 'Before personal configuration path resolution'
$personalConfigPath = if ($env:MSCLOUDPROFILE_PERSONAL_CONFIG_PATH) {
	Write-ProfileTime 'Personal path source: environment override'
	$env:MSCLOUDPROFILE_PERSONAL_CONFIG_PATH
}
elseif ($env:OneDriveConsumer) {
	Write-ProfileTime ('Before personal path composition using OneDriveConsumer (Management loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Management))
	[System.IO.Path]::Combine([string[]]@($env:OneDriveConsumer, 'Apps', 'PowerShell', 'PersonalConfig.psd1'))
}
else {
	Write-ProfileTime ('Before personal path composition using HOME fallback (Management loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Management))
	[System.IO.Path]::Combine([string[]]@($HOME, 'OneDrive', 'Apps', 'PowerShell', 'PersonalConfig.psd1'))
}
Write-ProfileTime ('After personal configuration path (Management loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Management))

# Check whether the personal configuration file is available.
Write-ProfileTime 'Before personal configuration file existence check'
$personalConfigExists = [System.IO.File]::Exists($personalConfigPath)
Write-ProfileTime ('After personal configuration file existence check (exists: {0})' -f $personalConfigExists)

# Load personal configuration into the global profile variable when available.
if ($personalConfigExists) {
    if ($env:PROFILE_TIMING) {
        Write-ProfileTime ('Before personal data-file import (Utility loaded: {0}; Management loaded: {1})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility), [bool](Get-Module -Name Microsoft.PowerShell.Management))

        # Separate the Utility module's first load from data-file processing.
        if (-not (Get-Module -Name Microsoft.PowerShell.Utility)) {
            Write-ProfileTime 'Before Utility module import for personal configuration'
            Import-Module -Name Microsoft.PowerShell.Utility -ErrorAction Stop
            Write-ProfileTime 'After Utility module import for personal configuration'
        }
        Write-ProfileTime 'Before personal data-file processing'
    }
    $Personal = $Per = Import-PowerShellDataFile -Path $personalConfigPath
    if ($env:PROFILE_TIMING) {
        Write-ProfileTime ('After personal data-file import (Utility loaded: {0}; Management loaded: {1})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility), [bool](Get-Module -Name Microsoft.PowerShell.Management))
    }
}
else {
    Write-ProfileTime 'Skipped personal data-file import (file not found)'
}
Write-ProfileTime 'After personal configuration import'

$workConfigPath = if ($env:MSCLOUDPROFILE_WORK_CONFIG_PATH) {
	$env:MSCLOUDPROFILE_WORK_CONFIG_PATH
}
elseif ($env:OneDriveCommercial) {
	[System.IO.Path]::Combine([string[]]@($env:OneDriveCommercial, 'Code', 'PowerShell', 'Config', 'WorkConfig.psd1'))
}
else {
	[System.IO.Path]::Combine([string[]]@($HOME, 'OneDrive - Quisitive', 'Code', 'PowerShell', 'Config', 'WorkConfig.psd1'))
}
Write-ProfileTime 'After work configuration path'

# Load work configuration into the global profile variable when available.
if ([System.IO.File]::Exists($workConfigPath)) {
	$Work = Import-PowerShellDataFile -Path $workConfigPath
}
Write-ProfileTime 'After work configuration import'

Write-ProfileTime 'After profile configuration'

# Define immediate-use profile commands while deferring the complete MSCloudProfile module import.
if ($PSVersionTable.PSEdition -eq 'Core') {
	#region DEFERRED CLOUD PROFILE COMMANDS
	# Expose profile switching and discovery commands without importing the full module at startup.
	function Import-MSCloudProfile {
		# Load the complete module the first time a profile-switching command is invoked.
		if (Get-Module -Name MSCloudProfile) {
			return
		}

		$msCloudProfileManifest = "$profileDir/Modules/MSCloudProfile/MSCloudProfile.psd1"
		if (-not [System.IO.File]::Exists($msCloudProfileManifest)) {
			throw "MSCloudProfile module manifest was not found: $msCloudProfileManifest"
		}

		Import-Module -Name $msCloudProfileManifest -Global -ErrorAction Stop
		& MSCloudProfile\Set-MSCloudProfileConfiguration -PersonalPath $personalConfigPath -WorkPath $workConfigPath | Out-Null
	}

	function Use-AzProfile {
		# Import and invoke the Azure profile-switching command on first use.
		[CmdletBinding()]
		param(
			[Parameter(Mandatory, Position = 0)]
			[string]$Name,

			[Parameter()]
			[switch]$Force,

			[Parameter()]
			[switch]$SelectAccount
		)

		Import-MSCloudProfile
		& MSCloudProfile\Use-AzProfile @PSBoundParameters
	}

	function Get-AllAzProfiles {
		# Import and invoke Azure profile discovery on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-AllAzProfiles @PSBoundParameters
	}

	function Get-CurrentAzProfile {
		# Import and invoke Azure current-profile inspection on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-CurrentAzProfile @PSBoundParameters
	}

	function Use-MgProfile {
		# Import and invoke the Microsoft Graph profile-switching command on first use.
		[CmdletBinding()]
		param(
			[Parameter(Mandatory, Position = 0)]
			[string]$Name,

			[Parameter()]
			[string[]]$Scopes,

			[Parameter()]
			[string]$ClientId,

			[Parameter()]
			[string]$LoginHint,

			[Parameter()]
			[switch]$NoWelcome,

			[Parameter()]
			[switch]$Force
		)

		Import-MSCloudProfile
		& MSCloudProfile\Use-MgProfile @PSBoundParameters
	}

	function Get-AllMgProfiles {
		# Import and invoke Microsoft Graph profile discovery on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-AllMgProfiles @PSBoundParameters
	}

	function Get-CurrentMgProfile {
		# Import and invoke Microsoft Graph current-profile inspection on first use.
		[CmdletBinding()]
		param()

		Import-MSCloudProfile
		& MSCloudProfile\Get-CurrentMgProfile @PSBoundParameters
	}
	#endregion

}
