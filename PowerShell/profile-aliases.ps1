# ---------------------------------------------------------------------------
# Description   : Configure profile aliases and Git shortcuts.
# Context       : Personal PowerShell profile feature initialization.
# Author        : Greg Tate, with help from a coding agent
# Last Modified : 2026-11-11
# Revision History:
#   2026-11-11 - Use Set-Alias on Windows PowerShell for provider compatibility.
#   2026-11-11 - Extract feature from the PowerShell profile.
# ---------------------------------------------------------------------------

#region ALIASES

# Create profile aliases through the built-in Alias provider rather than Set-Alias.
$script:ProfileAliasWriter = {
    param(
        [Parameter(Mandatory)]
        [string]$ProfileAliasName,

        [Parameter(Mandatory)]
        [string]$ProfileAliasValue,

        [switch]$ProfileAliasForce,

        [System.Management.Automation.ScopedItemOptions]$ProfileAliasOptions = [System.Management.Automation.ScopedItemOptions]::None
    )

    # Use the alias cmdlet on Windows PowerShell, whose provider API differs.
    if ($PSVersionTable.PSEdition -ne 'Core') {
        $profileAliasParameters = @{
            Name  = $ProfileAliasName
            Value = $ProfileAliasValue
            Force = $ProfileAliasForce.IsPresent
        }
        if ($ProfileAliasOptions -ne [System.Management.Automation.ScopedItemOptions]::None) {
            $profileAliasParameters.Option = $ProfileAliasOptions
        }
        Set-Alias @profileAliasParameters
    }
    else {
        # Resolve the alias without loading a command-discovery module.
        $profileAliasProvider = $ExecutionContext.SessionState.InvokeProvider.Item
        $profileAliasPath = "Alias:$ProfileAliasName"
        $profileExistingAlias = if ($profileAliasProvider.Exists($profileAliasPath)) {
            $profileAliasProvider.Get($profileAliasPath)[0]
        }
        else {
            $null
        }

        # Create the alias when it does not already exist in this session.
        if ($null -eq $profileExistingAlias) {
            $profileAliasInfo = $profileAliasProvider.New($profileAliasPath, $null, $null, $ProfileAliasValue)[0]
            $profileExistingOptions = [System.Management.Automation.ScopedItemOptions]::None
        }
        else {
            $profileExistingOptions = $profileExistingAlias.Options
            $null = $profileAliasProvider.Set($profileAliasPath, $ProfileAliasValue, $ProfileAliasForce.IsPresent, $true)
            $profileAliasInfo = $profileAliasProvider.Get($profileAliasPath)[0]
        }

        # Apply a requested option or preserve the existing alias flags.
        if ($ProfileAliasOptions -ne [System.Management.Automation.ScopedItemOptions]::None) {
            $profileAliasInfo.Options = $ProfileAliasOptions
        }
        else {
            $profileAliasInfo.Options = $profileExistingOptions
        }
    }
}
Write-ProfileTime 'After alias helper definition'

# Dot-source the helper so its aliases remain in the profile scope.
Write-ProfileTime ('Before first alias (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
. $script:ProfileAliasWriter -ProfileAliasName ll -ProfileAliasValue Get-ChildItem -ProfileAliasForce
Write-ProfileTime ('After first alias (Utility loaded: {0})' -f [bool](Get-Module -Name Microsoft.PowerShell.Utility))
. $script:ProfileAliasWriter -ProfileAliasName cfj -ProfileAliasValue ConvertFrom-Json
. $script:ProfileAliasWriter -ProfileAliasName gim -ProfileAliasValue Get-InstalledModule
. $script:ProfileAliasWriter -ProfileAliasName rdn -ProfileAliasValue Resolve-DNSName
. $script:ProfileAliasWriter -ProfileAliasName uap -ProfileAliasValue Use-AzProfile
. $script:ProfileAliasWriter -ProfileAliasName ugp -ProfileAliasValue Use-MgProfile
. $script:ProfileAliasWriter -ProfileAliasName gcap -ProfileAliasValue Get-CurrentAzProfile
. $script:ProfileAliasWriter -ProfileAliasName gcgp -ProfileAliasValue Get-CurrentMgProfile
. $script:ProfileAliasWriter -ProfileAliasName uaps -ProfileAliasValue Use-AzProfileSubscription
. $script:ProfileAliasWriter -ProfileAliasName gbs -ProfileAliasValue Get-BillingSubscriptions
. $script:ProfileAliasWriter -ProfileAliasName td -ProfileAliasValue Get-TimeDifference
. $script:ProfileAliasWriter -ProfileAliasName tf -ProfileAliasValue terraform
. $script:ProfileAliasWriter -ProfileAliasName he -ProfileAliasValue herdr
. $script:ProfileAliasWriter -ProfileAliasName nv -ProfileAliasValue nvim -ProfileAliasOptions AllScope -ProfileAliasForce


# Git aliases
# Forward the Git status shortcut to git.exe while preserving optional arguments.
function Invoke-GitStatus {
	git status @args
}
. $script:ProfileAliasWriter -ProfileAliasName gs -ProfileAliasValue Invoke-GitStatus

# Stage the current directory with the Git add shortcut.
function Invoke-GitAdd {
	git add .
}
. $script:ProfileAliasWriter -ProfileAliasName ga -ProfileAliasValue Invoke-GitAdd

# Forward the Git diff shortcut to git.exe while preserving optional arguments.
function Invoke-GitDiff {
	git diff @args
}
. $script:ProfileAliasWriter -ProfileAliasName gd -ProfileAliasValue Invoke-GitDiff

# Forward the Git commit shortcut to git.exe while preserving optional arguments.
function Invoke-GitCommit {
	git commit @args
}
. $script:ProfileAliasWriter -ProfileAliasName gco -ProfileAliasValue Invoke-GitCommit

# Forward the Git push shortcut to git.exe while preserving optional arguments.
function Invoke-GitPush {
	git push @args
}
. $script:ProfileAliasWriter -ProfileAliasName gpu -ProfileAliasValue Invoke-GitPush
. $script:ProfileAliasWriter -ProfileAliasName sgr -ProfileAliasValue Set-GitRepoRoot
. $script:ProfileAliasWriter -ProfileAliasName ghel -ProfileAliasValue Show-GhFailedRunLog

# Azure DevOps aliases
. $script:ProfileAliasWriter -ProfileAliasName adel -ProfileAliasValue Show-AdoFailedRunLog

# Docker aliases
. $script:ProfileAliasWriter -ProfileAliasName dex -ProfileAliasValue DockerExec
. $script:ProfileAliasWriter -ProfileAliasName dil -ProfileAliasValue DockerImageList
. $script:ProfileAliasWriter -ProfileAliasName dcl -ProfileAliasValue DockerContainerList
. $script:ProfileAliasWriter -ProfileAliasName regctl -ProfileAliasValue RegCtlCmd
Write-ProfileTime 'After aliases and Git shortcut functions'
#endregion
