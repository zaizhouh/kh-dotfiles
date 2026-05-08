#!/usr/bin/env bash

set -euo pipefail

if [[ -t 1 ]]; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  YELLOW="$(tput setaf 3 2>/dev/null || true)"
  RED="$(tput setaf 1 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
else
  BOLD=""
  DIM=""
  GREEN=""
  YELLOW=""
  RED=""
  RESET=""
fi

log_step() {
  printf "\n%s==>%s %s\n" "$BOLD" "$RESET" "$1"
}

log_ok() {
  printf "  %s[ok]%s %s\n" "$GREEN" "$RESET" "$1"
}

log_skip() {
  printf "  %s[skip]%s %s\n" "$DIM" "$RESET" "$1"
}

log_warn() {
  printf "  %s[warn]%s %s\n" "$YELLOW" "$RESET" "$1"
}

die() {
  printf "\n%sError:%s %s\n" "$RED" "$RESET" "$1" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer currently supports macOS only."
}

require_homebrew() {
  has_cmd brew || die "Homebrew is required. Install it first from https://brew.sh, then re-run this script."
  eval "$("$(command -v brew)" shellenv)"
  log_ok "Homebrew found at $(command -v brew)"
}

brew_install_formulae() {
  local formulae=(
    ccat
    fd
    fzf
    eza
    tree
    bat
    highlight
    ripgrep
    tmux
    yazi
    kubectl
  )

  log_step "Installing Homebrew formulae"
  for formula in "${formulae[@]}"; do
    if brew list --formula "$formula" >/dev/null 2>&1; then
      log_skip "$formula already installed"
    else
      log_warn "Installing $formula"
      brew install "$formula"
      log_ok "$formula installed"
    fi
  done
}

brew_install_casks() {
  local casks=(
    ghostty
    font-jetbrains-mono-nerd-font
    orbstack
  )

  log_step "Installing Homebrew casks"
  for cask in "${casks[@]}"; do
    if brew list --cask "$cask" >/dev/null 2>&1; then
      log_skip "$cask already installed"
    else
      log_warn "Installing $cask"
      brew install --cask "$cask"
      log_ok "$cask installed"
    fi
  done
}

install_zimfw() {
  local zim_home="${ZDOTDIR:-$HOME}/.zim"
  local zim_config="${ZIM_CONFIG_FILE:-${ZDOTDIR:-$HOME}/.zimrc}"
  local zimfw="$zim_home/zimfw.zsh"

  log_step "Setting up Zim"
  if [[ -f "$zimfw" ]]; then
    log_skip "zimfw already exists"
  else
    mkdir -p "$zim_home"
    curl -fsSL -o "$zimfw" "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh"
    log_ok "zimfw downloaded"
  fi

  ZIM_HOME="$zim_home" ZIM_CONFIG_FILE="$zim_config" zsh "$zimfw" install
  ZIM_HOME="$zim_home" ZIM_CONFIG_FILE="$zim_config" zsh "$zimfw" init
  log_ok "Zim modules are installed"
}

install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"

  log_step "Setting up tmux plugin manager"
  if [[ -d "$tpm_dir/.git" ]]; then
    log_skip "TPM already installed"
  else
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    log_ok "TPM cloned"
  fi

  "$tpm_dir/bin/install_plugins" || log_warn "TPM plugin install finished with warnings. Re-open tmux and press prefix + I if needed."
}

install_nvm() {
  export NVM_DIR="$HOME/.nvm"

  log_step "Setting up nvm"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log_skip "nvm already installed"
  else
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    log_ok "nvm installed"
  fi

  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  if has_cmd nvm; then
    nvm install --lts
    nvm alias default 'lts/*'
    log_ok "Node LTS is installed and set as default"
  else
    log_warn "nvm is not available in this shell. Open a new terminal and run: nvm install --lts"
  fi
}

install_rustup() {
  log_step "Setting up Rust"
  if [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    log_skip "rustup already installed"
    "$HOME/.cargo/bin/rustup" update
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    log_ok "rustup installed"
  fi
}

print_summary() {
  log_step "Done"
  log_ok "Dotfiles dependencies are ready."
  log_warn "Restart your terminal so zsh, nvm, Rust, and Homebrew shell environment changes are picked up."
}

main() {
  require_macos
  log_step "Checking prerequisites"
  require_homebrew

  brew_install_formulae
  brew_install_casks
  install_zimfw
  install_tpm
  install_nvm
  install_rustup
  print_summary
}

main "$@"
