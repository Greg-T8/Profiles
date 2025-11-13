# ==============================================================================
# BASH CONFIGURATION
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

# ==============================================================================
# TMUX AUTO-START
# ==============================================================================
# Automatically start tmux if available and not already in a tmux session
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [ -z "$TMUX_AUTOSTART_SKIP" ]; then
    # Start tmux: attach to existing session or create new one
    tmux attach-session -t default || tmux new-session -s default
fi

# ==============================================================================
# TERMINAL SETTINGS
# ==============================================================================
# Disable line wrapping for output (allows horizontal scrolling)
tput rmam

# ==============================================================================
# VI MODE CONFIGURATION
# ==============================================================================
# Enable vi command line editing mode (uses ~/.inputrc vi settings)
set -o vi

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
# Custom Prompt Function
# ------------------------------------------------------------------------------
# Two-line prompt with box-drawing characters
# Format:
#   ╭─( ~/path/to/directory
#   ╰─╴$
setup_custom_prompt() {
    # Define box-drawing characters (Unicode)
    box_arc_down_right=$'\u256D'    # ╭
    box_horizontal=$'\u2500'        # ─
    box_arc_up_right=$'\u2570'      # ╰
    box_horizontal_short=$'\u2574'  # ╴

    # Define colors using ANSI escape sequences
    cyan='\[\e[36m\]'               # Cyan color
    reset='\[\e[0m\]'               # Reset color

    # Build custom PS1 prompt
    PS1=$'\n'\
"${cyan}${box_arc_down_right}${box_horizontal}( \w"\
$'\n'\
"${cyan}${box_arc_up_right}${box_horizontal_short}${reset}\\$ "
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
    setup_custom_prompt
else
    # Fallback to simple prompt without colors
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# ------------------------------------------------------------------------------
# Terminal Title Configuration
# ------------------------------------------------------------------------------
# Set xterm/rxvt title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

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

# ==============================================================================
# STARTUP DIRECTORY
# ==============================================================================
# Change to home directory if starting in Windows directory
if [[ $PWD == /mnt/c/* ]]; then
    cd ~
fi
