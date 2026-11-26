# Profiles

Profiles contains configuration files for development tools and command-line environments. Use the quick bootstrap commands to install the PowerShell or Linux profile, or follow the manual setup instructions to configure individual tools.

## Quick setup

### PowerShell

To install the PowerShell profile from GitHub, run:

```powershell
# Download and run the PowerShell profile bootstrap script.
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/RemoteProfile/bootstrap.ps1 | iex
```

### Linux

The Linux setup targets APT-based distributions such as Debian and Ubuntu, including remote virtual machines and containers. Run the command as the user whose profile you want to configure. The installer uses `sudo` for package installation when needed.

To install the Linux profile, run:

```bash
# Download and run the Linux profile bootstrap script.
curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-linux.sh | bash
```

If `curl` is not installed on a minimal APT-based system, install it first:

```bash
# Install curl, then download and run the Linux profile bootstrap script.
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-linux.sh | bash
```

## Manual setup

Use these instructions to install or customize individual configurations.

### Linux

#### Run the Linux setup script

The `init-linux.sh` script installs command-line tools and downloads the Bash, Vim, and Readline configuration files. It supports `apt-get`, `yum`, `zypper`, and `apk`. Its package list is geared toward APT-based systems.

To run the script from a local clone:

```bash
# Clone the repository and run the Linux setup script.
git clone https://github.com/Greg-T8/Profiles.git ~/profiles
cd ~/profiles/Linux
chmod +x init-linux.sh
./init-linux.sh
```

The script installs `curl`, `wget`, `vim`, `less`, `procps`, and `fzf`. It backs up existing configuration files before downloading replacements and configures Bash with vi mode and a custom prompt.

#### Configure Vim

To link the Vim configuration into your home directory, run:

```bash
# Link the repository's Vim configuration into your home directory.
ln -s ~/path/to/Profiles/Linux/.vimrc ~/.vimrc
```

The Vim configuration includes vi mode with cursor shape changes, absolute and relative line numbers, an 80-character color column, the Desert color scheme, Space leader mappings, and line-break indicators with wrapping disabled.

#### Configure Zsh

To link and load the Zsh configuration, run:

```bash
# Link and load the repository's Zsh configuration.
ln -s ~/path/to/Profiles/Linux/.zshrc ~/.zshrc
source ~/.zshrc
```

The Zsh configuration includes vi mode with cursor feedback, history substring search, Git branch information in the prompt, a two-line prompt, enhanced tab completion, and Up/Down history search.

To add the optional history substring search plugin, run:

```bash
# Install the optional Zsh history substring search plugin.
git clone https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/zsh-history-substring-search
```

### Neovim

To link the Neovim configuration, run:

```bash
# Link the repository's Neovim configuration into your home directory.
ln -s ~/path/to/Profiles/Neovim ~/.config/nvim
```

The configuration uses Lazy.nvim and includes separate settings for Neovim and VSCode Neovim, plus Lualine, Neo-tree, and Vim-move.

### PowerShell

#### Install the PowerShell profile

The `Install-RemoteProfile.ps1` script installs the profile and its supporting files. To clone the repository and run the installer, use:

```powershell
# Clone the repository and run the PowerShell profile installer.
git clone https://github.com/Greg-T8/Profiles.git "$env:OneDrive\Apps\Profiles"
cd "$env:OneDrive\Apps\Profiles\PowerShell"
.\RemoteProfile\Install-RemoteProfile.ps1
```

You can also use the bootstrap command in [Quick setup](#quick-setup).

The installer configures the PowerShell profile entry point, profile directory structure, PSReadLine vi mode, and a custom prompt with Git integration.

#### Link the profile manually

To link the profile script to the current user's all-hosts profile path, run:

```powershell
# Link the repository's PowerShell profile script to the current profile path.
New-Item -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target "C:\path\to\Profiles\PowerShell\Profile\profile.ps1"
```

The PowerShell configuration includes a two-line prompt with Posh-Git, vi mode with cursor shape changes, helper functions and aliases for Docker and Terraform, PSScriptAnalyzer settings, and work configuration support.

### Visual Studio Code

Create links to the snippets, settings, and keybindings you want to use.

On Windows, run:

```cmd
REM Link the repository's snippets, settings, and keybindings on Windows.
mklink /D "%APPDATA%\Code\User\snippets" "C:\path\to\Profiles\VSCode\snippets"
mklink "%APPDATA%\Code\User\settings.json" "C:\path\to\Profiles\VSCode\settings.json"
mklink "%APPDATA%\Code\User\keybindings.json" "C:\path\to\Profiles\VSCode\keybindings.json"
```

On Linux or macOS, run:

```bash
# Link the repository's snippets, settings, and keybindings on Linux or macOS.
ln -s ~/path/to/Profiles/VSCode/snippets ~/.config/Code/User/snippets
ln -s ~/path/to/Profiles/VSCode/settings.json ~/.config/Code/User/settings.json
ln -s ~/path/to/Profiles/VSCode/keybindings.json ~/.config/Code/User/keybindings.json
```

The VS Code configuration includes custom keybindings, PowerShell and Markdown snippets, GitHub Copilot chat modes and instructions, and coding guidelines.

### Windows Terminal

Windows Terminal stores its settings file at:

```text
%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

Copy or link the repository's settings file to that location.
