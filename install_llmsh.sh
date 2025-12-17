#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/brsksh/llmsh.git"
PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
TARGET_DIR="${PLUGINS_DIR}/llmsh"
ZSHRC="${HOME}/.zshrc"

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

info "Installing llmsh"

if ! command -v git >/dev/null 2>&1; then
  error "git is required but not installed."
  exit 1
fi

mkdir -p "$PLUGINS_DIR"

if [ -d "$TARGET_DIR/.git" ]; then
  info "Existing llmsh clone found at $TARGET_DIR"
  info "Updating repository (git pull --ff-only)"
  if ! git -C "$TARGET_DIR" pull --ff-only; then
    warn "git pull failed, continuing with existing clone"
  fi
else
  info "Cloning llmsh into $TARGET_DIR"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

info "Running setup_llmsh.sh"
(
  cd "$TARGET_DIR"
  chmod +x setup_llmsh.sh || true
  ./setup_llmsh.sh
)

if [ ! -f "$ZSHRC" ]; then
  warn "$ZSHRC not found. Please add 'llmsh' to your plugins list manually."
  exit 0
fi

if grep -qE '^\s*plugins=.*llmsh' "$ZSHRC"; then
  info "llmsh is already present in your plugins list in $ZSHRC"
  exit 0
fi

echo
read -r -p "Add 'llmsh' to your plugins list in $ZSHRC? [y/N]: " answer
case "$answer" in
  [Yy]*)
    info "Updating plugins list in $ZSHRC"
    if ! command -v python3 >/dev/null 2>&1; then
      warn "python3 not found. Cannot update $ZSHRC automatically."
      warn "Please add 'llmsh' manually to your plugins list, e.g.: plugins=(... llmsh)"
      exit 0
    fi

    python3 - "$ZSHRC" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

pattern = re.compile(r'^(\s*plugins=\()([^)]*)(\).*)$')
updated = False

for i, line in enumerate(lines):
    m = pattern.match(line)
    if m:
        before, inner, after = m.groups()
        if "llmsh" in inner:
            updated = True
            break
        inner = inner.rstrip() + " llmsh"
        lines[i] = f"{before}{inner}{after}\n"
        updated = True
        break

if not updated:
    lines.append("\n# Enable llmsh plugin\nplugins=(llmsh)\n")

with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PY

    info "Done. Reload your shell with: source \"$ZSHRC\""
    ;;
  *)
    info "Skipped modifying $ZSHRC. Please add 'llmsh' to your plugins list manually."
    ;;
esac

info "Installation finished."


