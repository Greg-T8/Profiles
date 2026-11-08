# Herdr PowerShell client

The profile integration attaches to the current Herdr session only after its live snapshot reports at least one workspace. It does not create, select, rename, or close workspaces. If the server is stopped, the helper starts it headlessly and checks the restored snapshot. Empty or unreadable sessions leave PowerShell available.

General automatic startup is **enabled**. Set `$script:HerdrIntegrationEnabled` near the top of [profile.ps1](./profile.ps1) to `$false` to disable the profile's Herdr module import, automatic attachment, and managed-pane project initialization for new shells. The ALZ terminal profile retains `HERDR_ALZ_ENABLE=0` and continues to run its existing outer initializer until its dedicated startup path is validated. The previous project-to-workspace registry is not used.

When an eligible VS Code terminal attaches, the integration sends a PowerShell `Set-Location -LiteralPath` command to the currently focused Herdr pane using the VS Code terminal's initial directory, which is normally its workspace folder. It does not create a pane or select a different workspace. This input affects the shared pane and can interfere with a running program or partially typed command; Herdr accepting the input does not prove PowerShell executed it. Windows Terminal attaches without changing the pane's directory. If VS Code starts its terminal in another directory, that directory is used.

On November 7, 2026, the automated checks passed in an ordinary Windows user context, including empty-session protection, saved-session restoration, and initialization in new managed panes, tabs, and splits. A read-only snapshot of the existing Herdr 0.9.5 session also succeeded and reported one workspace. The user confirmed attachment to the disposable validation workspace from Windows Terminal and an isolated VS Code window. Detachment and the dedicated ALZ terminal remain to be confirmed.

After general startup was enabled, two subsequent isolated runs timed out waiting for managed-pane initialization: one at the first pane and another at a new tab. The server lifecycle and trusted-path checks passed in both runs. The cause of the timeouts has not been established.

## Validate in a disposable session

Run the automated checks from this repository with `pwsh -NoProfile -File ./PowerShell/HerdrClient.Tests.ps1`. They start and stop only a uniquely named test server; temporary test files and stopped test sessions remain for inspection.

Run the location-command check without controlling Herdr using `pwsh -NoProfile -File ./PowerShell/HerdrClient.Tests.ps1 -UnitOnly`.

For interactive checks, use a separate session name beginning with `profile-v3-`. In a PowerShell console, set process-level variables and initialize the test server:

```powershell
$env:HERDR_SESSION = 'profile-v3-manual'
Import-Module "$env:USERPROFILE\OneDrive\Apps\Profiles\PowerShell\HerdrClient.psm1"
Start-HerdrClient -NoAttach
```

Confirm the empty session returns a count of zero. If an old test session with that name already has workspaces, choose a new name. Create a workspace yourself in that test session, then start a new PowerShell 7 process from Windows Terminal with the session variable inherited. Confirm attachment and detach back to the original prompt. Use a separately started VS Code instance that inherits the same variable to check its normal PowerShell terminal and shell integration.

To validate ALZ, use an ALZ test workspace rooted at the approved ALZ directory, temporarily set `HERDR_ALZ_ENABLE` to `1` in its existing terminal profile, and open a new terminal in the isolated VS Code instance. Choose the ALZ workspace manually in Herdr, then create a new pane and check that its Azure profile initialization is available. Restore the flag to `0` if the check fails. No settings in Herdr need to change.

Check that tasks, debug terminals, `HERDR_AUTOSTART=0`, and the existing **PowerShell (No Profile)** terminal remain ordinary PowerShell sessions. Do not stop the default Herdr server during testing.

## ALZ activation and recovery

1. After validation, set `HERDR_ALZ_ENABLE` to `1` in the existing ALZ workspace terminal profile. That profile keeps `HERDR_AUTOSTART=0` so its shell integration completes before its explicit client call.
2. Remove the process-level `HERDR_SESSION` test variable, then open new terminals. `HERDR_AUTOSTART=0` disables the general automatic attachment; `pwsh -NoProfile` bypasses the profile entirely.

The ALZ workspace file is outside this repository and must be updated separately. Enable its flag only after the dedicated terminal and inner-pane checks pass.

The ALZ allowlist is explicit: only a managed shell starting in `USERPROFILE\LocalCode\Lab\ALZ` or one of its descendants loads that root's `.assets\LoadWorkspaceProfile.ps1`. Other projects and sibling directories do not load it. Existing panes do not reload their profiles automatically.

## Diagnostics and rollback

`Get-HerdrWorkspaceCount` inspects the current live session. `Start-HerdrClient -NoAttach` starts a stopped server headlessly if needed and reports the count without attaching. `Start-HerdrClient -NoAttach -WhatIf` performs a read-only snapshot check without starting a server.

If access is denied, use a Windows session with the appropriate access; the helper does not change server security settings. If a trusted initializer is missing or fails, the shell remains available and reports a warning. To roll back, set `$script:HerdrIntegrationEnabled` to `$false` in [profile.ps1](./profile.ps1) and leave the ALZ flag at `0`, or restore the profile and ALZ configuration backups created before the change. Do not stop the existing server or close its workspaces as part of rollback.

The snapshot check and the subsequent interactive attach are separate Herdr operations. If another client closes the last workspace between those operations, the launcher cannot make the check and attachment atomic with the available CLI.

Herdr 0.9.5's [client startup](https://github.com/herdrdev/herdr/blob/v0.9.5/src/server/autodetect.rs) passes its working directory to a server it starts, and the [server bootstrap](https://github.com/herdrdev/herdr/blob/v0.9.5/src/server/headless/bootstrap.rs) creates a workspace from that directory if no workspace was restored. In particular, the server could stop between the snapshot and client launch, allowing the client to start another server. The current launcher therefore cannot guarantee the plan's no-automatic-creation requirement under that race.
