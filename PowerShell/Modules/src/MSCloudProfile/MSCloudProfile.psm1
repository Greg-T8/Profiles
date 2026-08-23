# -------------------------------------------------------------------------
# Program: MSCloudProfile.psm1
# Description: Load MSCloudProfile public commands and private implementation helpers.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region MODULE LOADER
# Load private dependencies before the exported command implementations.
$privateScripts = @(
    'Private/ProfileConfiguration.ps1'
    'Private/AzModuleContext.ps1'
    'Private/MgProfileStore.ps1'
    'Private/MgModuleContext.ps1'
)

# Load every exported command from its own public script in a fixed order.
$publicScripts = @(
    'Public/Get-AzProfiles.ps1'
    'Public/Get-CurrentAzProfile.ps1'
    'Public/Use-AzProfile.ps1'
    'Public/Use-AzProfileSubscription.ps1'
    'Public/New-AzProfile.ps1'
    'Public/Remove-AzProfile.ps1'
    'Public/Get-MgProfiles.ps1'
    'Public/Get-CurrentMgProfile.ps1'
    'Public/Use-MgProfile.ps1'
    'Public/New-MgProfile.ps1'
    'Public/Remove-MgProfile.ps1'
)

# Dot-source each required module script and stop on an incomplete module payload.
foreach ($relativePath in @($privateScripts + $publicScripts)) {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $relativePath
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "MSCloudProfile module file is missing: $scriptPath"
    }

    . $scriptPath
}
#endregion

#region MODULE EXPORTS
# Export only the documented public commands declared by the module manifest.
Export-ModuleMember -Function @(
    'Get-AzProfiles'
    'Get-CurrentAzProfile'
    'Use-AzProfile'
    'Use-AzProfileSubscription'
    'New-AzProfile'
    'Remove-AzProfile'
    'Get-MgProfiles'
    'Get-CurrentMgProfile'
    'Use-MgProfile'
    'New-MgProfile'
    'Remove-MgProfile'
)
#endregion