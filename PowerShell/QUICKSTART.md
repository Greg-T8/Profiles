# PowerShell Profile Quick Reference Card

## 🚀 One-Liner Install (Copy & Paste This!)

```powershell
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

---

## 📋 Common Remote Dev Scenarios

### VS Code Remote SSH
```powershell
# After connecting to remote host:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Azure Cloud Shell
```powershell
# In Cloud Shell terminal:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Dev Container / Codespace
```dockerfile
# Add to Dockerfile or initialization script:
RUN pwsh -Command "irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex"
```

### Windows Sandbox / Test VM
```powershell
# First time setup in new environment:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

---

## 🛠️ Advanced Options

### Install with Options
```powershell
# Download installer first for custom options:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/Install-RemoteProfile.ps1 -OutFile install.ps1

# Custom install path:
.\install.ps1 -InstallPath "C:\MyProfiles"

# Without Git (direct download):
.\install.ps1 -UseRawDownload

# Install without activation:
.\install.ps1 -SkipActivation

# Different branch:
.\install.ps1 -Branch "dev"
```

---

## 🔄 Update Profile

```powershell
# Re-run the one-liner:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

---

## 🗑️ Uninstall

```powershell
# Remove installation directory:
Remove-Item "$HOME\Documents\PowerShell" -Recurse -Force

# Edit profile to remove auto-load:
code $PROFILE.CurrentUserAllHosts
```

---

## 🔍 Troubleshooting

### Execution Policy Issue
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### TLS/SSL Certificate Error
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

### Check Connectivity
```powershell
Test-NetConnection raw.githubusercontent.com -Port 443
```

---

## 📁 What Gets Installed

- ✅ `profile.ps1` - Main profile (remote-optimized version)
- ✅ `functions.ps1` - Custom PowerShell functions
- ✅ `prompt.ps1` - Custom prompt with git integration  
- ✅ `PSScriptAnalyzerSettings.psd1` - Code analysis settings

**Location:** `$HOME\Documents\PowerShell\`

---

## 💡 Tips

- **Bookmark this page** for quick access during remote sessions
- The installer is **idempotent** - safe to run multiple times
- Works on **Windows, Linux, and macOS** (PowerShell 7+)
- **No admin rights required**
- Git is **optional** (falls back to direct downloads)

---

## 🔗 Links

- 📦 **Repository**: https://github.com/Greg-T8/Profiles
- 📖 **Full Docs**: [README.md](./README.md)
- 🐛 **Report Issue**: https://github.com/Greg-T8/Profiles/issues

---

## ⚡ Pro Tip

Add this to your workspace settings for automatic setup in new containers:

```json
{
  "terminal.integrated.profiles.linux": {
    "pwsh": {
      "path": "pwsh",
      "args": [
        "-NoExit",
        "-Command",
        "irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex"
      ]
    }
  }
}
```
