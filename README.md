# Profiles

A collection of configuration files and profiles for various development tools and environments.

## ⚡ Quick Bootstrap

### PowerShell Profile

```powershell
# One-liner to install PowerShell profile from GitHub
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/RemoteProfile/bootstrap.ps1 | iex
```

### Linux Profile

The setup is intended for APT-based distributions such as Debian and Ubuntu,
including remote VMs and containers. Run it as the user whose profile you want
to configure; it uses `sudo` for package installation when needed.

```bash
# Set up the current user's Linux profile from GitHub
curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-linux.sh | bash
```

For a minimal APT-based system without curl, install it first:

```bash
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-linux.sh | bash
```

## 🚀 Manual Setup

For manual configuration or customization, use the following setup instructions.

### Linux Configurations

#### Remote Linux Quick Setup

The `init-linux.sh` script provides automated setup for remote Linux systems:

```bash
# Clone repository first
git clone https://github.com/Greg-T8/Profiles.git ~/profiles
cd ~/profiles/Linux

# Make executable and run
chmod +x init-linux.sh
./init-linux.sh
```

**What it does:**

- Installs curl, wget, vim, less, procps, and fzf
- Downloads .bashrc, .vimrc, and .inputrc, backing up existing files
- Configures vi mode and custom prompt
- Supports apt-get, yum, zypper, and apk; the package list is geared toward APT

#### Vim

```bash
# Create symlink to .vimrc
ln -s ~/path/to/Profiles/Linux/.vimrc ~/.vimrc
```

**Features:**

- Vi mode with cursor shape changes
- Line numbers (absolute + relative)
- Color column at 80 characters
- Desert color scheme
- Custom leader key mappings (Space)
- No line wrapping with line break indicators

#### ZSH

```bash
# Create symlink to .zshrc
ln -s ~/path/to/Profiles/Linux/.zshrc ~/.zshrc
source ~/.zshrc
```

**Features:**

- Vi mode keybindings with visual cursor feedback
- History substring search (PowerShell-like `#` + Tab)
- Git branch integration in prompt
- Custom two-line prompt with box-drawing characters
- Enhanced tab completion
- Command history search with Up/Down arrows

**Optional Plugin:**

```bash
# Install history substring search for enhanced functionality
git clone https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/zsh-history-substring-search
```

### Neovim

```bash
# Create symlink to Neovim config
ln -s ~/path/to/Profiles/Neovim ~/.config/nvim
```

**Features:**

- Lazy.nvim plugin manager
- Separate configurations for Neovim and VSCode Neovim
- Lualine status bar
- Neo-tree file explorer
- Vim-move for moving lines/blocks

### PowerShell

#### Automated Installation

The `Install-RemoteProfile.ps1` script provides automated setup:

```powershell
# Clone repository first
git clone https://github.com/Greg-T8/Profiles.git "$env:OneDrive\Apps\Profiles"
cd "$env:OneDrive\Apps\Profiles\PowerShell"

# Run installer
.\RemoteProfile\Install-RemoteProfile.ps1
```

Or use the bootstrap one-liner (see Quick Bootstrap section above).

**What it does:**

- Installs a PowerShell profile entry point and its feature scripts
- Sets up profile directory structure
- Configures PSReadLine with Vi mode
- Installs custom prompt with Git integration

#### Manual Setup

```powershell
# Create symlink to PowerShell profile
New-Item -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target "C:\path\to\Profiles\PowerShell\Profile\profile.ps1"
```

**Features:**

- Custom two-line prompt with Git integration (Posh-Git)
- Vi mode with cursor shape changes
- Helper functions and aliases for Docker, Terraform, etc.
- PSScriptAnalyzer settings included
- Work configuration support

### Visual Studio Code

```bash
# Windows
mklink /D "%APPDATA%\Code\User\snippets" "C:\path\to\Profiles\VSCode\snippets"
mklink "%APPDATA%\Code\User\settings.json" "C:\path\to\Profiles\VSCode\settings.json"
mklink "%APPDATA%\Code\User\keybindings.json" "C:\path\to\Profiles\VSCode\keybindings.json"

# Linux/Mac
ln -s ~/path/to/Profiles/VSCode/snippets ~/.config/Code/User/snippets
ln -s ~/path/to/Profiles/VSCode/settings.json ~/.config/Code/User/settings.json
ln -s ~/path/to/Profiles/VSCode/keybindings.json ~/.config/Code/User/keybindings.json
```

**Features:**

- Custom keybindings
- Code snippets for PowerShell and Markdown
- GitHub Copilot chat modes and instructions
- Coding guidelines and style guides

### Windows Terminal

```powershell
# Windows Terminal settings location
# Copy or symlink to: %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```
