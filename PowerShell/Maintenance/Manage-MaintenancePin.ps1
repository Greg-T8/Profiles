<#+
.SYNOPSIS
Manages exact-version PowerShell module and WinGet package maintenance pins.

.DESCRIPTION
Installs and pins a requested PowerShell module or WinGet package version,
records the pin in a per-user state file, and removes the pin on request.
Scheduled maintenance consumes the state file to avoid updating pinned modules.

.CONTEXT
User login maintenance automation (Windows Task Scheduler)

.AUTHOR
Greg Tate

.NOTES
Program: Manage-MaintenancePin.ps1
#>

[CmdletBinding(DefaultParameterSetName = 'Show')]
param(
    [Parameter(Mandatory, ParameterSetName = 'PinModule')]
    [switch]$PinModule,

    [Parameter(Mandatory, ParameterSetName = 'PinModule')]
    [Parameter(Mandatory, ParameterSetName = 'UnpinModule')]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Mandatory, ParameterSetName = 'PinModule')]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleVersion,

    [Parameter(Mandatory, ParameterSetName = 'UnpinModule')]
    [switch]$UnpinModule,

    [Parameter(Mandatory, ParameterSetName = 'PinPackage')]
    [switch]$PinPackage,

    [Parameter(Mandatory, ParameterSetName = 'PinPackage')]
    [Parameter(Mandatory, ParameterSetName = 'UnpinPackage')]
    [ValidateNotNullOrEmpty()]
    [string]$PackageId,

    [Parameter(Mandatory, ParameterSetName = 'PinPackage')]
    [ValidateNotNullOrEmpty()]
    [string]$PackageVersion,

    [Parameter(ParameterSetName = 'PinPackage')]
    [ValidateNotNullOrEmpty()]
    [string]$PackageSource = 'winget',

    [Parameter(ParameterSetName = 'PinPackage')]
    [switch]$SkipPackageInstall,

    [Parameter(Mandatory, ParameterSetName = 'UnpinPackage')]
    [switch]$UnpinPackage
)

$PinStatePath = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GregTate\MaintenancePins\pins.json'
$RequestedOperation = $PSCmdlet.ParameterSetName
$SkipRequestedPackageInstall = $SkipPackageInstall.IsPresent

$Main = {
    . $Helpers

    switch ($RequestedOperation) {
        'PinModule' {
            Set-MaintenanceModulePin -Name $ModuleName -Version $ModuleVersion
            break
        }
        'UnpinModule' {
            Remove-MaintenanceModulePin -Name $ModuleName
            break
        }
        'PinPackage' {
            Set-MaintenancePackagePin `
                -Id $PackageId `
                -Version $PackageVersion `
                -Source $PackageSource `
                -SkipInstall:$SkipRequestedPackageInstall
            break
        }
        'UnpinPackage' {
            Remove-MaintenancePackagePin -Id $PackageId
            break
        }
        default {
            Show-MaintenancePin
        }
    }
}

$Helpers = {
    function Get-MaintenancePinState {
        # Return an empty state when no maintenance pin has been recorded.
        if (-not (Test-Path -LiteralPath $PinStatePath -PathType Leaf)) {
            return [pscustomobject]@{
                ModulePins  = @()
                PackagePins = @()
            }
        }

        $state = Get-Content -LiteralPath $PinStatePath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $state.PSObject.Properties['ModulePins']) {
            $state | Add-Member -MemberType NoteProperty -Name ModulePins -Value @()
        }
        if ($null -eq $state.PSObject.Properties['PackagePins']) {
            $state | Add-Member -MemberType NoteProperty -Name PackagePins -Value @()
        }

        return $state
    }

    function Save-MaintenancePinState {
        param(
            [Parameter(Mandatory)]
            [pscustomobject]$State
        )

        # Create the per-user state directory before serializing the pin catalog.
        $stateDirectory = Split-Path -Path $PinStatePath -Parent
        if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
            New-Item -Path $stateDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        [pscustomobject]@{
            ModulePins  = @($State.ModulePins)
            PackagePins = @($State.PackagePins)
            UpdatedAtUtc = [datetime]::UtcNow.ToString('o')
        } |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $PinStatePath -Encoding UTF8 -ErrorAction Stop
    }

    function Set-MaintenanceModulePin {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Version
        )

        $requiredVersion = [version]$Version
        $installedRequiredModule = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue |
            Where-Object { $_.Version -eq $requiredVersion } |
            Select-Object -First 1

        # Install the required version in the same CurrentUser scope maintained by the scheduled task.
        if (-not $installedRequiredModule) {
            Install-Module `
                -Name $Name `
                -RequiredVersion $Version `
                -Scope CurrentUser `
                -Force `
                -AllowClobber `
                -ErrorAction Stop
        }

        $userModuleRoots = @(
            (Join-Path -Path $HOME -ChildPath 'Documents\PowerShell\Modules'),
            (Join-Path -Path $HOME -ChildPath 'Documents\WindowsPowerShell\Modules')
        )
        $otherModulePaths = foreach ($userModuleRoot in $userModuleRoots) {
            $moduleRoot = Join-Path -Path $userModuleRoot -ChildPath $Name
            Get-ChildItem -LiteralPath $moduleRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne $Version } |
                Sort-Object -Property Name -Descending
        }

        # Remove alternate CurrentUser versions so implicit imports select the requested release.
        foreach ($modulePath in $otherModulePaths) {
            try {
                Uninstall-Module `
                    -Name $Name `
                    -RequiredVersion $modulePath.Name `
                    -Force `
                    -ErrorAction Stop
            }
            catch {
                # PowerShellGet does not register every CurrentUser module version for uninstallation.
            }

            # Fall back to the verified CurrentUser module directory when it remains after PowerShellGet.
            if (Test-Path -LiteralPath $modulePath.FullName -PathType Container) {
                Remove-Item -LiteralPath $modulePath.FullName -Recurse -Force -ErrorAction Stop
            }
        }

        $state = Get-MaintenancePinState
        $state.ModulePins = @($state.ModulePins | Where-Object { $_.Name -ne $Name }) + @(
            [pscustomobject]@{
                Name    = $Name
                Version = $Version
            }
        )
        Save-MaintenancePinState -State $state
        Write-Host "Pinned PowerShell module $Name at $Version." -ForegroundColor Green
    }

    function Remove-MaintenanceModulePin {
        param(
            [Parameter(Mandatory)]
            [string]$Name
        )

        # Remove the maintenance exclusion without uninstalling the currently selected module version.
        $state = Get-MaintenancePinState
        $state.ModulePins = @($state.ModulePins | Where-Object { $_.Name -ne $Name })
        Save-MaintenancePinState -State $state
        Write-Host "Removed PowerShell module pin for $Name." -ForegroundColor Yellow
    }

    function Set-MaintenancePackagePin {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Version,

            [Parameter(Mandatory)]
            [string]$Source,

            [switch]$SkipInstall
        )

        # Install the exact requested package release before creating its native WinGet pin.
        $winget = Get-Command -Name 'winget.exe' -ErrorAction Stop
        if (-not $SkipInstall) {
            $installArguments = @(
                'install'
                '--id'
                $Id
                '--version'
                $Version
                '--exact'
                '--source'
                $Source
                '--force'
                '--accept-package-agreements'
                '--accept-source-agreements'
                '--disable-interactivity'
            )
            & $winget.Source @installArguments
            if ($LASTEXITCODE -ne 0) {
                throw "WinGet installation for $Id $Version failed with exit code $LASTEXITCODE."
            }
        }

        # Replace an existing native package pin with the requested exact version.
        & $winget.Source pin remove --id $Id --exact --disable-interactivity 2>$null
        $pinArguments = @(
            'pin'
            'add'
            '--id'
            $Id
            '--version'
            $Version
            '--exact'
            '--source'
            $Source
            '--accept-source-agreements'
            '--disable-interactivity'
            '--force'
        )
        & $winget.Source @pinArguments
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet pin creation for $Id $Version failed with exit code $LASTEXITCODE."
        }

        $state = Get-MaintenancePinState
        $state.PackagePins = @($state.PackagePins | Where-Object { $_.Id -ne $Id }) + @(
            [pscustomobject]@{
                Id      = $Id
                Version = $Version
                Source  = $Source
            }
        )
        Save-MaintenancePinState -State $state
        Write-Host "Pinned WinGet package $Id at $Version." -ForegroundColor Green
    }

    function Remove-MaintenancePackagePin {
        param(
            [Parameter(Mandatory)]
            [string]$Id
        )

        # Remove the native pin and its local maintenance catalog entry.
        $winget = Get-Command -Name 'winget.exe' -ErrorAction Stop
        & $winget.Source pin remove --id $Id --exact --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet pin removal for $Id failed with exit code $LASTEXITCODE."
        }

        $state = Get-MaintenancePinState
        $state.PackagePins = @($state.PackagePins | Where-Object { $_.Id -ne $Id })
        Save-MaintenancePinState -State $state
        Write-Host "Removed WinGet package pin for $Id." -ForegroundColor Yellow
    }

    function Show-MaintenancePin {
        # Display the durable pin catalog without changing installed software.
        $state = Get-MaintenancePinState
        [pscustomobject]@{
            ModulePins  = @($state.ModulePins)
            PackagePins = @($state.PackagePins)
        }
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    Pop-Location
}
