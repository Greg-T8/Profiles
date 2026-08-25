# -------------------------------------------------------------------------
# Program: MSCloudProfile.psd1
# Description: Defines the public contract for Microsoft cloud profile management.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

@{
    RootModule        = 'MSCloudProfile.psm1'
    FormatsToProcess  = @('MSCloudProfile.format.ps1xml')
    ModuleVersion     = '1.0.0'
    GUID              = '57ec2cb8-a0a7-4988-b73c-59d9c138132a'
    Author            = 'Greg Tate'
    Description       = 'Manages isolated Azure CLI, Az, Microsoft Graph, and Entra profiles.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @(
        'Use-AzProfile'
        'Use-MgProfile'
        'Get-CurrentAzProfile'
        'Get-CurrentMgProfile'
        'Get-AllAzProfiles'
        'Get-AllMgProfiles'
        'Set-MSCloudProfileConfiguration'
        'Get-MSCloudProfileConfiguration'
        'New-AzProfile'
        'New-MgProfile'
        'Remove-AzProfile'
        'Remove-MgProfile'
        'Use-AzProfileSubscription'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Azure', 'MicrosoftGraph', 'Entra', 'Profile')
        }
    }
}
