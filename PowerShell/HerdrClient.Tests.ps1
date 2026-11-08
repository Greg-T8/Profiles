<#
.SYNOPSIS
Validates the Herdr client integration in a disposable named session.

.DESCRIPTION
Checks empty-session protection, restored sessions, recursion prevention,
trusted project paths, and the deferred prompt without touching production.

.CONTEXT
Personal Windows PowerShell profile integration with Herdr.

.AUTHOR
Greg Tate

.NOTES
Program: HerdrClient.Tests.ps1
#>

[CmdletBinding()]
param([switch]$UnitOnly)

# Use a unique test session and preserve the caller's environment.
$TestSession = 'profile-v3-' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
$TestRoot = Join-Path $env:TEMP ('herdr-v3-' + [Guid]::NewGuid().ToString('N'))
$ModulePath = Join-Path $PSScriptRoot 'HerdrClient.psm1'
$OldSession = $env:HERDR_SESSION
$OldSocket = $env:HERDR_SOCKET_PATH
$OldHerdr = $env:HERDR_ENV
$OldUserProfile = $env:USERPROFILE

# Run the isolated lifecycle and trusted-path checks.
$Main = {
    . $Helpers
    if ($UnitOnly) {
        Confirm-VSCodeLocationCommand
        return
    }
    Initialize-TestEnvironment
    Confirm-EmptySession
    Confirm-RestoredSession
    Confirm-VSCodeLocationCommand
    Confirm-ProjectProfile
    Confirm-ManagedProfile
    Confirm-AlzProfile
    Confirm-SnapshotFailure
    Confirm-DeferredPrompt
    Write-Host 'All isolated Herdr client checks passed.'
}

# Define independent assertions and test scenarios.
$Helpers = {
    function Assert-Condition {
        # Stop immediately when an expected condition is not satisfied.
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw $Message }
        Write-Host "PASS: $Message"
    }

    function Initialize-TestEnvironment {
        # Isolate the CLI session from the user's existing Herdr server.
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        $env:HERDR_SESSION = $TestSession
        Remove-Item Env:HERDR_SOCKET_PATH, Env:HERDR_ENV -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force

        # Confirm that automation switches are excluded from autostart.
        Assert-Condition (-not (Test-HerdrAutostartEligibility)) 'Noninteractive PowerShell is ineligible'
        Assert-Condition ((Test-HerdrCommandArgument -Arguments @('-Comm', 'Get-Item')) -and
            (Test-HerdrCommandArgument -Arguments @('-Enco', 'payload')) -and
            -not (Test-HerdrCommandArgument -Arguments @('-ExecutionPolicy', 'RemoteSigned')) -and
            (Test-HerdrNonInteractiveArgument -Arguments @('-NonInt'))) 'Abbreviated automation switches are detected'
    }

    function Confirm-EmptySession {
        # Prove that diagnostics and headless startup do not create workspaces.
        $initial = Get-HerdrWorkspaceCount
        Assert-Condition ($initial.Status -eq 'Stopped') 'New test session starts stopped'

        # Confirm that preview mode does not start the test server.
        $preview = Start-HerdrClient -NoAttach -WhatIf
        $afterPreview = Get-HerdrWorkspaceCount
        Assert-Condition ($preview.Status -eq 'Stopped' -and $afterPreview.Status -eq 'Stopped') 'WhatIf leaves server stopped'

        # Check that starting an empty server does not create a workspace.
        $empty = Start-HerdrClient -NoAttach
        $snapshot = Get-HerdrWorkspaceCount
        Assert-Condition ($empty.Status -eq 'Ready' -and $empty.Count -eq 0 -and $snapshot.Count -eq 0) 'Headless empty session creates no workspace'
    }

    function Confirm-RestoredSession {
        # Populate only the disposable session and verify its saved workspace restores.
        $created = & herdr.exe --session $TestSession workspace create --cwd $TestRoot --label 'Manual test' --no-focus
        Assert-Condition ($LASTEXITCODE -eq 0) 'Created one workspace manually in the disposable session'
        $id = ($created | ConvertFrom-Json -AsHashtable).result.workspace.workspace_id
        $ready = Start-HerdrClient -NoAttach
        Assert-Condition ($ready.Count -eq 1) 'Detected an existing workspace without attaching'

        # Ensure managed panes cannot recursively invoke the client.
        $env:HERDR_ENV = '1'
        $nested = Start-HerdrClient -NoAttach
        Assert-Condition ($null -eq $nested) 'Managed panes cannot recursively attach'
        Remove-Item Env:HERDR_ENV

        # Restart only the disposable server and verify its saved workspace.
        & herdr.exe --session $TestSession server stop | Out-Null
        Assert-Condition ($LASTEXITCODE -eq 0) 'Stopped only the disposable test server'
        $restored = Start-HerdrClient -NoAttach
        $snapshot = & herdr.exe --session $TestSession api snapshot | ConvertFrom-Json -AsHashtable
        Assert-Condition ($restored.Count -eq 1 -and $snapshot.result.snapshot.workspaces[0].workspace_id -eq $id) 'Restored the saved workspace before attachment'
    }

    function Confirm-VSCodeLocationCommand {
        # Verify that a quoted directory remains a single literal PowerShell path.
        $directory = Join-Path $TestRoot "VS Code's workspace"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Import-Module $ModulePath -Force
        $module = Get-Module HerdrClient
        $command = & $module { param($path) Get-HerdrLocationCommand -Directory $path } $directory

        # Execute only the constructed command in this disposable test process.
        Push-Location
        try {
            & ([scriptblock]::Create($command))
            Assert-Condition ((Get-Location).ProviderPath -eq $directory) 'VS Code location command preserves spaces and apostrophes'
        }
        finally { Pop-Location }
    }

    function Confirm-ProjectProfile {
        # Allow only the configured project root and its directory descendants.
        $env:USERPROFILE = $TestRoot
        $root = Join-Path $TestRoot 'LocalCode/Lab/ALZ'
        $child = Join-Path $root 'Nested'
        $sibling = Join-Path $TestRoot 'LocalCode/Lab/ALZ-Old'
        New-Item -ItemType Directory -Path $child, $sibling, (Join-Path $root '.assets') -Force | Out-Null
        $loader = Join-Path $root '.assets/LoadWorkspaceProfile.ps1'
        [IO.File]::WriteAllText($loader, '# Trusted test initializer')

        # Compare a trusted descendant with a similarly named sibling directory.
        $env:HERDR_ENV = '1'
        Push-Location $child
        try { $selected = Get-HerdrTrustedProjectProfile }
        finally { Pop-Location }
        Push-Location $sibling
        try { $other = Get-HerdrTrustedProjectProfile }
        finally { Pop-Location }
        Assert-Condition ($selected -eq $loader -and $null -eq $other) 'Trusted initializer respects directory boundaries'

        # Restore the user profile environment for subsequent checks.
        $env:USERPROFILE = $OldUserProfile
        Remove-Item Env:HERDR_ENV
    }

    function Confirm-DeferredPrompt {
        # Confirm the actual prompt hook attaches once and retains the original prompt.
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'profile.ps1'), [ref]$tokens, [ref]$errors)
        $hook = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'global:prompt' }, $true)
        Assert-Condition ($null -ne $hook -and $errors.Count -eq 0) 'Parsed the deferred prompt hook'

        # Substitute local test functions and invoke the hook twice.
        try {
            $global:HerdrOriginalPrompt = { 'original prompt' }
            $global:HerdrAttachPending = $true
            $global:HerdrTestCount = 0
            function global:Test-HerdrAutostartEligibility { return $true }
            function global:Start-HerdrClient { $global:HerdrTestCount++ }
            $scriptBlock = $hook.Body.GetScriptBlock()
            $first = $scriptBlock.Invoke()
            $second = $scriptBlock.Invoke()
            Assert-Condition ($global:HerdrTestCount -eq 1 -and $first -eq 'original prompt' -and $second -eq 'original prompt') 'Deferred hook attaches once and preserves the prompt'
        }

        # Remove the test functions and temporary global variables.
        finally {
            Remove-Item Function:\global:Start-HerdrClient, Function:\global:Test-HerdrAutostartEligibility -ErrorAction SilentlyContinue
            Remove-Variable -Name HerdrOriginalPrompt, HerdrAttachPending, HerdrTestCount -Scope Global -ErrorAction SilentlyContinue
        }
    }

    function Confirm-ManagedProfile {
        # Start a new managed pane under a temporary trusted root and observe its initialization.
        $root = Join-Path $TestRoot 'LocalCode/Lab/ALZ'
        $sentinel = Join-Path $TestRoot 'managed-profile.txt'
        $escapedSentinel = $sentinel.Replace("'", "''")
        $loader = Join-Path $root '.assets/LoadWorkspaceProfile.ps1'
        [IO.File]::WriteAllText($loader, "[IO.File]::AppendAllText('$escapedSentinel', 'loaded`n')")

        # Start a managed pane and wait for its trusted initializer.
        $result = & herdr.exe --session $TestSession workspace create --cwd $root --label 'Trusted loader test' --env "USERPROFILE=$TestRoot" --no-focus
        Assert-Condition ($LASTEXITCODE -eq 0) 'Created an isolated managed pane for the trusted initializer'
        $workspace = $result | ConvertFrom-Json -AsHashtable
        for ($attempt = 0; $attempt -lt 100 -and -not (Test-Path -LiteralPath $sentinel); $attempt++) {
            Start-Sleep -Milliseconds 200
        }
        Assert-Condition (Test-Path -LiteralPath $sentinel) 'New managed PowerShell pane loaded the trusted initializer'

        # Verify that a new tab inherits its directory and initializes once.
        $tabResult = & herdr.exe --session $TestSession tab create --workspace $workspace.result.workspace.workspace_id --env "USERPROFILE=$TestRoot" --no-focus
        $tab = $tabResult | ConvertFrom-Json -AsHashtable
        Assert-Condition ($LASTEXITCODE -eq 0 -and $tab.result.root_pane.cwd.TrimEnd('\') -eq $root.TrimEnd('\')) 'New tab follows the workspace directory'
        for ($attempt = 0; $attempt -lt 100 -and @(Get-Content -LiteralPath $sentinel).Count -lt 2; $attempt++) {
            Start-Sleep -Milliseconds 200
        }
        Assert-Condition (@(Get-Content -LiteralPath $sentinel).Count -eq 2) 'New tab initializes once'

        # Verify that a split follows its source pane and also initializes once.
        $splitResult = & herdr.exe --session $TestSession pane split --pane $tab.result.root_pane.pane_id --direction right --env "USERPROFILE=$TestRoot" --no-focus
        $split = $splitResult | ConvertFrom-Json -AsHashtable
        Assert-Condition ($LASTEXITCODE -eq 0 -and $split.result.pane.cwd.TrimEnd('\') -eq $root.TrimEnd('\')) 'New split follows the source pane directory'
        for ($attempt = 0; $attempt -lt 100 -and @(Get-Content -LiteralPath $sentinel).Count -lt 3; $attempt++) {
            Start-Sleep -Milliseconds 200
        }
        Assert-Condition (@(Get-Content -LiteralPath $sentinel).Count -eq 3) 'New tab and split each initialize once'
    }

    function Confirm-AlzProfile {
        # Exercise the ALZ terminal command without attaching a client or contacting Azure.
        $path = 'C:\Users\gregt\LocalCode\Lab\ALZ\ALZ.code-workspace'
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host 'SKIP: ALZ workspace is unavailable.'
            return
        }

        # Confirm the dedicated terminal remains disabled by default.
        $workspace = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        $profile = $workspace.settings.'terminal.integrated.profiles.windows'.'PowerShell ALZ'
        Assert-Condition ($profile.env.HERDR_AUTOSTART -eq '0' -and $profile.env.HERDR_ALZ_ENABLE -eq '0' -and
            $profile.args[0] -eq '-NoExit') 'ALZ integration remains disabled and preserves NoExit'

        # Preserve the terminal environment before testing both branches.
        $oldTerm = $env:TERM_PROGRAM
        $oldFlag = $env:HERDR_ALZ_ENABLE
        $oldLoader = $env:HERDR_ALZ_LOADER

        # Exercise the disabled initializer and enabled client call separately.
        try {
            $env:TERM_PROGRAM = 'herdr-test'
            $env:HERDR_ALZ_ENABLE = '0'
            $env:HERDR_ALZ_LOADER = Join-Path $TestRoot 'alz-loader.ps1'
            [IO.File]::WriteAllText($env:HERDR_ALZ_LOADER, '$global:HerdrAlzTestLoaded = $true')
            & ([scriptblock]::Create($profile.args[2]))
            Assert-Condition $global:HerdrAlzTestLoaded 'Disabled ALZ branch preserves existing initialization'

            # Substitute a client function before checking the enabled branch.
            $global:HerdrAlzTestLoaded = $false
            $global:HerdrAlzClientCalled = $false
            function Start-HerdrClient {
                param([switch]$Explicit)
                $global:HerdrAlzClientCalled = $Explicit.IsPresent
            }
            $env:HERDR_ALZ_ENABLE = '1'
            & ([scriptblock]::Create($profile.args[2]))
            Assert-Condition ($global:HerdrAlzClientCalled -and -not $global:HerdrAlzTestLoaded) 'Enabled ALZ branch calls the client without outer initialization'
        }

        # Restore the terminal environment and clear the test markers.
        finally {
            $env:TERM_PROGRAM = $oldTerm
            $env:HERDR_ALZ_ENABLE = $oldFlag
            $env:HERDR_ALZ_LOADER = $oldLoader
            Remove-Variable -Name HerdrAlzTestLoaded, HerdrAlzClientCalled -Scope Global -ErrorAction SilentlyContinue
        }
    }

    function Confirm-SnapshotFailure {
        # Verify that an unreadable snapshot cannot reach the attachment path.
        $module = Get-Module HerdrClient
        & $module { function script:Get-HerdrWorkspaceCount { throw 'Invalid test snapshot' } }

        # Confirm the launcher warns and returns without attaching.
        try {
            $warnings = @()
            $state = Start-HerdrClient -NoAttach -WarningAction SilentlyContinue -WarningVariable warnings
            Assert-Condition ($null -eq $state -and $warnings.Count -gt 0) 'Invalid snapshot fails open with a warning'
        }

        # Restore the original module implementation after the simulated failure.
        finally { Import-Module $ModulePath -Force }
    }
}

try {
    Push-Location -Path $PSScriptRoot
    & $Main
}
finally {
    # Stop only this invocation's disposable server and restore the environment.
    if (-not $UnitOnly -and $env:HERDR_SESSION -eq $TestSession) { & herdr.exe --session $TestSession server stop 2>$null | Out-Null }
    $env:HERDR_SESSION = $OldSession
    $env:HERDR_SOCKET_PATH = $OldSocket
    $env:HERDR_ENV = $OldHerdr
    $env:USERPROFILE = $OldUserProfile
    Pop-Location
}
