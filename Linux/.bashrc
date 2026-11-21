# ==============================================================================
# Description   : Configure interactive Bash settings, prompt, history, and aliases
# Context       : Profiles configuration — Linux Bash profile
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-21
# Revision History:
#   2026-11-21 - Fix root fzf installation and defer the Vi mode indicator setting
#   2026-11-21 - Mirror configured Readline Vi bindings in ble.sh
#   2026-11-21 - Hide ble.sh Vi indicator and apply Readline bindings before loading it
#   2026-11-21 - Add ble.sh automatic history completion menu
#   2026-11-21 - Show fzf history results in a compact dropdown and load Bash integration
#   2026-11-21 - Install fzf when missing on Debian-based systems
#   2026-11-21 - Enable fzf command history picker
# ==============================================================================
# ~/.bashrc: executed by bash(1) for non-login shells.
# This configuration enables vi mode with visual feedback, custom prompts,
# and various quality-of-life improvements.
# See /usr/share/doc/bash/examples/startup-files for more examples.

# ==============================================================================
# INTERACTIVE SHELL CHECK
# ==============================================================================
# If running interactively, proceed with the script; otherwise, exit
case $- in
    *i*) ;;
      *) return;;
esac

# Configure Bash's Vi mode and Readline bindings before ble.sh wraps Readline.
set -o vi
if [ -f ~/.inputrc ]; then
    bind -f ~/.inputrc
fi

# Install ble.sh in the user's local data directory when it is not already available.
install_ble_sh() {
    local install_directory
    install_directory=$(mktemp -d) || return 1

    # Download and install ble.sh from its official nightly build in a temporary directory.
    if curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz |
        tar -xJf - -C "$install_directory" &&
        bash "$install_directory/ble-nightly/ble.sh" --install "$HOME/.local/share"; then
        rm -rf -- "$install_directory"
        return 0
    fi

    rm -rf -- "$install_directory"
    return 1
}

# Install and load ble.sh only in interactive shells so it can manage line editing.
if [ ! -r "$HOME/.local/share/blesh/ble.sh" ]; then
    if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && command -v xz >/dev/null 2>&1; then
        if ! install_ble_sh; then
            printf 'ble.sh installation failed; continuing with the standard Bash line editor.\n' >&2
        fi
    else
        printf 'ble.sh needs curl, tar, and xz; continuing with the standard Bash line editor.\n' >&2
    fi
fi

# Load ble.sh without attaching until the remaining Bash settings are applied.
if [ -r "$HOME/.local/share/blesh/ble.sh" ]; then
    source -- "$HOME/.local/share/blesh/ble.sh" --attach=none
fi

# ==============================================================================
# TERMINAL SETTINGS
# ==============================================================================
# Disable line wrapping for output (allows horizontal scrolling)
tput rmam

# Set default editors for CLI tools (git, crontab, etc.)
export EDITOR=vim
export VISUAL=vim

# ==============================================================================
# HISTORY SETTINGS
# ==============================================================================
# Don't record duplicate commands or commands starting with space
HISTCONTROL=ignoreboth

# Append to history file instead of overwriting it
shopt -s histappend

# History size settings
HISTSIZE=1000                          # Commands to remember in current session
HISTFILESIZE=2000                      # Commands to save in history file

# Install fzf on Debian-based systems when it is missing.
if ! command -v fzf >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1 && { [ "$EUID" -eq 0 ] || command -v sudo >/dev/null 2>&1; }; then
        printf 'fzf is missing; installing it with apt-get...\n'
        # Use apt-get directly as root and sudo for an unprivileged user.
        if { [ "$EUID" -eq 0 ] && apt-get update && apt-get install -y fzf; } ||
            { [ "$EUID" -ne 0 ] && sudo apt-get update && sudo apt-get install -y fzf; }; then
            printf 'fzf was installed successfully.\n'
        else
            printf 'fzf installation failed; continuing without the history picker.\n' >&2
        fi
    else
        printf 'fzf is missing. Install it using your system package manager.\n' >&2
    fi
fi

# ==============================================================================
# SHELL OPTIONS
# ==============================================================================
# Check window size after each command and update LINES and COLUMNS
shopt -s checkwinsize

# Enable "**" pattern for recursive directory matching (uncomment if desired)
#shopt -s globstar

# ==============================================================================
# LESS CONFIGURATION
# ==============================================================================
# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# ==============================================================================
# CHROOT IDENTIFICATION
# ==============================================================================
# Set variable identifying the chroot you work in (used in prompt)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# ==============================================================================
# PROMPT CONFIGURATION
# ==============================================================================
# ------------------------------------------------------------------------------
# SSH Host Detection
# ------------------------------------------------------------------------------
# Set hostname prefix (green) only when connected via SSH
# Evaluated once at shell startup since SSH status doesn't change mid-session
# Uses \001 and \002 (readline markers) with actual escape sequences
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" ]]; then
    _ssh_host=$'\001\e[32m\002'"$HOSTNAME"$'\001\e[36m\002 '
else
    _ssh_host=""
fi

# ------------------------------------------------------------------------------
# Custom Prompt Function
# ------------------------------------------------------------------------------
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( ~/path/to/directory
#   ╰─$
# When connected via SSH:
#   ╭─( hostname ~/path/to/directory
#   ╰─$
setup_custom_prompt() {
    local use_color="${1:-yes}"  # Default to yes if no parameter provided

    # Define colors based on parameter
    if [ "$use_color" = "yes" ]; then
        local cyan=$'\001\e[36m\002'   # Cyan color
        local reset=$'\001\e[0m\002'   # Reset color
        # Build custom PS1 prompt with color
        PS1=$'\n'"${cyan}"$'╭─( '"${_ssh_host}"$'\w\n'"${cyan}"$'╰─'"${reset}"$'\$ '
    else
        # Build custom PS1 prompt without color
        PS1=$'\n╭─( '"${_ssh_host}"$'\w\n╰─\$ '
    fi
}

# ------------------------------------------------------------------------------
# Color Detection
# ------------------------------------------------------------------------------
# Detect if terminal supports color
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# Force color prompt (uncomment to enable)
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # Terminal supports color (Ecma-48/ISO/IEC-6429 compliant)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

# Apply appropriate prompt based on color support
if [ "$color_prompt" = yes ]; then
    setup_custom_prompt yes
else
    # Use custom prompt without colors
    setup_custom_prompt no
fi
unset color_prompt force_color_prompt

# ------------------------------------------------------------------------------
# Terminal Title Configuration
# ------------------------------------------------------------------------------
# Set xterm/rxvt title to user@host:dir
# Disabled for custom prompt to avoid username/hostname display
#case "$TERM" in
#xterm*|rxvt*)
#    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
#    ;;
#*)
#    ;;
#esac

# ==============================================================================
# COLOR SUPPORT
# ==============================================================================
# Enable color support for ls and related commands
if [ -x /usr/bin/dircolors ]; then
    # Load dircolors configuration if available
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"

    # Colorized command aliases
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Colored GCC warnings and errors (uncomment if desired)
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# ==============================================================================
# ALIASES
# ==============================================================================
# ls command variations
alias ll='ls -alF'                    # Long listing with hidden files and indicators
alias la='ls -A'                      # Show hidden files except . and ..
alias l='ls -CF'                      # Compact listing with indicators

# Windows-style command aliases
alias cls='clear'                     # Windows-style clear command
alias md='mkdir'                      # Windows-style make directory

# Alert alias for long-running commands
# Usage: sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# ==============================================================================
# EXTERNAL CONFIGURATION
# ==============================================================================
# Load additional aliases from separate file if it exists
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# ==============================================================================
# PROGRAMMABLE COMPLETION
# ==============================================================================
# Enable bash completion features
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Enable a delayed, linewise menu for automatic history completions.
if [ -n "${BLE_VERSION:-}" ]; then
    bleopt complete_auto_menu=500
    bleopt complete_menu_style=linewise
    bleopt complete_menu_maxlines=10

    # Register ble.sh-native equivalents for the custom Readline Vi bindings.
    ble_configure_vi_bindings() {
        # Hide the Vi mode indicator after its option is registered.
        bleopt keymap_vi_mode_show=
        # Enable Meta-key sequences in insert mode before binding Alt+B and Alt+F.
        ble-decode/keymap:vi_imap/define-meta-bindings

        # Match the Readline bindings used while entering a command.
        ble-bind -m vi_imap -f C-p history-prev
        ble-bind -m vi_imap -f C-n history-next
        ble-bind -m vi_imap -f M-b backward-cword
        ble-bind -m vi_imap -f M-f forward-cword
        ble-bind -m vi_imap -f C-a beginning-of-line
        ble-bind -m vi_imap -f C-e end-of-line
        ble-bind -m vi_imap -f C-k kill-forward-line
        ble-bind -m vi_imap -f C-u kill-backward-line
        ble-bind -m vi_imap -f C-w kill-backward-uword
        ble-bind -m vi_imap -f up history-search-backward
        ble-bind -m vi_imap -f down history-search-forward

        # Match the corresponding custom bindings in Vi command mode.
        ble-bind -m vi_nmap -f C-p vi-command/history-prev
        ble-bind -m vi_nmap -f C-n vi-command/history-next
        ble-bind -m vi_nmap -f M-b backward-cword
        ble-bind -m vi_nmap -f M-f forward-cword
        ble-bind -m vi_nmap -f C-a beginning-of-line
        ble-bind -m vi_nmap -f C-e end-of-line
        ble-bind -m vi_nmap -f C-k kill-forward-line
        ble-bind -m vi_nmap -f C-u kill-backward-line
        ble-bind -m vi_nmap -f C-w kill-backward-uword

        # Preserve the configured block and line cursor shapes in each mode.
        ble-bind -m vi_imap --cursor 6
        ble-bind -m vi_nmap --cursor 2
    }
    blehook/eval-after-load keymap_vi ble_configure_vi_bindings

    # Use ble.sh's compatibility layer for fzf key bindings when fzf is installed.
    if command -v fzf >/dev/null 2>&1; then
        export FZF_CTRL_R_OPTS='--height=~40% --layout=reverse --border'
        ble-import -d integration/fzf-completion
        ble-import -d integration/fzf-key-bindings
    fi

    # Attach ble.sh after the rest of the shell configuration is loaded.
    ble-attach
elif command -v fzf >/dev/null 2>&1; then
    export FZF_CTRL_R_OPTS='--height=~40% --layout=reverse --border'

    # Load fzf's modern integration or a packaged key-binding script for older releases.
    if fzf --bash >/dev/null 2>&1; then
        eval "$(fzf --bash)"
    elif [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
        . /usr/share/doc/fzf/examples/key-bindings.bash
    elif [ -r /usr/share/fzf/key-bindings.bash ]; then
        . /usr/share/fzf/key-bindings.bash
    else
        printf 'fzf Bash bindings were not found; Ctrl+R will use Bash reverse search.\n' >&2
    fi
fi
