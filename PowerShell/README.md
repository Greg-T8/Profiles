# PowerShell Profile for Remote Development

A lightweight, portable PowerShell profile optimized for remote development environments. Quickly bootstrap your customized PowerShell experience on any system with a single command.

## ✨ Features

- **🎨 Custom Prompt**: Elegant prompt with git integration (via Posh-Git when available)
- **⌨️ Vi Mode**: Full Vi keybindings with visual mode indicators
- **📝 PSReadLine**: Enhanced editing with predictive IntelliSense
- **🛠️ Useful Functions**: Collection of productivity-enhancing PowerShell functions
- **🚀 Fast Loading**: Optimized for quick startup times
- **🌐 Cross-Platform**: Works on Windows, Linux, and macOS (PowerShell 7+)
- **📦 No Dependencies**: Falls back gracefully when optional modules aren't available
- **🔒 Portable**: No OneDrive or system-specific paths required

## 🚀 Quick Install

Run this single command in any PowerShell session:

```powershell
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

**What it does:**
- ✅ Downloads all profile files from GitHub
- ✅ Installs to `$HOME\Documents\PowerShell`
- ✅ Configures auto-loading on PowerShell startup
- ✅ Activates immediately in current session

## 📋 Remote Development Scenarios

### VS Code Remote - SSH

```powershell
# After connecting to remote host:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Azure Cloud Shell

```powershell
# In Cloud Shell:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Dev Container / Codespace

Add to your `.devcontainer/devcontainer.json`:

```json
{
  "postCreateCommand": "pwsh -Command 'irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex'"
}
```

Or in a Dockerfile:

```dockerfile
RUN pwsh -Command "irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex"
```

### Windows Sandbox / Test VM

```powershell
# First-time setup in new environment:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

## 📦 What Gets Installed

The installer copies these files to your system:

| File | Description |
|------|-------------|
| `profile.ps1` | Main profile configuration (remote-optimized, no OneDrive dependencies) |
| `functions.ps1` | Custom PowerShell functions for productivity |
| `prompt.ps1` | Custom prompt with git integration and path shortening |
| `PSScriptAnalyzerSettings.psd1` | Code analysis settings |

**Installation Location:** `$HOME\Documents\PowerShell\`

### Profile Features

**Vi Mode Keybindings:**
- Visual mode indicators (cursor shape changes)
- `Ctrl+p` / `Ctrl+n` - Navigate history
- `Alt+b` / `Alt+f` - Word navigation
- `Ctrl+a` / `Ctrl+e` - Line navigation
- `Ctrl+k` / `Ctrl+u` - Kill line operations

**Aliases:**
- `ll` → `Get-ChildItem`
- `cfj` → `ConvertFrom-Json`
- `tf` → `terraform`
- `gim` → `Get-InstalledModule`

**Custom Functions Include:**
- `Get-ClipboardExcel` - Convert Excel clipboard data to objects
- `touch` - Create/update file timestamps (Unix-style)
- `Update-AllInstalledModules` - Update all PowerShell modules
- `Remove-OldModuleVersions` - Clean up old module versions
- `Measure-ProfileLoad` - Analyze profile loading performance
- And many more! (See `functions.ps1` for full list)

## ⚙️ Advanced Installation Options

For more control, download the installer manually:

```powershell
# Download installer
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/Install-RemoteProfile.ps1 -OutFile install.ps1

# Custom install path:
.\install.ps1 -InstallPath "C:\CustomPath"

# Without Git (direct download):
.\install.ps1 -UseRawDownload

# Install without activating in current session:
.\install.ps1 -SkipActivation

# Install from different branch:
.\install.ps1 -Branch "dev"
```



## 🔄 Updating Your Profile

Simply re-run the installer:

```powershell
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

The installer will:
- Detect existing installation
- Pull latest changes (if using Git) or re-download files
- Preserve your profile configuration

## 🔧 Troubleshooting

### Execution Policy Errors

If you see "scripts is disabled on this system":

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then reload your profile:

```powershell
. $PROFILE
```

### TLS/SSL Certificate Errors

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Connection Issues

Verify GitHub connectivity:

```powershell
Test-NetConnection raw.githubusercontent.com -Port 443
```

### Profile Not Loading Automatically

The installer modifies `$PROFILE.CurrentUserAllHosts` to auto-load your profile. If it's not working:

1. Check if the profile exists: `Test-Path $PROFILE.CurrentUserAllHosts`
2. View the profile: `Get-Content $PROFILE.CurrentUserAllHosts`
3. Verify the dot-source paths are correct

## 🗑️ Uninstallation

```powershell
# Remove installation directory
Remove-Item "$HOME\Documents\PowerShell" -Recurse -Force

# Edit your profile to remove auto-load section
code $PROFILE.CurrentUserAllHosts
```

## 💡 Tips & Best Practices

- **Idempotent**: Safe to run installer multiple times
- **No Admin Required**: Installs to user directory
- **Git Optional**: Automatically falls back to direct downloads
- **Lightweight**: Optimized for fast startup (~50-200ms overhead)
- **Portable**: Works across Windows, Linux, and macOS
- **Customizable**: Modify installed files in `$HOME\Documents\PowerShell`

## 📚 Additional Resources

- **Repository**: [github.com/Greg-T8/Profiles](https://github.com/Greg-T8/Profiles)
- **Issues**: [Report bugs or request features](https://github.com/Greg-T8/Profiles/issues)
- **Profile Optimization**: [Microsoft Docs](https://devblogs.microsoft.com/powershell/optimizing-your-profile/)

## 🤝 Contributing

Feel free to fork this repository and customize it for your needs. Pull requests welcome!

## 📄 License

This project is provided as-is for personal and educational use.
