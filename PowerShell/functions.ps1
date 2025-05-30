function Get-ClipboardExcel {
    Get-Clipboard | ConvertFrom-Csv -Delimiter "`t"
}

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