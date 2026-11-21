#!/bin/bash
# -------------------------------------------------------------------------
# Description   : Set up command-line tools and configuration on Linux
# Context       : Remote Linux setup — install tools and configure Bash
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-21
# Revision History:
#   2026-11-21 - Rename Linux setup and clarify APT-based usage
#   2026-11-21 - Remove ble.sh installation while retaining fzf
#   2026-11-21 - Install fzf and ble.sh with basic tools and report failures
#   2026-11-21 - Start an interactive Bash shell to load the installed profile
# -------------------------------------------------------------------------
#
# USAGE:
#   1. Make the script executable:
#      chmod +x init-linux.sh
#
#   2. Run the script:
#      ./init-linux.sh
#
#   3. After completion, restart your terminal or run:
#      exec bash
#
# WHAT THIS SCRIPT DOES:
#   - Downloads profile dotfiles from GitHub (.bashrc, .vimrc, .inputrc)
#   - Installs basic tools (curl, wget, vim, less, procps, fzf)
#   - Configures bash with vi mode and custom prompt
#
# REQUIREMENTS:
#   - Linux environment, preferably an APT-based distribution
#   - Sudo privileges or run as root
#
# -------------------------------------------------------------------------

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# GitHub repository information
GITHUB_REPO="https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux"

# Configuration files to download
DOTFILES=(".bashrc" ".inputrc" ".vimrc")

# List of essential tools to install
# Add or remove tools as needed for your Linux environment
TOOLS=(
    "curl"          # URL transfer tool
    "wget"          # File downloader
    "vim"           # Text editor
    "less"          # Pager for viewing files
    "procps"        # Process utilities (ps, top, etc.)
    "fzf"           # Fuzzy command history picker
    # "git"         # Version control
)

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    echo ""
    info "Linux Initialization Script"
    info "Author: Greg Tate"
    info "Date: $(date)"
    echo ""

    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ] && ! command -v sudo &> /dev/null; then
        warning "Not running as root and sudo is not available"
        warning "Some operations may fail"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi

    # Execute setup functions
    install_tools || warning "Basic tools setup was incomplete"
    download_configs

    # Display completion message
    show_summary

    # Apply configuration files
    info "Applying configuration..."

    # Change to home directory
    cd ~

    # Force interactive startup so Bash reads the newly installed .bashrc.
    info "Starting new bash shell with configurations..."
    exec bash -i
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

# ==============================================================================
# MAIN FUNCTIONS
# ==============================================================================

# Download configuration files from GitHub
download_configs() {
    section "Downloading Configuration Files"

    local target_home="$HOME"

    info "Downloading configuration files to: $target_home"

    # Check if curl or wget is available
    local downloader=""
    if command -v curl &> /dev/null; then
        downloader="curl"
        info "Using curl for downloads"
    elif command -v wget &> /dev/null; then
        downloader="wget"
        info "Using wget for downloads"
    else
        error "Neither curl nor wget is available"
        error "Please install curl or wget first"
        exit 1
    fi

    # Download each configuration file
    for file in "${DOTFILES[@]}"; do
        local url="${GITHUB_REPO}/${file}"
        local destination="${target_home}/${file}"

        # Backup existing file if it exists
        if [ -e "$destination" ]; then
            local backup="${destination}.backup"
            info "Backing up existing $file to ${file}.backup"
            mv "$destination" "$backup"
            success "Backup created: $backup"
        fi

        # Download file
        info "Downloading $file from GitHub..."
        if [ "$downloader" = "curl" ]; then
            if curl -fsSL "$url" -o "$destination"; then
                success "Downloaded $file successfully"
            else
                error "Failed to download $file"
                warning "URL: $url"
            fi
        else
            if wget -q "$url" -O "$destination"; then
                success "Downloaded $file successfully"
            else
                error "Failed to download $file"
                warning "URL: $url"
            fi
        fi

        # Verify file was created
        if [ -f "$destination" ]; then
            success "File created: $destination"
        else
            error "File not found after download: $destination"
        fi
    done
}

# Install basic tools
install_tools() {
    section "Installing Basic Tools"

    # Track failures while allowing the remaining tools to be installed.
    local failures=0
    local -a privilege=()
    if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        privilege=(sudo)
    fi

    # Set environment variables to avoid interactive prompts during installation
    export DEBIAN_FRONTEND=noninteractive
    export TZ=America/Chicago

    # Detect package manager
    local pkg_manager=""
    if command -v apt-get &> /dev/null; then
        pkg_manager="apt-get"
        info "Detected package manager: apt-get"
    elif command -v yum &> /dev/null; then
        pkg_manager="yum"
        info "Detected package manager: yum"
    elif command -v zypper &> /dev/null; then
        pkg_manager="zypper"
        info "Detected package manager: zypper (SUSE)"
    elif command -v apk &> /dev/null; then
        pkg_manager="apk"
        info "Detected package manager: apk (Alpine)"
    else
        warning "No supported package manager found (apt-get, yum, zypper, apk)"
        warning "Skipping package installation"
        return 1
    fi

    # Update package lists
    info "Updating package lists..."
    case $pkg_manager in
        apt-get)
            "${privilege[@]}" apt-get update -qq || failures=1
            ;;
        yum)
            yum check-update -q || true
            ;;
        zypper)
            "${privilege[@]}" zypper refresh || failures=1
            ;;
        apk)
            "${privilege[@]}" apk update -q || failures=1
            ;;
    esac

    # Install each tool if not present
    for tool in "${TOOLS[@]}"; do
        if command -v "$tool" &> /dev/null; then
            info "$tool is already installed"
        else
            info "Installing $tool..."
            case $pkg_manager in
                apt-get)
                    "${privilege[@]}" apt-get install -y -qq "$tool" || failures=1
                    ;;
                yum)
                    "${privilege[@]}" yum install -y -q "$tool" || failures=1
                    ;;
                zypper)
                    "${privilege[@]}" zypper install -y "$tool" || failures=1
                    ;;
                apk)
                    "${privilege[@]}" apk add -q "$tool" || failures=1
                    ;;
            esac
        fi
    done

    # Confirm the history picker is available after package installation.
    if command -v fzf >/dev/null 2>&1; then
        success "fzf is available"
    else
        error "fzf is not available after package installation"
        failures=1
    fi

    # Report incomplete installations accurately.
    if [ "$failures" -eq 0 ]; then
        success "Tool installation completed"
    else
        warning "Some tools could not be installed; review the errors above"
        return 1
    fi
}

# Display summary and next steps
show_summary() {
    section "Installation Summary"

    echo ""
    info "Linux initialization finished. Review any warnings above."
    echo ""
    info "To activate the configuration in your current session, run:"
    echo -e "  ${GREEN}exec bash${NC}"
    echo ""
    info "Or simply close this terminal and open a new one."
    echo ""
    info "Key features configured:"
    echo "  - Vi mode enabled in bash and vim"
    echo "  - Custom two-line prompt with box-drawing characters"
    echo "  - Enhanced readline configuration (.inputrc)"
    echo "  - All configuration files downloaded from GitHub"
    echo ""
    info "Quick reference:"
    echo "  Vi mode: Press ESC for command mode, 'i' for insert mode"
    echo "  Ctrl+P/N: Navigate command history"
    echo "  Ctrl+A/E: Move to beginning/end of line"
    echo "  Ctrl+K: Delete from cursor to end of line"
    echo "  Ctrl+U: Delete from cursor to beginning of line"
    echo ""
}

# Run main function
main "$@"
