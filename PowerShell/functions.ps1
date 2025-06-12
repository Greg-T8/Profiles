# Converts tab-delimited clipboard data to PowerShell objects (for Excel copy-paste).
function Get-ClipboardExcel {
    Get-Clipboard | ConvertFrom-Csv -Delimiter "`t"
}

# Opens the VS Code PowerShell profile in a new window.
function ep {
    code -n --profile 'PowerShell' $PROFILE.CurrentUserAllHosts
}

# Opens VSCode with a temporary user data directory, or cleans up the temp directory if -Clean is specified.
function tempcode {
    param (
        [switch]$Clean
    )
    $tempDir = "$env:TEMP/tempvscode"
    if (-not $Clean) {
        # Open a new VSCode window with the current directory as the working directory
        & code --user-data-dir=$tempDir --extensions-dir="$tempDir/extensions"
        return
    }
    else {
        # Remove the temp VSCode user data and extensions directories
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
        }
    }
}

# Downloads and outputs the Microsoft license catalog as PowerShell objects.
function GetMicrosoftLicenseCatalog {
    [OutputType([PSCustomObject[]])]
    $url = 'https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference'
    $response = Invoke-WebRequest -Uri $Url
    $csvLink = $response.Links | Select-Object href | Where-Object { $_ -match 'csv' } |
        Select-Object -ExpandProperty href
    $licenseCatalog = Invoke-RestMethod -Uri $csvLink
    $licenseCatalog = $licenseCatalog | ConvertFrom-Csv
    Write-Output $licenseCatalog
}

# Removes Snagit files older than one month from the OneDriveConsumer/Snagit folder.
function CleanUpSnagitFolder {
    $folderPath = "$env:OneDriveConsumer/Snagit"
    $cutoffDate = (Get-Date).AddMonths(-1)
    Get-ChildItem -Path $folderPath -File | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Force
}

# Removes all but the latest version of each installed PowerShell module for the current user.
function RemoveOldModules {
    [OutputType()]
    $psresources = Get-InstalledPSResource -Scope CurrentUser
    $groupedResources = $psresources | Group-Object -Property Name
    foreach ($group in $groupedResources) {
        $latestVersion = $group.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
        $oldVersions = $group.Group | Where-Object { $_.Version -ne $latestVersion.Version }
        foreach ($oldVersion in $oldVersions) {
            Write-Host "Uninstalling $($oldVersion.Name) version $($oldVersion.Version)"
            try {
                Uninstall-PSResource -Name $oldVersion.Name -Version $oldVersion.Version -ProgressAction SilentlyContinue
            }
            catch {
                $err = $_.Exception.Message
                Write-Host "Failed to uninstall $($oldVersion.Name) version $($oldVersion.Version): $err" -ForegroundColor Red
                continue
            }
        }
    }
}

# Creates a file if it doesn't exist, or updates its last modified time if it does (like Unix 'touch').
function touch {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (Test-Path $Path) {
        # Update last modified time
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        # Create the file
        New-Item -ItemType File -Path $Path | Out-Null
    }
}
