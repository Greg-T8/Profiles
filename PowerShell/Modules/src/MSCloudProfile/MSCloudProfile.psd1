# -------------------------------------------------------------------------
# Program: MSCloudProfile.psd1
# Description: Defines the public contract for Microsoft cloud profile management.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

@{
    RootModule        = 'MSCloudProfile.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '57ec2cb8-a0a7-4988-b73c-59d9c138132a'
    Author            = 'Greg Tate'
    Description       = 'Manages isolated Azure CLI, Az, Microsoft Graph, and Entra profiles.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Azure', 'MicrosoftGraph', 'Entra', 'Profile')
        }
    }
}
