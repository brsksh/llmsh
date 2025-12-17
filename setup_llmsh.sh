#!/usr/bin/env bash
set -euo pipefail

if [ -t 1 ] && [ -z "${LLMSH_NO_COLOR:-}" ]; then
  COLOR_INFO="\033[36m"
  COLOR_WARN="\033[33m"
  COLOR_ERROR="\033[31m"
  COLOR_RESET="\033[0m"
else
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_RESET=""
fi

info() {
  echo -e "${COLOR_INFO}INFO:${COLOR_RESET} $*"
}

warn() {
  echo -e "${COLOR_WARN}WARNING:${COLOR_RESET} $*"
}

error() {
  echo -e "${COLOR_ERROR}ERROR:${COLOR_RESET} $*"
}

info "Starting llmsh setup"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/llmsh"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG_DIR="${CONFIG_HOME}/llmsh"
CONFIG_FILE="${CONFIG_DIR}/config.zsh"

NON_INTERACTIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive|--yes)
      NON_INTERACTIVE=1
      shift
      ;;
    *)
      warn "Unknown argument: $1"
      shift
      ;;
  esac
done

info "Repository directory: $REPO_DIR"
info "Target plugin directory: $TARGET_DIR"
info "Config file: $CONFIG_FILE"

if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" ]; then
  warn "Oh-My-Zsh custom directory not found at ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  warn "Make sure Oh-My-Zsh is installed and configured."
fi

info "Creating parent directory if necessary"
mkdir -p "$(dirname "$TARGET_DIR")"

if [ -e "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
  warn "$TARGET_DIR already exists and is not a symlink."
  warn "Skipping symlink creation. Please remove or rename it if you want to link this repository."
else
  if [ -L "$TARGET_DIR" ]; then
    info "Removing existing symlink at $TARGET_DIR"
    rm "$TARGET_DIR"
  fi
  info "Creating symlink from repository to plugin directory"
  ln -s "$REPO_DIR" "$TARGET_DIR"
fi

info "Checking required commands"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Command '$cmd' not found in PATH."
  else
    info "Found '$cmd'"
  fi
}

require_cmd zsh
require_cmd python3
require_cmd jq
require_cmd fzf
require_cmd curl

info "Checking Python dependency 'requests'"
if ! python3 - <<'EOF'
try:
    import requests  # noqa: F401
except ImportError:
    raise SystemExit(1)
EOF
then
  warn "Python package 'requests' is not installed for python3."
  warn "Install it with: pip install --user requests"
else
  info "Python package 'requests' is available"
fi

info "Making plugin scripts executable"
chmod +x "$REPO_DIR"/llmsh.plugin.zsh "$REPO_DIR"/llmsh.zsh "$REPO_DIR"/utils.zsh "$REPO_DIR"/llmsh_api.py 2>/dev/null || true

info "Writing configuration file"
mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ] && [ "$NON_INTERACTIVE" -eq 0 ]; then
  warn "Config file already exists at $CONFIG_FILE"
  read -r -p "Overwrite existing config? [y/N]: " answer
  case "$answer" in
    [Yy]*)
      info "Overwriting existing config file"
      ;;
    *)
      info "Keeping existing config file, no changes made to configuration"
      info "Setup complete."
      exit 0
      ;;
  esac
fi

prompt_default() {
  local var_name="$1"
  local prompt="$2"
  local default="$3"

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    local value="${!var_name:-$default}"
    printf '%s' "$value"
    return
  fi

  local current="${!var_name:-$default}"
  read -r -p "$prompt [$current]: " input
  if [ -z "$input" ]; then
    printf '%s' "$current"
  else
    printf '%s' "$input"
  fi
}

LLMSH_URL_VALUE="$(prompt_default LLMSH_URL 'LLMSH_URL (Ollama endpoint URL)' 'http://localhost:11434')"
LLMSH_MODEL_VALUE="$(prompt_default LLMSH_MODEL 'LLMSH_MODEL (model name)' 'llama3')"

if [ "$NON_INTERACTIVE" -eq 1 ]; then
  LLMSH_TOKEN_VALUE="${LLMSH_TOKEN:-}"
else
  read -r -p "LLMSH_TOKEN (Bearer token, leave empty if not needed) []: " LLMSH_TOKEN_VALUE
fi

LLMSH_HOTKEY_VALUE="$(prompt_default LLMSH_HOTKEY 'LLMSH_HOTKEY (ZLE keybinding)' '^o')"
LLMSH_COMMAND_COUNT_VALUE="$(prompt_default LLMSH_COMMAND_COUNT 'LLMSH_COMMAND_COUNT (number of suggestions)' '5')"
LLMSH_TIMEOUT_VALUE="$(prompt_default LLMSH_TIMEOUT 'LLMSH_TIMEOUT (API timeout in seconds)' '30')"

cat > "$CONFIG_FILE" <<EOF
export LLMSH_URL="${LLMSH_URL_VALUE}"
export LLMSH_MODEL="${LLMSH_MODEL_VALUE}"
export LLMSH_TOKEN="${LLMSH_TOKEN_VALUE}"
export LLMSH_HOTKEY="${LLMSH_HOTKEY_VALUE}"
export LLMSH_COMMAND_COUNT=${LLMSH_COMMAND_COUNT_VALUE}
export LLMSH_TIMEOUT=${LLMSH_TIMEOUT_VALUE}
EOF

info "Configuration written to $CONFIG_FILE"

info "Setup complete."
info "Add 'llmsh' to your plugins list in ~/.zshrc, for example:"
info "  plugins=(git llmsh)"
info "Then reload your shell configuration:"
info "  source ~/.zshrc"

