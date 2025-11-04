#!/bin/bash
# -------------------------------------------------------------------------
# Program: init-wsl.sh
# Description: Initialize WSL instance with profile configurations and tools
# Context: Automates setup of bash, zsh, vim, and tmux configurations
# Author: Greg Tate
# Date: November 4, 2025
# -------------------------------------------------------------------------

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Path to Windows profile directory (accessible from WSL)
WINDOWS_PROFILE="/mnt/c/Users/gregt"

# Configuration files to symlink
DOTFILES=(".bashrc" ".inputrc" ".vimrc" ".zshrc" ".tmux.conf")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Print informational message
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Print success message
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Print warning message
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Print error message
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print section header
section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

# Create symbolic links for configuration files
create_symlinks() {
    section "Creating Symbolic Links"

    # Backup and link each configuration file
    for file in "${DOTFILES[@]}"; do
        local target="${WINDOWS_PROFILE}/${file}"
        local link="${HOME}/${file}"

        # Check if source file exists in Windows profile
        if [ ! -f "$target" ]; then
            warning "Source file not found: $target"
            continue
        fi

        # Backup existing file if it exists and is not a symlink
        if [ -e "$link" ] && [ ! -L "$link" ]; then
            local backup="${link}.backup"
            info "Backing up existing $file to ${file}.backup"
            mv "$link" "$backup"
            success "Backup created: $backup"
        fi

        # Remove existing symlink if present
        if [ -L "$link" ]; then
            info "Removing existing symlink: $link"
            rm "$link"
        fi

        # Create symbolic link
        info "Creating symlink: $link -> $target"
        ln -s "$target" "$link"

        # Verify symlink creation
        if [ -L "$link" ]; then
            success "Symlink created successfully for $file"
        else
            error "Failed to create symlink for $file"
        fi
    done
}

# Install and configure ZSH
install_zsh() {
    section "Installing and Configuring ZSH"

    # Check if zsh is already installed
    if command -v zsh &> /dev/null; then
        warning "ZSH is already installed"
    else
        # Install zsh
        info "Installing ZSH..."
        sudo apt update
        sudo apt install zsh -y

        # Verify installation
        if command -v zsh &> /dev/null; then
            success "ZSH installed successfully"
        else
            error "Failed to install ZSH"
            return 1
        fi
    fi

    # Change default shell to zsh
    info "Setting ZSH as default shell..."
    chsh -s "$(which zsh)"
    success "Default shell changed to ZSH"

    # Install zsh-autosuggestions plugin
    info "Installing zsh-autosuggestions plugin..."
    local plugin_dir="${HOME}/.zsh/zsh-autosuggestions"

    # Create .zsh directory if it doesn't exist
    if [ ! -d "${HOME}/.zsh" ]; then
        mkdir -p "${HOME}/.zsh"
    fi

    # Clone or update zsh-autosuggestions
    if [ -d "$plugin_dir" ]; then
        warning "zsh-autosuggestions already exists, updating..."
        cd "$plugin_dir"
        git pull
        cd - > /dev/null
    else
        git clone https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir"
    fi

    # Verify plugin installation
    if [ -f "${plugin_dir}/zsh-autosuggestions.zsh" ]; then
        success "zsh-autosuggestions installed successfully"
    else
        error "Failed to install zsh-autosuggestions"
    fi
}

# Install and configure tmux
install_tmux() {
    section "Installing and Configuring tmux"

    # Check if tmux is already installed
    if command -v tmux &> /dev/null; then
        warning "tmux is already installed"
        tmux -V
    else
        # Install tmux
        info "Installing tmux..."
        sudo apt update
        sudo apt install tmux -y

        # Verify installation
        if command -v tmux &> /dev/null; then
            success "tmux installed successfully"
            tmux -V
        else
            error "Failed to install tmux"
            return 1
        fi
    fi

    # Verify tmux configuration file exists
    if [ -L "${HOME}/.tmux.conf" ]; then
        success "tmux configuration file is properly linked"
    else
        warning "tmux configuration file not found or not linked"
    fi
}

# Install additional useful tools
install_additional_tools() {
    section "Installing Additional Tools"

    info "Updating package lists..."
    sudo apt update

    # List of useful tools
    local tools=("vim" "git" "curl" "wget")

    # Install each tool if not present
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            info "$tool is already installed"
        else
            info "Installing $tool..."
            sudo apt install "$tool" -y
        fi
    done

    success "Additional tools installation completed"
}

# Display summary and next steps
show_summary() {
    section "Installation Summary"

    echo ""
    success "WSL initialization completed successfully!"
    echo ""
    info "Next steps:"
    echo "  1. Close this terminal and reopen to use ZSH"
    echo "  2. Or run: exec zsh"
    echo "  3. tmux will start automatically on next login"
    echo ""
    info "Key features configured:"
    echo "  - Vi mode enabled in bash, zsh, and vim"
    echo "  - Custom prompts with git integration (zsh)"
    echo "  - tmux with custom keybindings (prefix: backtick)"
    echo "  - All configuration files linked to Windows profile"
    echo ""
    info "Quick reference:"
    echo "  tmux prefix key: \` (backtick)"
    echo "  tmux split horizontal: \` + |"
    echo "  tmux split vertical: \` + -"
    echo "  tmux reload config: \` + r"
    echo "  View all tmux bindings: \` + ?"
    echo ""
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo ""
    info "WSL Initialization Script"
    info "Author: Greg Tate"
    info "Date: $(date)"
    echo ""

    # Check if running in WSL
    if ! grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        warning "This script is designed for WSL environments"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi

    # Execute setup functions
    create_symlinks
    install_additional_tools
    install_zsh
    install_tmux

    # Display completion message
    show_summary
}

# Run main function
main "$@"
