#!/bin/bash
# -------------------------------------------------------------------------
# Program: init-wsl.sh
# Description: Initialize WSL instance with profile configurations and tools
# Context: Automates setup of bash, zsh, vim, and tmux configurations
# Author: Greg Tate
# Date: November 4, 2025
# -------------------------------------------------------------------------
#
# USAGE:
#   1. Make the script executable:
#      chmod +x init-wsl.sh
#
#   2. Run the script:
#      ./init-wsl.sh
#
#   3. After completion, restart your terminal or run:
#      exec zsh
#
# WHAT THIS SCRIPT DOES:
#   - Creates symbolic links to your Windows profile dotfiles
#   - Installs ZSH and sets it as default shell
#   - Installs zsh-autosuggestions plugin
#   - Installs FZF for fuzzy finding and history search
#   - Installs tmux for terminal multiplexing
#   - Installs additional tools (vim, git, curl, wget)
#
# REQUIREMENTS:
#   - WSL environment (Ubuntu, Fedora, Alpine, or other Linux distributions)
#   - Internet connection for package installation
#   - Sudo privileges or root access
#
# -------------------------------------------------------------------------

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# Path to Windows profile directory (accessible from WSL)
WINDOWS_PROFILE="/mnt/c/Users/gregt"

# Path to Linux profile directory (contains dotfiles)
LINUX_PROFILE="${WINDOWS_PROFILE}/OneDrive/Apps/Profiles/Linux"

# Configuration files to symlink
DOTFILES=(".bashrc" ".inputrc" ".vimrc" ".zshrc" ".tmux.conf")

# User credentials (will be set during execution)
NEW_USERNAME=""
NEW_PASSWORD=""

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo ""
    info "WSL Initialization Script"
    info "Author: Greg Tate"
    info "Date: $(date)"
    echo ""

    # Verify running as root
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo or run as root)"
        exit 1
    fi

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

    # Setup user account
    setup_user

    # Execute setup functions
    install_additional_tools
    setup_configurations
    install_zsh
    install_fzf
    install_tmux

    # Display completion message
    show_summary

    # Output username for PowerShell script to use
    echo ""
    info "Default user: $NEW_USERNAME"
    echo "$NEW_USERNAME" > /tmp/wsl-default-user.txt

    # Change to home directory
    cd ~
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v apk &> /dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# Update package lists
update_packages() {
    local pkg_manager=$(detect_package_manager)

    info "Detected package manager: $pkg_manager"
    info "Updating package lists..."

    case $pkg_manager in
        apt)
            apt-get update -qq
            ;;
        dnf|yum)
            $pkg_manager check-update -q || true
            ;;
        zypper)
            zypper refresh
            ;;
        apk)
            apk update -q
            ;;
        *)
            warning "Unknown package manager, skipping update"
            return 1
            ;;
    esac
}

# Install a package
install_package() {
    local package=$1
    local pkg_manager=$(detect_package_manager)

    case $pkg_manager in
        apt)
            apt-get install -y -qq "$package"
            ;;
        dnf|yum)
            $pkg_manager install -y -q "$package"
            ;;
        zypper)
            zypper install -y "$package"
            ;;
        apk)
            apk add -q "$package"
            ;;
        *)
            error "Unknown package manager, cannot install $package"
            return 1
            ;;
    esac
}

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

# Create or get user account
setup_user() {
    section "User Account Setup"

    # Prompt for username
    read -p "Enter username for new user account: " NEW_USERNAME

    # Validate username
    if [[ -z "$NEW_USERNAME" ]]; then
        error "Username cannot be empty"
        exit 1
    fi

    # Check if user already exists
    if id "$NEW_USERNAME" &>/dev/null; then
        info "User '$NEW_USERNAME' already exists"
    else
        # Create user
        info "Creating user '$NEW_USERNAME'..."
        useradd -m -s /bin/bash "$NEW_USERNAME"

        # Prompt for password
        info "Setting password for '$NEW_USERNAME'..."
        passwd "$NEW_USERNAME"

        # Add user to sudo group
        info "Adding '$NEW_USERNAME' to sudo group..."
        usermod -aG sudo "$NEW_USERNAME"

        success "User '$NEW_USERNAME' created successfully"
    fi

    # Set as default user for WSL
    info "Setting '$NEW_USERNAME' as default WSL user..."
    # This will be handled by the PowerShell script after this completes
}

# Create symbolic links for configuration files
create_symlinks() {
    section "Creating Symbolic Links"

    local target_home="$1"

    info "Setting up configuration files for: $target_home"

    # Backup and link each configuration file
    for file in "${DOTFILES[@]}"; do
        local target="${LINUX_PROFILE}/${file}"
        local link="${target_home}/${file}"

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

# Setup configuration for both root and user
setup_configurations() {
    section "Configuring Root and User Profiles"

    # Setup symlinks for root
    info "Configuring root profile..."
    create_symlinks "/root"

    # Setup symlinks for new user
    if [ -n "$NEW_USERNAME" ]; then
        info "Configuring $NEW_USERNAME profile..."
        local user_home="/home/$NEW_USERNAME"
        create_symlinks "$user_home"

        # Ensure proper ownership
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "$user_home"
    fi
}

# Install ZSH plugins for a specific user
install_zsh_plugins() {
    local target_home="$1"
    local plugin_dir="${target_home}/.zsh/zsh-autosuggestions"

    # Create .zsh directory if it doesn't exist
    if [ ! -d "${target_home}/.zsh" ]; then
        mkdir -p "${target_home}/.zsh"
    fi

    # Clone or update zsh-autosuggestions
    if [ -d "$plugin_dir" ]; then
        warning "zsh-autosuggestions already exists in $target_home, updating..."
        cd "$plugin_dir"
        git pull
        cd - > /dev/null
    else
        info "Installing zsh-autosuggestions to $target_home..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$plugin_dir"
    fi

    # Verify plugin installation
    if [ -f "${plugin_dir}/zsh-autosuggestions.zsh" ]; then
        success "zsh-autosuggestions installed successfully in $target_home"
    else
        error "Failed to install zsh-autosuggestions in $target_home"
    fi
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
        update_packages
        install_package zsh

        # Verify installation
        if command -v zsh &> /dev/null; then
            success "ZSH installed successfully"
        else
            error "Failed to install ZSH"
            return 1
        fi
    fi

    # Change default shell to zsh for root
    info "Setting ZSH as default shell for root..."
    chsh -s "$(which zsh)" root

    # Change default shell to zsh for new user
    if [ -n "$NEW_USERNAME" ]; then
        info "Setting ZSH as default shell for $NEW_USERNAME..."
        chsh -s "$(which zsh)" "$NEW_USERNAME"
    fi

    success "Default shell changed to ZSH"

    # Install zsh-autosuggestions plugin for root
    info "Installing zsh-autosuggestions for root..."
    install_zsh_plugins "/root"

    # Install zsh-autosuggestions plugin for new user
    if [ -n "$NEW_USERNAME" ]; then
        info "Installing zsh-autosuggestions for $NEW_USERNAME..."
        install_zsh_plugins "/home/$NEW_USERNAME"
        chown -R "$NEW_USERNAME:$NEW_USERNAME" "/home/$NEW_USERNAME/.zsh"
    fi
}

# Install and configure FZF
install_fzf() {
    section "Installing and Configuring FZF"

    # Check if fzf is already installed
    if command -v fzf &> /dev/null; then
        warning "FZF is already installed"
        fzf --version
        return 0
    fi

    # Install fzf
    info "Installing FZF..."
    update_packages
    install_package fzf

    # Verify installation
    if command -v fzf &> /dev/null; then
        success "FZF installed successfully"
        fzf --version
    else
        error "Failed to install FZF"
        return 1
    fi

    # Verify key bindings file exists
    if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        success "FZF key bindings available for ZSH"
    else
        warning "FZF key bindings file not found at expected location"
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
        update_packages
        install_package tmux

        # Verify installation
        if command -v tmux &> /dev/null; then
            success "tmux installed successfully"
            tmux -V
        else
            error "Failed to install tmux"
            return 1
        fi
    fi

    # Verify tmux configuration file exists for root
    if [ -L "/root/.tmux.conf" ]; then
        success "tmux configuration file is properly linked for root"
    else
        warning "tmux configuration file not found or not linked for root"
    fi

    # Verify tmux configuration file exists for new user
    if [ -n "$NEW_USERNAME" ] && [ -L "/home/$NEW_USERNAME/.tmux.conf" ]; then
        success "tmux configuration file is properly linked for $NEW_USERNAME"
    elif [ -n "$NEW_USERNAME" ]; then
        warning "tmux configuration file not found or not linked for $NEW_USERNAME"
    fi
}

# Install additional useful tools
install_additional_tools() {
    section "Installing Additional Tools"

    update_packages

    # List of useful tools
    local tools=("vim" "git" "curl" "wget" "sudo")

    # Install each tool if not present
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            info "$tool is already installed"
        else
            info "Installing $tool..."
            install_package "$tool"
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
    echo "  - FZF for PowerShell-like history list view"
    echo "  - zsh-autosuggestions for inline predictions"
    echo "  - All configuration files linked to Windows profile"
    echo ""
    info "Quick reference:"
    echo "  tmux prefix key: \` (backtick)"
    echo "  tmux split horizontal: \` + |"
    echo "  tmux split vertical: \` + -"
    echo "  tmux reload config: \` + r"
    echo "  View all tmux bindings: \` + ?"
    echo ""
    info "ZSH/FZF shortcuts:"
    echo "  Ctrl+R - Search command history (list view)"
    echo "  Ctrl+T - Search and insert files"
    echo "  Alt+C  - Change directory interactively"
    echo "  → (right arrow) - Accept inline suggestion"
    echo ""
}


# Run main function
main "$@"
