# ==============================================================================
# ZSH CONFIGURATION
# ==============================================================================
# This configuration enables vi mode with visual feedback, custom prompts,
# git integration, and various quality-of-life improvements.

# ==============================================================================
# HISTORY SETTINGS
# ==============================================================================
setopt histignorealldups sharehistory  # Don't save duplicates, share across sessions
HISTSIZE=1000                          # Number of commands to remember in session
SAVEHIST=1000                          # Number of commands to save to file
HISTFILE=~/.zsh_history               # History file location

# ==============================================================================
# VI MODE CONFIGURATION
# ==============================================================================
# Enable vi keybindings for command-line editing
bindkey -v

# Reduce ESC key delay for faster mode switching (10ms instead of default 400ms)
export KEYTIMEOUT=1

# Set default editors for CLI tools (git, crontab, etc.)
export EDITOR=vim
export VISUAL=vim

# Enable edit-command-line: Press 'v' in normal mode to edit command in vim
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'v' edit-command-line

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
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

# Enable colored completion listings
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''

# Case-insensitive completion matching
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'

# Colorize process list for kill command
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# ==============================================================================
# ALIASES
# ==============================================================================
alias ls='ls --color=auto'            # Colorize ls output
alias ll='ls -la --color'             # Long listing with hidden files
alias cls='clear'                     # Windows-style clear command

# ==============================================================================
# PLUGINS
# ==============================================================================
# Load zsh-autosuggestions if installed
# Provides fish-like autosuggestions based on command history
# Installation: git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
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
#   ╰─╴%

# Define box-drawing characters (Unicode)
box_arc_down_right=$'\u256D'    # ╭
box_horizontal=$'\u2500'        # ─
box_arc_up_right=$'\u2570'      # ╰
box_horizontal_short=$'\u2574'  # ╴

# Prompt configuration
# See: https://zsh.sourceforge.io/Doc/Release/Prompt-Expansion.html
# %~  = current directory (~ replaces $HOME)
# %F  = start foreground color
# %f  = reset foreground color
# %#  = % for normal user, # for root
PROMPT=$'\n'\
"%F{cyan}${box_arc_down_right}${box_horizontal}( %~"\
'%F{yellow}${vcs_info_msg_0_}%f'\
$'\n'\
'%F{cyan}${box_arc_up_right}${box_horizontal_short}%f%# '
