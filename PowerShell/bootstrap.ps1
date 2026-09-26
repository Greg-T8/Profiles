<#
.SYNOPSIS
Bootstraps the PowerShell profile installer from its current repository location.

.DESCRIPTION
Keeps the original PowerShell/bootstrap.ps1 URL working after the installer
scripts moved into the RemoteProfile directory.

.CONTEXT
Remote development setup for the personal cross-host PowerShell profile.

.AUTHOR
Greg Tate

.NOTES
Program: bootstrap.ps1
#>

[CmdletBinding()]
param()

# Keep the legacy URL pointed at the current installer.
$InstallerUrl = 'https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/RemoteProfile/Install-RemoteProfile.ps1'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# Orchestrate downloading and running the current installer.
$Main = {
    . $Helpers

    Invoke-RemoteProfileInstaller -Uri $InstallerUrl
}

# Define the helper that retrieves and runs the installer script.
$Helpers = {
    function Invoke-RemoteProfileInstaller {
        # Download and execute the current profile installer.
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        $installerScript = Invoke-RestMethod -Uri $Uri
        Invoke-Expression $installerScript
    }
}

try {
    Push-Location -Path $ScriptRoot
    & $Main
}
finally {
    Pop-Location
}
