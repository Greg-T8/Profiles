# -------------------------------------------------------------------------
# Program: Remove-AzProfile.ps1
# Description: Defines the public MSCloudProfile command Remove-AzProfile.
# Context: Personal cross-host PowerShell profile.
# Author: Greg Tate
# -------------------------------------------------------------------------

#region PUBLIC COMMAND
# Defines the public MSCloudProfile command Remove-AzProfile.

function Remove-AzProfile {
    <#
    .SYNOPSIS
        Removes an Azure CLI profile configuration directory.
    .DESCRIPTION
        Removes the Azure CLI config directory for the specified profile and
        optionally removes it from the in-memory configuration.
    .PARAMETER Name
        The profile name to remove.
    .PARAMETER KeepConfig
        Keeps the profile in WorkConfig (only removes the local config dir).
    .EXAMPLE
        Remove-AzProfile -Name 'oldclient'
        Removes the profile's config directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$KeepConfig
    )


    $allConfiguredProfiles = Get-AllAzureProfileConfigs
    $profileConfig = $null
    if ($allConfiguredProfiles.ContainsKey($Name)) {
        $profileConfig = $allConfiguredProfiles[$Name]
    }

    $configDir = Join-Path $HOME ".azure\profiles\$Name"

    # Remove config directory if it exists
    if (Test-Path $configDir) {
        if ($PSCmdlet.ShouldProcess($configDir, "Remove Azure config directory")) {
            Remove-Item -Path $configDir -Recurse -Force
            Write-Host "Removed config directory: $configDir" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Config directory not found: $configDir" -ForegroundColor Yellow
    }

    # Remove matching Az PowerShell module contexts for this profile
    $getAzContextCommand = Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue
    $removeAzContextCommand = Get-Command -Name Remove-AzContext -ErrorAction SilentlyContinue

    if ($getAzContextCommand -and $removeAzContextCommand -and $profileConfig) {
        $configuredPrimarySub = if ($profileConfig.ContainsKey('PrimarySub')) { $profileConfig.PrimarySub } else { $profileConfig.SubscriptionId }
        $matchingContexts = @(Get-AzContext -ListAvailable -ErrorAction SilentlyContinue | Where-Object {
            ($configuredPrimarySub -and $_.Subscription -and $_.Subscription.Id -eq $configuredPrimarySub) -or
            (
                $profileConfig.TenantId -and
                $_.Tenant -and
                $_.Tenant.Id -eq $profileConfig.TenantId -and
                (
                    -not $profileConfig.Account -or
                    ($_.Account -and $_.Account.Id -eq $profileConfig.Account)
                )
            )
        })

        if ($matchingContexts.Count -gt 0) {
            $contextNames = $matchingContexts | Select-Object -ExpandProperty Name -Unique

            foreach ($contextName in $contextNames) {
                if ($PSCmdlet.ShouldProcess($contextName, "Remove Az PowerShell context")) {
                    try {
                        Remove-AzContext -Name $contextName -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
                        Remove-AzContext -Name $contextName -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "Removed Az PowerShell context: $contextName" -ForegroundColor Green
                    }
                    catch {
                        Write-Warning "Could not remove Az PowerShell context '$contextName': $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # Remove from in-memory config unless KeepConfig is specified
    if (-not $KeepConfig.IsPresent) {
        $removed = $false
        $personalProfiles = Get-AzureProfilesFromConfig -Config $global:Personal
        $workProfiles = Get-AzureProfilesFromConfig -Config $global:Work

        if ($personalProfiles.ContainsKey($Name)) {
            if ($global:Personal.ContainsKey('AzureProfiles') -and $global:Personal.AzureProfiles -is [hashtable]) {
                $global:Personal.AzureProfiles.Remove($Name)
            }
            else {
                $global:Personal.Remove($Name)
            }
            Write-Host "Removed profile from Personal in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from PersonalConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if ($workProfiles.ContainsKey($Name)) {
            if ($global:Work.ContainsKey('AzureProfiles') -and $global:Work.AzureProfiles -is [hashtable]) {
                $global:Work.AzureProfiles.Remove($Name)
            }
            else {
                $global:Work.Remove($Name)
            }
            Write-Host "Removed profile from Work in-memory configuration" -ForegroundColor Green
            Write-Host "Note: To remove from WorkConfig.psd1, edit the file manually." -ForegroundColor Yellow
            $removed = $true
        }

        if (-not $removed) {
            Write-Host "Profile '$Name' not found in any in-memory configuration" -ForegroundColor Yellow
        }
    }
}

# Register argument completer for Remove-AzProfile
Register-ArgumentCompleter -CommandName Remove-AzProfile -ParameterName Name -ScriptBlock $azProfileCompleter

#endregion
