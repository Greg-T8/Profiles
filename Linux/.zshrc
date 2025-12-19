# ==============================================================================
# ZSH CONFIGURATION
# ==============================================================================
# This configuration enables vi mode with visual feedback, custom prompts,
# git integration, and various quality-of-life improvements.

# ==============================================================================
# TMUX AUTO-START
# ==============================================================================
# Automatically start tmux if available and not already in a tmux session
#
# SETUP: To use separate sessions in VS Code vs Windows Terminal, add this to
# VS Code settings.json (Ctrl+Shift+P -> "Preferences: Open User Settings (JSON)"):
#
#   "terminal.integrated.env.linux": {
#       "TMUX_SESSION": "vscode"
#   }
#
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [ -z "$TMUX_AUTOSTART_SKIP" ]; then
    # Detect VS Code terminal and use appropriate session name
    if [ -n "$VSCODE_SHELL_INTEGRATION" ]; then
        SESSION_NAME="vscode"
    else
        SESSION_NAME="terminal"
    fi

    # Start or attach to the session
    tmux attach-session -t "$SESSION_NAME" || tmux new-session -s "$SESSION_NAME"
fi

# ==============================================================================
# VSCODE SHELL INTEGRATION
# ==============================================================================
# Enable VS Code shell integration if running in VS Code terminal
# See: https://code.visualstudio.com/docs/terminal/shell-integration
if [ -n "$VSCODE_SHELL_INTEGRATION" ]; then
    # Temporarily unset to prevent recursive issues
    unset VSCODE_SHELL_INTEGRATION
    . "$(code --locate-shell-integration-path zsh)"
fi

# ==============================================================================
# HISTORY SETTINGS
# ==============================================================================
setopt histignorealldups sharehistory  # Don't save duplicates, share across sessions
HISTSIZE=1000                          # Number of commands to remember in session
SAVEHIST=1000                          # Number of commands to save to file
HISTFILE=~/.zsh_history               # History file location

# ==============================================================================
# INTERACTIVE COMMENTS
# ==============================================================================
setopt interactivecomments            # Allow comments in interactive shell

# ==============================================================================
# BELL CONFIGURATION
# ==============================================================================
# Disable all notification bells (audible and visual)
setopt NO_BEEP                        # Disable beep on errors
unsetopt BEEP                         # Alternative way to disable beep
unsetopt LIST_BEEP                    # Disable beep on ambiguous completion
unsetopt HIST_BEEP                    # Disable beep on history errors

# ==============================================================================
# TERMINAL SETTINGS
# ==============================================================================
# Disable line wrapping for output (allows horizontal scrolling)
tput rmam

# ==============================================================================
# VI MODE CONFIGURATION
# ==============================================================================
# Enable vi keybindings for command-line editing
bindkey -v

# Reduce ESC key delay for faster mode switching
# Default is 40 (400ms). Setting to 10 (100ms) is fast but stable for pasting
export KEYTIMEOUT=10

# Note: KEYTIMEOUT=1 causes issues with pasted multi-line text:
# - Last character may capitalize (escape sequence timing issue)
# - Multi-line navigation with k/j breaks
# - Recommended range: 10-20 for good ESC response without paste issues
# To apply changes to KEYTIMEOUT: use 'exec zsh' instead of 'source ~/.zshrc'

# Set default editors for CLI tools (git, crontab, etc.)
export EDITOR=vim
export VISUAL=vim

# Enable edit-command-line: Press 'v' in normal mode to edit command in vim
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line

# Enable run-help for built-in help system
autoload -Uz run-help
alias help=run-help

# ------------------------------------------------------------------------------
# Key Bindings
# ------------------------------------------------------------------------------
# Fix backspace and delete in vi insert mode (common issue after mode switching)
bindkey -M viins '^?' backward-delete-char    # Backspace
bindkey -M viins '^H' backward-delete-char    # Ctrl+H (alternative backspace)
bindkey -M viins '^[[3~' delete-char          # Delete key

# History navigation with Ctrl+P/N in insert mode
bindkey -M viins '^P' up-line-or-history      # Ctrl+P: previous command
bindkey -M viins '^N' down-line-or-history    # Ctrl+N: next command

# History search with Ctrl+R (fallback if fzf is not installed)
bindkey -M viins '^R' history-incremental-search-backward
bindkey -M vicmd '^R' history-incremental-search-backward

# Vi mode navigation - buffer-only movement (no history)
# Note: In standard vi-mode, k/j access history. These bindings change that behavior
# to only move within the current multi-line command buffer.
bindkey -M vicmd 'k' up-line-or-search        # k: move up in buffer, search if at top
bindkey -M vicmd 'j' down-line-or-search      # j: move down in buffer, search if at bottom

# Multi-line command editing
# Alt+Enter inserts a literal newline for multi-line command input
# Uses self-insert-unmeta which strips the escape/meta bit to insert literal newline
# Allows cursor navigation between lines (like ESC+Enter described in zsh guide)
# See https://zsh.sourceforge.io/Guide/zshguide04.html#l100 (4.6.1: Multi-line Editing)
bindkey -M viins '\e^M' self-insert-unmeta  # Alt+Enter
bindkey -M vicmd '\e^M' self-insert-unmeta  # Alt+Enter in normal mode

# Ctrl+O converts continuation lines (PS2 prompts) into a single editable buffer
# Useful for editing commands that span multiple lines with continuations
bindkey -M viins '^O' push-line-or-edit  # Ctrl+O
bindkey -M vicmd '^O' push-line-or-edit  # Ctrl+O in normal mode


# ------------------------------------------------------------------------------
# Cursor Shape Based on Vi Mode
# ------------------------------------------------------------------------------
# Changes cursor to block in normal mode, beam in insert mode
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[2 q'  # Block cursor for normal mode
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] || [[ ${KEYMAP} = '' ]] || [[ $1 = 'beam' ]]; then
    echo -ne '\e[6 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

# Set beam cursor on shell startup (start in insert mode)
function zle-line-init {
  echo -ne '\e[6 q'
}
zle -N zle-line-init

# Reset cursor to default shape on exit
function reset_cursor {
  echo -ne '\e[ q'
}
trap reset_cursor EXIT

# ==============================================================================
# COMPLETION SYSTEM
# ==============================================================================
# Load and configure zsh's powerful tab completion system
autoload -Uz compinit
compinit

# Completion behavior settings
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt 'Scrolling active: current selection at %p'
zstyle ':completion:*' list-prompt 'At %p: Hit TAB for more, or the character to insert'
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

# Enable colored completion listings
eval "$(dircolors -b)"

# Case-insensitive completion matching
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'

# Colorize process list for kill command
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# Arrow key navigation in completion menu
zmodload zsh/complist
bindkey -M menuselect '^[[A' up-line-or-history        # Up arrow
bindkey -M menuselect '^[[B' down-line-or-history      # Down arrow
bindkey -M menuselect '^[[D' backward-char             # Left arrow
bindkey -M menuselect '^[[C' forward-char              # Right arrow

# ==============================================================================
# ALIASES
# ==============================================================================
alias ls='ls --color=auto'            # Colorize ls output
alias ll='ls -la --color'             # Long listing with hidden files
alias cls='clear'                     # Windows-style clear command
alias md='mkdir'                      # Windows-style make directory

# Docker shortcuts
alias dex='docker exec -it'           # Docker exec interactive
alias dil='docker image ls -a'        # Docker image list all with full IDs
alias dcl='docker container ls -a'    # Docker container list all with full IDs

# Tmux session shortcuts
alias ta='tmux attach -t'             # Attach to tmux session by name
alias tat='tmux attach -t terminal'   # Attach to terminal session
alias tav='tmux attach -t vscode'     # Attach to vscode session

# ==============================================================================
# PLUGINS
# ==============================================================================
# ------------------------------------------------------------------------------
# FZF - Fuzzy Finder (PowerShell-like list view for history)
# ------------------------------------------------------------------------------
# Provides interactive list view for command history (replaces Ctrl+R)
# Installation: sudo apt install fzf
# Features:
#   Ctrl+R - History search with list view
#   Ctrl+T - File finder
#   Alt+C  - Directory changer
if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
elif [ -f ~/.fzf/shell/key-bindings.zsh ]; then
    source ~/.fzf/shell/key-bindings.zsh
fi

# ------------------------------------------------------------------------------
# Zsh Autosuggestions (PowerShell-like inline predictions)
# ------------------------------------------------------------------------------
# Provides fish-like autosuggestions based on command history
# Installation: git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
# Usage: Press → (right arrow) to accept suggestion
if [[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# ==============================================================================
# GIT INTEGRATION (VCS_INFO)
# ==============================================================================
# Enable version control information in prompt
# See: https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#Version-Control-Information
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst

# Configure git status display
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '%F{green}●%f'      # Green dot for staged changes
zstyle ':vcs_info:git:*' unstagedstr '%F{red}…%f'      # Red ellipsis for unstaged changes
zstyle ':vcs_info:git:*' formats ' %f[%b%c%m%u]'       # Format: [branch●…]
zstyle ':vcs_info:git:*' actionformats ' [%b|%a%c%u%m%r]'  # Format during rebase/merge
zstyle ':vcs_info:*' enable-hook true
zstyle ':vcs_info:*' hooks git-hook2

# ------------------------------------------------------------------------------
# Custom Git Hook (Experimental)
# ------------------------------------------------------------------------------
# Counts git status changes - currently for testing
function git-hook() {
    echo 'this is a test'
    local -a git_status
    git_status=("${(f)$(git status --porcelain -b)}")

    local -i added=0 modified=0 untracked=0 deleted=0
    local branch=""

    for line in "${git_status[@]}"; do
        case $line in
            "##"*) branch="${line#\#\# }" ;;
            "A  "*) ((added++)) ;;
            " M "*) ((modified++)) ;;
            " D "*) ((deleted++)) ;;
            "?? "*) ((untracked++)) ;;
        esac
    done

    echo "Branch name: ${branch}"
    echo "Added: ${added}"
    echo "Modified: ${modified}"
    echo "Untracked: ${untracked}"
    echo "Deleted: ${deleted}"

    # Update vcs_info message with colored counts
    hook_com[branch]="%F{cyan}${branch}%f"
    hook_com[added]="%F{green}+${added}%f"
    hook_com[modified]="%F{yellow}~${modified}%f"
    hook_com[deleted]="%F{red}-${deleted}%f"
    hook_com[untracked]="%F{magenta}!${untracked}U%f"
}

# ==============================================================================
# CUSTOM PROMPT
# ==============================================================================
# Two-line prompt with box-drawing characters and git integration
# Format:
#   ╭─( ~/path/to/directory [git-branch●…]
#   ╰─%

# ------------------------------------------------------------------------------
# Get-PromptPath: Returns shortened path for prompt display
# ------------------------------------------------------------------------------
# Replicates PowerShell Get-MyPromptPath behavior:
#   - Paths under Linux $HOME use ~ prefix
#   - Paths under Windows home (/mnt/c/Users/gregt) use ~win prefix
#   - Long paths (>50 chars or >4 folders) are shortened:
#     First 3 folders + ... + last 2 folders
function get_prompt_path() {
    local location="$PWD"
    local prompt_path=""
    local relative_path=""
    local prefix=""

    # Define home directories
    local linux_home="$HOME"
    local win_home="/mnt/c/Users/gregt"

    # Remove trailing slash except for root
    if [[ "$location" != "/" && "$location" == */ ]]; then
        location="${location%/}"
    fi

    # Check if path is under Windows home (check first, more specific)
    if [[ "$location" == "$win_home"* ]]; then
        if [[ "$location" == "$win_home" ]]; then
            prompt_path="~win"
        else
            prefix="~win"
            relative_path="${location#$win_home}"
        fi
    # Check if path is under Linux home
    elif [[ "$location" == "$linux_home"* ]]; then
        if [[ "$location" == "$linux_home" ]]; then
            prompt_path="~"
        else
            prefix="~"
            relative_path="${location#$linux_home}"
        fi
    else
        # Outside both home directories
        relative_path="$location"
        prefix=""
    fi

    # If prompt_path is already set (at home directory), return it
    if [[ -n "$prompt_path" ]]; then
        echo "$prompt_path"
        return
    fi

    # Count path separators in relative path
    local sep_count="${relative_path//[^\/]/}"
    sep_count="${#sep_count}"

    # Short path (<=50 chars) or few folders (<=4 separators): show full path
    if [[ ${#relative_path} -le 50 ]] || [[ $sep_count -le 4 ]]; then
        prompt_path="${prefix}${relative_path}"
    else
        # Long path: keep first 3 folders + ... + last 2 folders
        # Split path into array
        local -a parts
        parts=("${(@s:/:)relative_path}")

        # Remove empty first element if path started with /
        if [[ -z "${parts[1]}" ]]; then
            parts=("${parts[@]:1}")
        fi

        local total_parts=${#parts[@]}

        if [[ $total_parts -le 4 ]]; then
            # Not enough parts to shorten meaningfully
            prompt_path="${prefix}${relative_path}"
        else
            # Build shortened path: first 2 folders + ... + last 2 folders
            local left_path="/${parts[1]}/${parts[2]}"
            local right_path="/${parts[-2]}/${parts[-1]}"
            prompt_path="${prefix}${left_path}/...${right_path}"
        fi
    fi

    echo "$prompt_path"
}

# Prompt configuration
# See: https://zsh.sourceforge.io/Doc/Release/Prompt-Expansion.html
# %F  = start foreground color
# %f  = reset foreground color
# %#  = % for normal user, # for root
PROMPT=$'\n'\
$'%F{cyan}╭─( $(get_prompt_path)'\
'%F{yellow}${vcs_info_msg_0_}%f'\
$'\n'\
$'%F{cyan}╰─%f%# '

# ==============================================================================
# STARTUP DIRECTORY
# ==============================================================================
# Change to home directory if starting in Windows directory
# if [[ $PWD == /mnt/c/* ]]; then
#     cd ~
# fi
