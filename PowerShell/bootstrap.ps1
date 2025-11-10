# Quick one-liner to bootstrap PowerShell profile from GitHub
# Usage: irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex

# Download and execute the full installer
$installerUrl = 'https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/Install-RemoteProfile.ps1'
$installerScript = Invoke-RestMethod -Uri $installerUrl
Invoke-Expression $installerScript
