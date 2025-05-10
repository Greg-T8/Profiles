setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

alias ls='ls --color=auto'
alias ll='ls -la --color'
alias cls='clear'

# Turn on auto suggestions
# Installation: https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md#manual-git-clone
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Just testing for now
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

    # Update vcs_info message
    hook_com[branch]="%F{cyan}${branch}%f"
    hook_com[added]="%F{green}+${added}%f"
    hook_com[modified]="%F{yellow}~${modified}%f"
    hook_com[deleted]="%F{red}-${deleted}%f"
    hook_com[untracked]="%F{magenta}!${untracked}U%f"
}

# Enable version control feature for usage in prompt
# See https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#Version-Control-Information
# See https://sourceforge.net/p/zsh/code/ci/master/tree/Misc/vcs_info-examples
autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
precmd_functions+=( precmd_vcs_info )
setopt prompt_subst
zstyle ':vcs_info:git:*' actionformats ' [%b|%a%c%u%m%r]'
zstyle ':vcs_info:*' enable-hook true
zstyle ':vcs_info:*' hooks git-hook2
# zstyle ':vcs_info:*' hooks git-hook
# zstyle ':vcs_info:git:*' formats '(%{${hook_com[branch]}%}|%{${hook_com[added]}%} %{${hook_com[modified]}%} %{${hook_com[deleted]}%} %{${hook_com[untracked]}%})'
# zstyle ':vcs_info:git:*' formats '%{${hook_com[branch]}%}'
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr '%F{green}●%f'
zstyle ':vcs_info:git:*' unstagedstr '%F{red}…%f'
zstyle ':vcs_info:git:*' formats ' %f[%b%c%m%u]'

# Define custom prompt characters
box_arc_down_right=$'\u256D'
box_horizontal=$'\u2500'
box_arc_up_right=$'\u2570'
box_horizontal_short=$'\u2574'

# See https://zsh.sourceforge.io/Doc/Release/Prompt-Expansion.html
# Notes:
# - %~: working directory; replaces home directory with ~
# - %F: activate foreground color
# - %f: deactivate foreground color
# - %#: Displays % if shell is running witout privs; displays # if shell is runnign w/ privs
PROMPT=$'\n'\
"%F{cyan}${box_arc_down_right}${box_horizontal}( %~"\
'%F{yellow}${vcs_info_msg_0_}%f'\
$'\n'\
'%F{cyan}${box_arc_up_right}${box_horizontal_short}%f%# '

