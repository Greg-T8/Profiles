# Profiles

A collection of configuration files and profiles for various development tools and environments.

## ⚡ Quick Bootstrap

### PowerShell Profile

```powershell
# One-liner to install PowerShell profile from GitHub
irm https://raw.githubusercontent.com/Greg-T8/Profiles/main/PowerShell/bootstrap.ps1 | iex
```

### Linux/Docker Container Setup

```bash
# One-liner to setup Linux/Docker environment from GitHub
curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-docker.sh | bash
```

## 📁 Repository Structure

```text
Profiles/
├── draw.io/                              # Draw.io configuration
│   └── draw.io.desktop.config.json
├── Linux/                                # Linux environment configurations
│   ├── .bashrc                          # Bash shell configuration
│   ├── .inputrc                         # Readline configuration
│   ├── .tmux.conf                       # Tmux configuration
│   ├── .vimrc                           # Vim editor configuration
│   ├── .zshrc                           # ZSH shell configuration
│   ├── bootstrap-docker.sh              # Quick bootstrap for Docker containers
│   ├── init-docker.sh                   # Docker container setup script
│   └── init-wsl.sh                      # WSL environment setup script
├── Neovim/                               # Neovim configurations
│   ├── init.lua                         # Main Neovim configuration
│   ├── lazy-lock.nvim.json              # Neovim plugin lockfile
│   ├── lazy-lock.vscode.json            # VSCode Neovim plugin lockfile
│   └── lua/                             # Lua configuration modules
│       ├── _common/                     # Shared configurations (keymaps, plugins)
│       ├── _nvim/                       # Neovim-specific configs
│       ├── _vscode/                     # VSCode Neovim configs
│       └── config/                      # Lazy.nvim configuration
├── PowerShell/                           # PowerShell profile and scripts
│   ├── bootstrap.ps1                    # Quick bootstrap script
│   ├── functions.ps1                    # Custom PowerShell functions
│   ├── Install-RemoteProfile.ps1        # Automated installer
│   ├── profile.ps1                      # PowerShell profile
│   ├── PSScriptAnalyzerSettings.psd1    # Linter settings
│   └── README.md                        # PowerShell-specific documentation
├── VSCode/                               # Visual Studio Code settings
│   ├── settings.json                    # Editor settings
│   ├── keybindings.json                 # Custom keybindings
│   ├── snippets/                        # Code snippets
│   │   ├── DefaultProfile.code-snippets
│   │   └── markdown.code-snippets
│   ├── chatmodes/                       # GitHub Copilot chat modes
│   │   ├── Plan.chatmode.md
│   │   └── Refactor.chatmode.md
│   └── instructions/                    # Copilot instructions
│       ├── General Coding Guidelines.instructions.md
│       ├── PowerShell Style Guidelines.instructions.md
│       └── Shell Style Guidelines.instructions.md
└── Windows Terminal/                     # Windows Terminal configuration
    └── settings.json
```

## 🚀 Manual Setup

For manual configuration or customization, use the following setup instructions.

### Linux Configurations

#### Docker Container Quick Setup

The `init-docker.sh` script provides automated setup for Docker containers:

```bash
# Clone repository first
git clone https://github.com/Greg-T8/Profiles.git ~/profiles
cd ~/profiles/Linux

# Make executable and run
chmod +x init-docker.sh
./init-docker.sh
```

**What it does:**

- Automatically installs vim, git, curl, wget
- Creates symlinks for .bashrc, .vimrc, .inputrc
- Configures vi mode and custom prompt
- Works with apt-get, yum, and apk package managers

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
.\Install-RemoteProfile.ps1
```

Or use the bootstrap one-liner (see Quick Bootstrap section above).

**What it does:**

- Creates symlinks to PowerShell profile files
- Sets up profile directory structure
- Configures PSReadLine with Vi mode
- Installs custom prompt with Git integration

#### Manual Setup

```powershell
# Create symlink to PowerShell profile
New-Item -ItemType SymbolicLink -Path $PROFILE.CurrentUserAllHosts -Target "C:\path\to\Profiles\PowerShell\profile.ps1"
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

## 🛠️ Customization

Each configuration file is well-documented with inline comments explaining:

- What each setting does
- Why it's configured that way
- Available alternatives

Feel free to fork and customize to your preferences!

## 📝 Key Features by Tool

### Vim (.vimrc)

- ✅ Vi mode cursor shapes (block/beam)
- ✅ Leader key mappings (Space as leader)
- ✅ Visual guides (line numbers, color column)
- ✅ No line wrapping mode
- ✅ Enhanced search settings

### ZSH (.zshrc)

- ✅ Vi mode with visual feedback
- ✅ History substring search
- ✅ Git integration in prompt
- ✅ Enhanced completion system
- ✅ Custom box-drawing prompt

### Neovim (init.lua)

- ✅ Lazy.nvim plugin management
- ✅ VSCode Neovim compatibility
- ✅ Modular Lua configuration
- ✅ Modern plugin ecosystem

### PowerShell (profile.ps1)

- ✅ Custom prompt with Git status
- ✅ Helper functions
- ✅ Code quality standards

### VSCode

- ✅ Integrated snippets
- ✅ Copilot enhancements
- ✅ Style guidelines
- ✅ Custom keybindings

## 🤝 Contributing

This is a personal configuration repository, but suggestions and improvements are welcome! Feel free to open an issue or submit a pull request.

## 📄 License

MIT License - Feel free to use and modify these configurations for your own use.

## 🔗 Related Resources

- [Vim Documentation](https://www.vim.org/docs.php)
- [ZSH Documentation](https://zsh.sourceforge.io/Doc/)
- [Neovim Documentation](https://neovim.io/doc/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [VSCode Documentation](https://code.visualstudio.com/docs)

---

**Author:** Greg-T8  
**Last Updated:** November 2025
