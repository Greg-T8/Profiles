# PowerShell Profile Remote Installation

This directory contains scripts to quickly install your PowerShell profile customizations on remote systems or new development environments.

## Quick Start

### One-Liner Installation (Fastest)

Run this single command in any PowerShell session:

```powershell
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

This will:
- Download the full installer script
- Install all profile files to `$HOME\Documents\PowerShell`
- Configure your profile to auto-load on startup
- Activate the profile in your current session

### Manual Installation

If you prefer to download and review the script first:

```powershell
# Download the installer
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/Install-RemoteProfile.ps1' -OutFile 'Install-RemoteProfile.ps1'

# Review the script (optional but recommended)
code Install-RemoteProfile.ps1

# Run the installer
.\Install-RemoteProfile.ps1
```

## Installation Options

The `Install-RemoteProfile.ps1` script supports several parameters:

### Use Direct Download (No Git Required)

```powershell
.\Install-RemoteProfile.ps1 -UseRawDownload
```

Useful when Git is not installed on the remote system.

### Custom Installation Path

```powershell
.\Install-RemoteProfile.ps1 -InstallPath "C:\CustomPath\PowerShell"
```

### Install Without Activation

```powershell
.\Install-RemoteProfile.ps1 -SkipActivation
```

Installs files but doesn't load them into the current session.

### Install from Different Branch

```powershell
.\Install-RemoteProfile.ps1 -Branch "dev"
```

## What Gets Installed

The installer copies these files to your system:

- `profile.ps1` - Main profile configuration
- `functions.ps1` - Custom PowerShell functions
- `prompt.ps1` - Custom prompt with git integration
- `PSScriptAnalyzerSettings.psd1` - PSScriptAnalyzer configuration

## File Locations

After installation:

- **Profile files**: `$HOME\Documents\PowerShell\`
- **PowerShell profile**: `$PROFILE.CurrentUserAllHosts`
- **Git repository** (if cloned): `$HOME\Documents\PowerShell\.repo\`

## Updating Your Profile

### With Git Installed

If the profile was installed using git clone, simply run:

```powershell
.\Install-RemoteProfile.ps1
```

The script will detect the existing repository and pull the latest changes.

### Without Git

Re-run the installer with `-UseRawDownload`:

```powershell
.\Install-RemoteProfile.ps1 -UseRawDownload
```

This will re-download all files from GitHub.

## Remote Development Scenarios

### VS Code Remote - SSH

```powershell
# Connect to remote system via SSH
# In the remote terminal:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Azure Cloud Shell

```powershell
# In Cloud Shell:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Docker Container

```dockerfile
# In your Dockerfile:
RUN pwsh -Command "irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex"
```

### Windows Sandbox

```powershell
# Inside Windows Sandbox:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

## Troubleshooting

### Security Policy Errors

If you encounter execution policy restrictions:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### TLS/SSL Errors

If you get certificate errors:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Can't Download Files

Ensure you have internet access and that GitHub is not blocked:

```powershell
Test-NetConnection -ComputerName raw.githubusercontent.com -Port 443
```

## Uninstallation

To remove the profile customizations:

1. Delete the installation directory:
   ```powershell
   Remove-Item -Path "$HOME\Documents\PowerShell" -Recurse -Force
   ```

2. Edit your PowerShell profile to remove the auto-generated section:
   ```powershell
   code $PROFILE.CurrentUserAllHosts
   ```

## Notes

- The installer is idempotent - you can run it multiple times safely
- Existing profile customizations are preserved
- The script requires PowerShell 5.1 or later (PowerShell Core 7+ recommended)
- No administrator privileges required

## Links

- **GitHub Repository**: https://github.com/Greg-T8/Profiles
- **Issues**: https://github.com/Greg-T8/Profiles/issues
