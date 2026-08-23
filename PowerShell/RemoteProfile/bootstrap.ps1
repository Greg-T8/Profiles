<#
.SYNOPSIS
Bootstraps the remote PowerShell profile installer from GitHub.

.DESCRIPTION
Downloads and executes the full remote-profile installer from the repository's
RemoteProfile directory.

.CONTEXT
Remote development setup for the personal cross-host PowerShell profile.

.AUTHOR
Greg Tate

.NOTES
Program: bootstrap.ps1
#>

# Download and execute the full installer
$installerUrl = 'https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/RemoteProfile/Install-RemoteProfile.ps1'
$installerScript = Invoke-RestMethod -Uri $installerUrl
Invoke-Expression $installerScript
