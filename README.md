# Profiles

A collection of configuration files and profiles for various development tools and environments.

## 📁 Repository Structure

```
Profiles/
├── draw.io/              # Draw.io configuration
├── Linux/                # Linux environment configurations
│   ├── .vimrc           # Vim editor configuration
│   └── .zshrc           # ZSH shell configuration
├── Neovim/              # Neovim configurations
│   ├── init.lua         # Main Neovim configuration
│   ├── lua/             # Lua configuration modules
│   │   ├── _common/     # Shared configurations
│   │   ├── _nvim/       # Neovim-specific configs
│   │   └── _vscode/     # VSCode Neovim configs
├── PowerShell/          # PowerShell profile and scripts
│   ├── profile.ps1      # PowerShell profile
│   ├── prompt.ps1       # Custom prompt configuration
│   └── functions.ps1    # Custom PowerShell functions
├── VSCode/              # Visual Studio Code settings
│   ├── settings.json    # Editor settings
│   ├── keybindings.json # Custom keybindings
│   ├── snippets/        # Code snippets
│   ├── chatmodes/       # GitHub Copilot chat modes
│   └── instructions/    # Copilot instructions
└── Windows Terminal/    # Windows Terminal configuration
    └── settings.json
```

## 🚀 Quick Start

### Linux Configurations

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

```powershell
# Create symlink to PowerShell profile
New-Item -ItemType SymbolicLink -Path $PROFILE -Target "C:\path\to\Profiles\PowerShell\profile.ps1"
```

**Features:**

- Custom prompt with Git integration
- Helper functions for common tasks
- PSScriptAnalyzer settings included

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
**Last Updated:** October 2025
