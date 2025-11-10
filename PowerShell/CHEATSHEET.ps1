# ┌─────────────────────────────────────────────────────────────┐
# │  PowerShell Profile Remote Install - Cheat Sheet           │
# └─────────────────────────────────────────────────────────────┘

# ═══════════════════════════════════════════════════════════════
#  ONE-LINER (Just copy & paste this)
# ═══════════════════════════════════════════════════════════════

irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex


# ═══════════════════════════════════════════════════════════════
#  Common Scenarios
# ═══════════════════════════════════════════════════════════════

# Remote SSH Session:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex

# Azure Cloud Shell:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex

# New Test VM:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex


# ═══════════════════════════════════════════════════════════════
#  Advanced: Custom Installation
# ═══════════════════════════════════════════════════════════════

# Download installer for custom options:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/Install-RemoteProfile.ps1 -OutFile install.ps1

# Custom path:
.\install.ps1 -InstallPath "C:\CustomPath"

# Without Git:
.\install.ps1 -UseRawDownload

# No activation:
.\install.ps1 -SkipActivation


# ═══════════════════════════════════════════════════════════════
#  Update Existing Installation
# ═══════════════════════════════════════════════════════════════

# Just re-run the one-liner:
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex


# ═══════════════════════════════════════════════════════════════
#  Troubleshooting
# ═══════════════════════════════════════════════════════════════

# Fix execution policy:
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Fix TLS/SSL:
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Test connectivity:
Test-NetConnection raw.githubusercontent.com -Port 443


# ═══════════════════════════════════════════════════════════════
#  What Gets Installed
# ═══════════════════════════════════════════════════════════════

# Location: $HOME\Documents\PowerShell\
#   - profile.ps1 (remote-optimized version)
#   - functions.ps1
#   - prompt.ps1
#   - PSScriptAnalyzerSettings.psd1


# ═══════════════════════════════════════════════════════════════
#  Uninstall
# ═══════════════════════════════════════════════════════════════

Remove-Item "$HOME\Documents\PowerShell" -Recurse -Force
code $PROFILE.CurrentUserAllHosts  # Remove auto-load section


# ═══════════════════════════════════════════════════════════════
#  Repository
# ═══════════════════════════════════════════════════════════════

# https://github.com/Greg-T8/Profiles
