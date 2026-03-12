# =============================================================================
# 1. 基础配置与超级自适应预览 
# =============================================================================

export FZF_DEFAULT_OPTS='--height 80% --layout=reverse --border --bind=ctrl-t:top,change:top --bind ctrl-e:down,ctrl-u:up'

# 全局默认使用 fd，自动忽略 .git 和 venv，包含隐藏文件
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude venv'
export FZF_TMUX=1
export FZF_TMUX_HEIGHT='80%'

# [修复] 改为严谨的单行 POSIX 脚本，使用 {q} 完美防范包含空格的乱码文件名
export FZF_PREVIEW_CMD='file={}; if [ -d "$file" ]; then eza --color=always -T -L 1 "$file" 2>/dev/null || tree -C -L 1 "$file" 2>/dev/null || ls -la "$file"; elif file --mime "$file" 2>/dev/null | grep -q binary; then echo "$file is a binary file."; else bat --color=always --style=numbers "$file" 2>/dev/null || ccat --color=always "$file" 2>/dev/null || highlight -O ansi -l "$file" 2>/dev/null || cat "$file" 2>/dev/null; fi'

# =============================================================================
# 2. 核心辅助函数
# =============================================================================
__fzfcmd() {
  [ -n "${TMUX_PANE-}" ] && { [ "${FZF_TMUX:-0}" != 0 ] || [ -n "${FZF_TMUX_OPTS-}" ]; } &&
    echo "fzf-tmux ${FZF_TMUX_OPTS:--d${FZF_TMUX_HEIGHT:-80%}} -- " || echo "fzf"
}

# =============================================================================
# 3. 智能上下文感知 Widget (^P 找文件 / ^T 找目录)
# =============================================================================

# --- CTRL-P: 智能补全/查找文件 ---
fzf-find-widget() {
  setopt localoptions pipefail no_aliases 2> /dev/null
  local ret=0
  local tokens=(${(z)LBUFFER})
  
  local fd_cmd="fd --type f --type l --hidden --follow --exclude .git --exclude venv"
  local dir="."
  local base=""
  local is_wave=0
  local fzf_query=""

  if (( $#tokens )) && [[ $LBUFFER[-1] != ' ' ]]; then
    dir=${(e)tokens[-1]}
    if [[ $dir[1] == '~' ]]; then
      is_wave=1
      dir=${dir/#\~/$HOME}
    fi
    if [[ ! -d $dir ]]; then
      base=$(basename "$dir")
      dir=$(dirname "$dir")
    fi
    fzf_query=$base
  fi

  # [修复] 放弃管道符，使用 FZF_DEFAULT_COMMAND 让 fzf 管理 fd 生命周期，彻底解决卡死
  # [修复] 直接把 --preview 当作参数传入，解决环境变解析混乱
  local match
  match=$(FZF_DEFAULT_COMMAND="$fd_cmd . ${(q)dir} 2>/dev/null" \
          $(__fzfcmd) --preview "$FZF_PREVIEW_CMD" -m ${fzf_query:+--query "$fzf_query"} < /dev/tty)
  ret=$?

  if (( ret == 0 || ret == 130 || ret == 141 )) && [[ -n "$match" ]]; then
    local formatted_match=$(echo "$match" | sed -E 's/^.\///')
    if (( is_wave )); then
      formatted_match=$(echo "$formatted_match" | sed "s|^$HOME|~|")
    fi

    local quoted_match=""
    local item
    for item in ${(f)formatted_match}; do
      quoted_match="$quoted_match ${(q)item}"
    done
    quoted_match=${quoted_match# }

    if (( $#tokens == 1 && $LBUFFER[-1] != ' ' )); then
      LBUFFER="$quoted_match"
    elif [[ $LBUFFER[-1] == ' ' ]]; then
      LBUFFER="${LBUFFER}${quoted_match}"
    else
      LBUFFER="${tokens[1,-2]} ${quoted_match}"
    fi
  fi
  zle reset-prompt
  return $ret
}
zle -N fzf-find-widget
bindkey '^p' fzf-find-widget

# --- CTRL-T: 智能查找并进入目录 ---
fzf-cd-widget() {
  setopt localoptions pipefail no_aliases 2> /dev/null
  local tokens=(${(z)LBUFFER})
  local dir="."
  local base=""
  local fzf_query=""

  if (( $#tokens )) && [[ $LBUFFER[-1] != ' ' ]]; then
    dir=${(e)tokens[-1]}
    dir=${dir/#\~/$HOME}
    if [[ ! -d $dir ]]; then
      base=$(basename "$dir")
      dir=$(dirname "$dir")
    fi
    fzf_query=$base
  fi

  # [修复] 同样改为 FZF_DEFAULT_COMMAND 触发
  local fd_cmd="fd --type d --hidden --follow --exclude .git --exclude venv"
  local match
  match=$(FZF_DEFAULT_COMMAND="$fd_cmd . ${(q)dir} 2>/dev/null" \
          $(__fzfcmd) --preview "$FZF_PREVIEW_CMD" +m ${fzf_query:+--query "$fzf_query"} < /dev/tty)

  if [[ -n "$match" ]]; then
    zle push-line 
    BUFFER="builtin cd -- ${(q)match}"
    zle accept-line
  else
    zle redisplay
  fi
  local ret=$?
  zle reset-prompt
  return $ret
}
zle -N fzf-cd-widget
bindkey '^t' fzf-cd-widget

# =============================================================================
# 4. 官方最强流式历史记录 (^R)
# =============================================================================
fzf-history-widget() {
  local selected
  setopt localoptions noglobsubst noposixbuiltins pipefail no_aliases noglob nobash_rematch 2> /dev/null
  # 使用 perl/awk 直接读取内存数组，拒绝外部低效 sort
  if zmodload -F zsh/parameter p:{commands,history} 2>/dev/null && (( ${+commands[perl]} )); then
    selected="$(printf '%s\t%s\000' "${(kv)history[@]}" |
      perl -0 -ne 'if (!$seen{(/^\s*[0-9]+\**\t(.*)/s, $1)}++) { s/\n/\n\t/g; print; }' |
      FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --scheme=history --bind=ctrl-r:toggle-sort --wrap-sign '\t↳ ' +m --read0" $(__fzfcmd))"
  else
    selected="$(fc -rl 1 | awk '{ cmd=$0; sub(/^[ \t]*[0-9]+\**[ \t]+/, "", cmd); if (!seen[cmd]++) print $0 }' |
      FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --scheme=history --bind=ctrl-r:toggle-sort --wrap-sign '\t↳ ' +m" $(__fzfcmd))"
  fi
  local ret=$?
  if [ -n "$selected" ]; then
    if [[ $(awk '{print $1; exit}' <<< "$selected") =~ ^[1-9][0-9]* ]]; then
      zle vi-fetch-history -n $MATCH
    else 
      LBUFFER="$selected"
    fi
  fi
  zle reset-prompt
  return $ret
}
zle -N fzf-history-widget
bindkey '^R' fzf-history-widget

# =============================================================================
# 5. Find in File (内容搜索)
# =============================================================================

# 命令行 fif 函数
fif() {
  if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
  rg --files-with-matches --no-messages "$1" | fzf --preview "highlight -O ansi -l {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
}

# --- CTRL-F : 交互式全文检索 ---
fzf-find-in-file-widget() {
  if ! (( $+commands[rg] )); then
    echo "\nError: ripgrep (rg) not installed."
    zle reset-prompt
    return 1
  fi
  local selected
  # 敲击键盘即时触发 ripgrep 重载搜索，按回车直接使用 vim 跳转到目标行
  FZF_DEFAULT_COMMAND='rg --files' $(__fzfcmd) \
    --ansi --disabled --delimiter ':' \
    --bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case {q} || true" \
    --bind 'enter:become(vim "{1}" $([ -n "{2}" ] && echo "+{2}"))' \
    --preview "rg --ignore-case --pretty --context 10 {q} {1} 2> /dev/null" \
    --header "Find in File Mode (Type to search content)" < /dev/tty  
  
  zle reset-prompt
}
zle -N fzf-find-in-file-widget
bindkey '^f' fzf-find-in-file-widget
