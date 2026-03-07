# llmsh

LLM-powered command suggestions for zsh.  
Type what you want to do in natural language, press `Ctrl+O`, and insert ready-to-run shell commands into your prompt.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Updating](#updating)
- [Usage](#usage)
- [Configuration](#configuration)
- [Debugging](#debugging)
- [License](#license)

---

## Features

- **Natural language → shell commands**: Describe your task, get concrete shell commands back.
- **Ollama-compatible backend**: Works with local and remote Ollama-compatible APIs.
- **Bearer token support**: Use `LLMSH_TOKEN` for remote, authenticated instances.
- **fzf integration**: Fuzzy-select from suggestions; each command can show a short description in the picker.
- **Configurable**: Model, endpoint, hotkey, timeout and number of suggestions are all tunable.
- **Polished CLI UX**: Colored INFO/WARNING/ERROR messages and a small spinner while waiting for the LLM.
- **Clean config**: Uses XDG config (`~/.config/llmsh/config.zsh`) instead of polluting `~/.zshrc`.

---

## Requirements

- **macOS** (only supported platform)
- zsh + Oh-My-Zsh
- python3 (3.8+)
- fzf
- jq
- curl
- Python package: `requests`

---

## Installation

llmsh supports **macOS only**. On other platforms the install and setup scripts will exit with an error.

### One-line install (recommended)

Run the installer script, which will clone the repository, run the setup, and optionally update your `~/.zshrc`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/brsksh/llmsh/main/install_llmsh.sh)
```

### Manual install

Clone `llmsh` into your Oh-My-Zsh custom plugins directory and install the Python dependency:

```bash
git clone https://github.com/brsksh/llmsh.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/llmsh

pip install --user requests
```

Enable the plugin in your `~/.zshrc`:

```bash
plugins=(... llmsh)
```

Then reload your shell:

```bash
source ~/.zshrc
```

---

## Updating

- **From a shell where llmsh is loaded:** run `llmsh_update`. This runs `git pull --ff-only` in the plugin directory and tells you to reload the shell.
- **From a fresh clone or any terminal:** run the install script again from the repo (it will `git pull` if the plugin dir already exists):  
  `bash <(curl -fsSL https://raw.githubusercontent.com/brsksh/llmsh/main/install_llmsh.sh)`
- If the plugin is a **symlink** to your own clone, run `git pull` in that clone to update.

---

## Usage

1. After installation, run the interactive setup to configure `llmsh`:

   ```bash
   ./setup_llmsh.sh
   ```

2. Type a description in your shell, for example:

   ```text
   find all large files over 500MB
   ```

3. Press `Ctrl+O` (default hotkey) to trigger command suggestions.
4. Wait for the LLM to respond (a spinner indicates progress).
5. Select a command in the picker (fzf shows the command and a short description). Press Enter to insert the command into your prompt.

---

## Configuration

Configuration is stored in `${XDG_CONFIG_HOME:-$HOME/.config}/llmsh/config.zsh`. Create or update it by running:

```bash
./setup_llmsh.sh
```

The script prompts for:

- `LLMSH_URL` (Ollama endpoint URL)
- `LLMSH_MODEL` (model name, e.g. `llama3`)
- `LLMSH_TOKEN` (optional bearer token)
- `LLMSH_HOTKEY` (ZLE keybinding, e.g. `^o`)
- `LLMSH_COMMAND_COUNT` (number of suggestions)
- `LLMSH_TIMEOUT` (API timeout in seconds)

For non-interactive setup (e.g. in dotfiles):

```bash
LLMSH_URL="https://your-ollama-instance.com" \
LLMSH_MODEL="llama3" \
LLMSH_TOKEN="your-bearer-token" \
LLMSH_HOTKEY="^o" \
LLMSH_COMMAND_COUNT=5 \
LLMSH_TIMEOUT=30 \
./setup_llmsh.sh --non-interactive
```

### Optional: Token from HashiCorp Vault (macOS)

During interactive setup you can choose to use **HashiCorp Vault** for `LLMSH_TOKEN` (auth on demand). The setup then writes `~/.config/llmsh/vault.zsh`, which defines `llmsh_auth` and a wrapper widget that fetches the token from Vault when needed.

1. Run `./setup_llmsh.sh`, leave `LLMSH_TOKEN` empty, and answer **y** to “Use HashiCorp Vault for LLMSH_TOKEN?”.
2. Add to the **end** of your `~/.zshrc`:

   ```bash
   source ~/.config/llmsh/vault.zsh
   ```

3. Reload your shell. The first time you press the llmsh hotkey, `llmsh_auth` will run (e.g. `vault login -method=oidc` if needed) and set `LLMSH_TOKEN` from Vault. `VAULT_ADDR` is set inside `vault.zsh`; adjust the default in the file or set it before sourcing if you use another Vault server.

For non-interactive setup with Vault:

```bash
LLMSH_USE_VAULT=1 \
VAULT_ADDR="https://vault.example.com" \
LLMSH_URL="https://..." \
LLMSH_MODEL="llama3" \
./setup_llmsh.sh --non-interactive
```

### CLI appearance

- INFO, WARNING and ERROR messages are colorized by default. Disable with `export LLMSH_NO_COLOR=1`.
- A spinner is shown during LLM calls. Disable with `export LLMSH_NO_SPINNER=1`.

---

## Debugging

`llmsh` writes detailed debug logs to:

```bash
/tmp/llmsh_debug.log
```

To inspect logs in real time:

```bash
tail -f /tmp/llmsh_debug.log
```

You can also test the Python client directly:

```bash
export LLMSH_URL="https://your-url.com"
export LLMSH_MODEL="your-model"
export LLMSH_TOKEN="your-token"

python3 ~/.oh-my-zsh/custom/plugins/llmsh/llmsh_api.py "list files"
```

---

---

## License

[MIT](LICENSE)


