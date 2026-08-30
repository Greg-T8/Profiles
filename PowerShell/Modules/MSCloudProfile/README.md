# MSCloudProfile

MSCloudProfile manages named Azure CLI, Az PowerShell, Microsoft Graph, and Entra authentication contexts. Named profiles isolate Azure CLI state under `~/.azure/profiles/<name>` and retain Microsoft Graph routing metadata under `~/.mg/profiles/<name>`; credentials remain in the SDK-managed cache.

## Prerequisites

Use PowerShell 7 or later. Install the Azure CLI for Azure profile switching. The Az, Microsoft.Graph, and Microsoft.Entra modules are optional; commands report their unavailable state instead of installing them.

Import the module directly when you are not using this repository's `profile.ps1`:

```powershell
Import-Module ./MSCloudProfile.psd1
Set-MSCloudProfileConfiguration
```

The root profile registers configuration automatically the first time it loads MSCloudProfile.

## Configuration sources

The module reads two optional PowerShell data files:

- Personal: `PersonalConfig.psd1`, for personal and lab profiles.
- Work: `WorkConfig.psd1`, for work and customer profiles.

`Set-MSCloudProfileConfiguration` accepts explicit paths. When a path is omitted, it resolves in this order:

1. `MSCLOUDPROFILE_PERSONAL_CONFIG_PATH` or `MSCLOUDPROFILE_WORK_CONFIG_PATH`.
2. The matching OneDrive environment variable (`OneDriveConsumer` or `OneDriveCommercial`).
3. The documented OneDrive path beneath the user home directory.

```powershell
Set-MSCloudProfileConfiguration `
    -PersonalPath 'C:\Config\PersonalConfig.psd1' `
    -WorkPath 'C:\Config\WorkConfig.psd1'

Get-MSCloudProfileConfiguration
```

The status command returns `Name`, `Path`, `Exists`, `Loaded`, `ProfileCount`, and `Precedence`. Missing files are valid empty sources. A malformed PSD1 file causes registration to fail and leaves the last successfully registered configuration unchanged.

Personal has precedence `1` and Work has precedence `2`; when both define the same profile name, Personal wins. `Get-AllAzProfiles` and `Get-AllMgProfiles` retain the source in their `ConfigSource` property.

## Default views and full detail

The exported `Get-*` commands have compact default tables for interactive use. The full objects and all their properties are still returned to the pipeline:

```powershell
Get-AllAzProfiles | Select-Object *
Get-AllMgProfiles | Format-List *
Get-MSCloudProfileConfiguration | Export-Csv ./configuration.csv -NoTypeInformation
```

Use `Format-Table` or `Format-List` explicitly whenever you need a different display. The module does not serialize profile results with CLIXML.

## Refreshing a renamed subscription

After an Azure subscription is renamed, refresh the active profile with:

```powershell
Update-AzProfileContext
```

The command runs `az account list --refresh`, reloads the subscription through
Az PowerShell, updates the current Az context name, and persists the refreshed
subscription name as the profile description. Use `-WhatIf` to preview the
context and configuration updates.

## PSD1 format

Use one top-level hashtable entry per named profile. The module also supports the legacy `AzureProfiles` wrapper. `TenantId`, `Account`, `PrimarySub` (or `SubscriptionId`), and `Description` are recognized profile fields. `Subs` is optional.

```powershell
@{
    'lab' = @{
        Account     = 'user@contoso.com'
        TenantId    = '00000000-0000-0000-0000-000000000000'
        PrimarySub  = '11111111-1111-1111-1111-111111111111'
        Description = 'Contoso lab tenant'
        Subs        = @{
            'platform' = '11111111-1111-1111-1111-111111111111'
        }
    }
}
```

Keep credentials, tokens, and client secrets out of these files. They contain routing metadata only.

## Common commands

```powershell
Get-MSCloudProfileConfiguration
Get-AllAzProfiles
Get-AllMgProfiles
Use-AzProfile lab
Use-MgProfile lab
Get-CurrentAzProfile
Get-CurrentMgProfile
Use-AzProfileSubscription -SubscriptionID 'platform'
```

Use `New-AzProfile` or `New-MgProfile` to initialize a named profile, and `Remove-AzProfile` or `Remove-MgProfile` to remove it. The `-Save` workflow displays the configuration snippet to add; review and save it yourself.

## Troubleshooting

- Run `Get-MSCloudProfileConfiguration` first when a profile is missing.
- Confirm `Exists` and `Loaded` are `True`; set the relevant environment-path override or register an explicit path if they are not.
- Use `Get-AllAzProfiles` or `Get-AllMgProfiles` to confirm the expected `ConfigSource` and precedence result.
- Correct PSD1 syntax before re-registering. Registration is atomic, so a failed import does not replace the active configuration.
