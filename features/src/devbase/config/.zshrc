# Managed by the devbase devcontainer Feature — do not edit in place.
#
# Rebuilding the container overwrites this file, which is deliberate: it is what
# stops the team prompt drifting per repository (the copies this replaced had
# diverged by 29 lines for no reason anyone chose).
#
# Per-repository or personal additions go in ~/.zshrc.local, sourced at the end.

# Oh My Zsh cache directory
export ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
[[ -d "$ZSH_CACHE_DIR" ]] || mkdir -p "$ZSH_CACHE_DIR"

###### Interactive setup — skipped in CI ######
if [[ "${GITHUB_CLI:-false}" != "true" && "${CI:-false}" != "true" ]]; then
  export ZSH=$HOME/.oh-my-zsh

  # Guarded: a base image without Oh My Zsh still gets a working shell, just
  # without the theme and plugins.
  if [[ -d "$ZSH" ]]; then
    ZSH_THEME="devcontainers"
    plugins=(git zsh-autosuggestions)
    source "$ZSH/oh-my-zsh.sh"
  fi

  setopt PROMPT_SUBST

  prompt_path_segment() {
    print -r -- "%K{33}%F{255} %~ %f%k"
  }

  prompt_git_segment() {
    local arrow=$'\ue0b0'
    command git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
      print -r -- "%F{33}${arrow}%f"
      return
    }

    local branch git_status_text line x y
    local staged=0 unstaged=0 deleted=0 untracked=0 conflicted=0 stashed=0
    local ahead=0 behind=0 is_dirty=0

    branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null) || return
    git_status_text=$(git status --porcelain --branch 2>/dev/null)

    while IFS= read -r line; do
      if [[ "$line" == '## '* ]]; then
        [[ "$line" =~ 'ahead '([0-9]+) ]] && ahead=${match[1]}
        [[ "$line" =~ 'behind '([0-9]+) ]] && behind=${match[1]}
        continue
      fi

      if [[ "$line" == '?? '* ]]; then
        ((untracked++))
        continue
      fi

      x=${line[1,1]}
      y=${line[2,2]}

      [[ "$x" != ' ' ]] && ((staged++))
      [[ "$y" != ' ' ]] && ((unstaged++))
      [[ "$x" == 'D' || "$y" == 'D' ]] && ((deleted++))
      [[ "$x" == 'U' || "$y" == 'U' || "$line" == 'AA '* || "$line" == 'DD '* ]] && ((conflicted++))
    done <<< "$git_status_text"

    stashed=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

    if (( staged > 0 || unstaged > 0 || deleted > 0 || untracked > 0 || conflicted > 0 || stashed > 0 )); then
      is_dirty=1
    fi

    local bg_color=70
    ((is_dirty > 0)) && bg_color=178

    local changes=""
    ((ahead > 0)) && changes+="⇡${ahead}"
    ((behind > 0)) && changes+="⇣${behind}"
    ((unstaged > 0)) && changes+="±"
    ((staged > 0)) && changes+="✚"
    ((untracked > 0)) && changes+="?"
    ((stashed > 0)) && changes+="*"
    ((is_dirty == 0)) && changes+="✓"

    print -r -- "%F{33}%K{${bg_color}}${arrow}%f%F{0} ⎇ ${branch}${changes:+ ${changes}} %f%k%F{${bg_color}}${arrow}%f"
  }

  PROMPT='$(prompt_path_segment)$(prompt_git_segment) '

  # Command history. HISTFILE is what drives zsh-autosuggestions, and the
  # devbase Feature symlinks it to the host so it survives rebuilds.
  HISTFILE=~/.zsh_history
  HISTSIZE=5000
  SAVEHIST=5000
  setopt APPEND_HISTORY
  setopt SHARE_HISTORY
  setopt HIST_IGNORE_DUPS
  setopt HIST_IGNORE_ALL_DUPS
  setopt HIST_REDUCE_BLANKS
  setopt HIST_VERIFY

  # Native zsh history search (plugin-free)
  autoload -U up-line-or-beginning-search down-line-or-beginning-search
  zle -N up-line-or-beginning-search
  zle -N down-line-or-beginning-search
  bindkey '^[[A' up-line-or-beginning-search
  bindkey '^[[B' down-line-or-beginning-search
  bindkey '^P' up-line-or-beginning-search
  bindkey '^N' down-line-or-beginning-search
  bindkey '^R' history-incremental-search-backward
  bindkey '^S' history-incremental-search-forward

  # Oh My Zsh update checks are noise in a container that gets rebuilt.
  zstyle ':omz:update' mode disabled
fi

# pnpm — kept in sync with the PNPM_HOME the Feature installs global packages to.
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Per-repository and personal overrides. Not managed by the Feature, never
# overwritten — put your own aliases, exports and prompt tweaks here.
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
