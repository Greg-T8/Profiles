<#
    This is my PowerShell profile script I use in the context of $Profile.CurrentUserAllHosts.

    The prompt function mimmics the behavior of the Oh-My-Posh prompt for PowerShell, but without requiring the
    additional overhead and loading time of Oh-My-Posh.

    The profile script does the following:
    - Configures VI mode for PSReadline
    - Sets the prompt to display the current directory in a shortened format
    - Enables Posh-Git when using VSCode or when in a git repository
    - Imports a configuration file for work-related settings

    See the following link for optimizing your PowerShell profile:
    - https://devblogs.microsoft.com/powershell/optimizing-your-profile/
#>

if ($PSVersionTable.PSEdition -eq 'Core') {
    $PSStyle.Formatting.Verbose = $PSStyle.Foreground.Cyan
    $PSStyle.Formatting.Warning = $PSStyle.Foreground.Yellow

    # Enable PSReadline prediction
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
}

if (Test-Path -Path "$env:OneDriveConsumer/Apps/Profiles/PowerShell/prompt.ps1") {
    . "$env:OneDriveConsumer/Apps/Profiles/PowerShell/prompt.ps1"
}

if (Test-Path -Path "$env:OneDriveConsumer/Apps/Profiles/PowerShell/functions.ps1") {
    . "$env:OneDriveConsumer/Apps/Profiles/PowerShell/functions.ps1"
}

if (Test-Path -Path $env:OneDriveCommercial/Code/PowerShell/WorkConfig.psd1) {
    $Work = Import-PowerShellDataFile -Path $env:OneDriveCommercial/Code/PowerShell/WorkConfig.psd1

    $orderedAccounts = [ordered]@{}
    foreach ($key in $Work.Accounts.Keys | Sort-Object) {
        $orderedAccounts[$key] = $Work.Accounts[$key]
    }
    $Work.Accounts = $orderedAccounts

    $orderedTenantIds = [ordered]@{}
    foreach ($key in $Work.TenantIds.Keys | Sort-Object) {
        $orderedTenantIds[$key] = $Work.TenantIds[$key]
    }
    $Work.TenantIds = $orderedTenantIds

    $orderedSubscriptionIds = [ordered]@{}
    foreach ($key in $Work.SubscritpionIds.Keys | Sort-Object) {
        $orderedSubscriptionIds[$key] = $Work.SubscritpionIds[$key]
    }
    $Work.SubscritpionIds = $orderedSubscriptionIds
}

# Aliases
Set-Alias -Name ll -Value Get-ChildItem -Force
Set-Alias -name cfj -Value ConvertFrom-Json
Set-Alias -Name tf -Value terraform
Set-Alias -Name gim -Value Get-InstalledModule
Remove-Item Alias:dir

# Enable keyboard shortcuts
if (-not (Get-Module PSReadline)) { Import-Module PSReadLine }
Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
Set-PSReadLineKeyHandler -Chord Tab -Function TabCompleteNext
Set-PSReadLineKeyHandler -Chord Shift+Tab -Function TabCompletePrevious
Set-PSReadLineKeyHandler -Chord Ctrl+V -Function Paste
if ((Get-PSReadLineOption).EditMode -eq 'Vi') {
    Set-PSReadLineOption -ViModeIndicator 'Cursor'
    $env:EDITOR = 'nvim'
    foreach ($mode in 'Command', 'Insert') {
        Set-PSReadLineKeyHandler -Chord Ctrl+p -Function PreviousHistory -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+n -Function NextHistory -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Alt+b -Function BackwardWord -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Alt+f -Function ForwardWord -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+e -Function EndOfLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+a -Function BeginningOfLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+k -Function KillLine -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+u -Function BackwardKillInput -ViMode $mode
        Set-PSReadLineKeyHandler -Chord Ctrl+w -Function BackwardKillWord -ViMode $mode
    }
    function OnViModeChange {
        if ($args[0] -eq 'Command') {
            # Set the cursor to a blinking block.
            Write-Host -NoNewline "`e[1 q"
        }
        else {
            # Set the cursor to a blinking line.
            Write-Host -NoNewline "`e[5 q"
        }
    }
    Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $Function:OnViModeChange
}