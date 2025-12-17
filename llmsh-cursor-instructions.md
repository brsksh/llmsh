# llmsh - Cursor Build Instructions

## Projekt-Info

- **Name:** llmsh
- **Description:** LLM-powered command suggestions for zsh
- **License:** MIT
- **Repo:** github.com/[username]/llmsh

## Zweck

Ein Oh-My-Zsh Plugin, das natürliche Sprache in Shell-Befehle übersetzt. 
Nutzt eine **Remote Ollama API** mit **Bearer Token** Authentifizierung.

**Beispiel:**
1. User tippt: `find large files over 100mb`
2. Drückt `Ctrl+O`
3. LLM gibt Vorschläge wie `find . -size +100M -type f`
4. User wählt mit fzf aus

---

## Dateistruktur

```
llmsh/
├── llmsh.plugin.zsh      # Oh-My-Zsh Plugin Wrapper
├── llmsh.zsh             # Hauptlogik + Keybinding
├── utils.zsh             # Helper-Funktionen
├── llmsh_api.py          # Python Script für API-Calls
├── README.md             # Dokumentation
└── LICENSE               # MIT License
```

---

## Dateien

### 1. `llmsh.plugin.zsh`

```zsh
0=${(%):-%N}
source ${0:A:h}/llmsh.zsh
```

---

### 2. `llmsh.zsh`

```zsh
#!/usr/bin/env zsh

# ============================================
# llmsh - LLM-powered command suggestions
# ============================================

# Default configuration
(( ! ${+LLMSH_HOTKEY} )) && typeset -g LLMSH_HOTKEY='^o'
(( ! ${+LLMSH_MODEL} )) && typeset -g LLMSH_MODEL='llama3'
(( ! ${+LLMSH_COMMAND_COUNT} )) && typeset -g LLMSH_COMMAND_COUNT='5'
(( ! ${+LLMSH_URL} )) && typeset -g LLMSH_URL='http://localhost:11434'
(( ! ${+LLMSH_TOKEN} )) && typeset -g LLMSH_TOKEN=''
(( ! ${+LLMSH_TIMEOUT} )) && typeset -g LLMSH_TIMEOUT='30'
(( ! ${+LLMSH_PYTHON} )) && typeset -g LLMSH_PYTHON='python3'

# Source utilities
source "${0:A:h}/utils.zsh"

# Log file
LLMSH_LOG_FILE="/tmp/llmsh_debug.log"

log_debug() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" >> "$LLMSH_LOG_FILE" 2>&1
}

validate_requirements() {
    check_command "jq" || return 1
    check_command "fzf" || return 1
    check_command "curl" || return 1
    check_command "$LLMSH_PYTHON" || return 1
    check_ollama_reachable || return 1
    return 0
}

llmsh_suggest() {
    setopt extendedglob
    
    validate_requirements
    if [ $? -eq 1 ]; then
        zle reset-prompt
        return 1
    fi
    
    local user_query="$BUFFER"
    
    if [ -z "$user_query" ]; then
        echo ""
        echo "💡 Type a description first, then press ${LLMSH_HOTKEY}"
        zle reset-prompt
        return 0
    fi
    
    zle end-of-line
    zle reset-prompt
    print
    print -u1 "🤖 Asking LLM..."
    
    # Export env vars for Python script
    export LLMSH_URL
    export LLMSH_MODEL
    export LLMSH_TOKEN
    export LLMSH_COMMAND_COUNT
    export LLMSH_TIMEOUT
    
    local plugin_dir="${0:A:h}"
    local commands=$("$LLMSH_PYTHON" "$plugin_dir/llmsh_api.py" "$user_query" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$commands" ]; then
        log_debug "Failed to get commands for: $user_query"
        echo "❌ No commands found. Check /tmp/llmsh_debug.log"
        zle reset-prompt
        return 0
    fi
    
    # Clear "Asking LLM..." line
    tput cuu 1
    tput el
    
    # Let user select with fzf
    local selected=$(echo "$commands" | fzf --ansi --height=~10 --cycle --prompt="Select command: ")
    
    if [ -n "$selected" ]; then
        BUFFER="$selected"
        CURSOR=${#BUFFER}
        log_debug "Selected: $selected"
    fi
    
    zle reset-prompt
    return 0
}

# Register widget and keybinding
autoload -U llmsh_suggest
zle -N llmsh_suggest
bindkey "$LLMSH_HOTKEY" llmsh_suggest
```

---

### 3. `utils.zsh`

```zsh
#!/usr/bin/env zsh

# ============================================
# llmsh - Utility functions
# ============================================

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "mac" ;;
        *)       echo "unknown" ;;
    esac
}

get_install_cmd() {
    local os=$(detect_os)
    case "$os" in
        "linux")
            if command -v apt-get &> /dev/null; then
                echo "sudo apt install"
            elif command -v dnf &> /dev/null; then
                echo "sudo dnf install"
            elif command -v pacman &> /dev/null; then
                echo "sudo pacman -S"
            else
                echo "your package manager"
            fi
            ;;
        "mac")
            echo "brew install"
            ;;
        *)
            echo "your package manager"
            ;;
    esac
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        local install_cmd=$(get_install_cmd)
        echo "❌ $cmd not found! Install with: $install_cmd $cmd"
        return 1
    fi
    return 0
}

check_ollama_reachable() {
    local auth_header=""
    if [ -n "$LLMSH_TOKEN" ]; then
        auth_header="Authorization: Bearer $LLMSH_TOKEN"
    fi
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -H "$auth_header" \
        "${LLMSH_URL}/api/tags" 2>/dev/null)
    
    if [[ ! "$http_code" =~ ^(200|401|403)$ ]]; then
        echo "❌ Cannot reach Ollama at ${LLMSH_URL} (HTTP: $http_code)"
        return 1
    fi
    return 0
}
```

---

### 4. `llmsh_api.py`

```python
#!/usr/bin/env python3
"""
llmsh - API client for Ollama-compatible endpoints
Supports Bearer token authentication for remote instances
"""

import json
import logging
import os
import re
import sys
import warnings

warnings.filterwarnings("ignore")

import requests

# Logging setup
LOG_FILE = "/tmp/llmsh_debug.log"
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


def log(message, data=None):
    if data:
        logging.debug(f"{message}\n{data}\n{'='*40}")
    else:
        logging.debug(message)


def query_llm(user_query: str) -> list[str]:
    """Send query to Ollama API and return command suggestions."""
    
    url = os.environ.get("LLMSH_URL", "http://localhost:11434")
    model = os.environ.get("LLMSH_MODEL", "llama3")
    token = os.environ.get("LLMSH_TOKEN", "")
    count = os.environ.get("LLMSH_COMMAND_COUNT", "5")
    timeout = int(os.environ.get("LLMSH_TIMEOUT", "30"))

    prompt = f"""Generate {count} shell commands for this task: {user_query}

Return ONLY a JSON object with a "commands" key containing a list of command strings.
No explanations, no markdown, just valid JSON.

Example response:
{{"commands": ["ls -la", "find . -type f", "du -sh *"]}}"""

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
    }

    log(f"Query: {user_query}")
    log(f"URL: {url}, Model: {model}")

    try:
        response = requests.post(
            f"{url}/api/chat",
            headers=headers,
            json=payload,
            timeout=timeout
        )
        response.raise_for_status()
        data = response.json()
        
        content = data.get("message", {}).get("content", "")
        log("Response content:", content)
        
        if content:
            return parse_commands(content)
        
        return []

    except requests.exceptions.Timeout:
        log("Request timed out")
        return []
    except requests.exceptions.RequestException as e:
        log(f"Request error: {e}")
        return []
    except Exception as e:
        log(f"Unexpected error: {e}")
        return []


def parse_commands(content: str) -> list[str]:
    """Extract commands from LLM response."""
    
    # Try to extract JSON from markdown code block
    md_match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", content)
    if md_match:
        content = md_match.group(1).strip()
    
    # Try to find JSON object
    json_match = re.search(r'\{[^{}]*"commands"\s*:\s*\[.*?\][^{}]*\}', content, re.DOTALL)
    if json_match:
        content = json_match.group(0)
    
    try:
        data = json.loads(content)
        commands = data.get("commands", [])
        
        if isinstance(commands, list):
            return [str(cmd).strip() for cmd in commands if cmd]
    
    except json.JSONDecodeError:
        log("JSON parse failed, trying line extraction")
        
        # Fallback: extract lines that look like commands
        lines = []
        for line in content.split("\n"):
            line = line.strip()
            if not line:
                continue
            # Skip common non-command patterns
            if line.startswith(("#", "{", "}", "[", "]", '"', "//")):
                continue
            # Remove list prefixes
            line = re.sub(r'^[\d]+[\.\)]\s*', '', line)
            line = re.sub(r'^[-*]\s*', '', line)
            line = line.strip('`"\'')
            if line:
                lines.append(line)
        
        if lines:
            return lines
    
    return []


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: llmsh_api.py <query>", file=sys.stderr)
        sys.exit(1)
    
    commands = query_llm(sys.argv[1])
    
    if not commands:
        sys.exit(1)
    
    for cmd in commands:
        print(cmd)
```

---

### 5. `README.md`

```markdown
# llmsh

LLM-powered command suggestions for zsh.

Describe what you want to do in natural language, press `Ctrl+O`, and get shell commands suggested by your LLM.

## Features

- 🌐 Works with remote Ollama instances
- 🔐 Bearer token authentication support
- ⚡ Fast fuzzy selection with fzf
- 🎯 Configurable model, URL, and hotkey

## Requirements

- zsh + Oh-My-Zsh
- Python 3.8+
- fzf
- jq
- curl

## Installation

```bash
# Clone to Oh-My-Zsh plugins
git clone https://github.com/[username]/llmsh.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/llmsh

# Install Python dependency
pip install requests

# Add to ~/.zshrc plugins
plugins=(... llmsh)
```

## Configuration

Add to your `~/.zshrc`:

```bash
export LLMSH_URL="https://your-ollama-instance.com"
export LLMSH_MODEL="llama3"
export LLMSH_TOKEN="your-bearer-token"  # optional
export LLMSH_HOTKEY="^o"                 # Ctrl+O (default)
export LLMSH_COMMAND_COUNT=5             # suggestions count
export LLMSH_TIMEOUT=30                  # API timeout in seconds
```

## Usage

1. Type a description: `find all python files modified today`
2. Press `Ctrl+O`
3. Select a command with fzf
4. Press Enter to insert

## Debugging

```bash
tail -f /tmp/llmsh_debug.log
```

## License

MIT
```

---

### 6. `LICENSE`

```
MIT License

Copyright (c) 2024 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Testen

```bash
# Plugin laden
source ~/.zshrc

# Manuell testen
export LLMSH_URL="https://deine-url.com"
export LLMSH_MODEL="dein-modell"
export LLMSH_TOKEN="dein-token"
python3 ~/.oh-my-zsh/custom/plugins/llmsh/llmsh_api.py "list files"

# Im Terminal: etwas tippen + Ctrl+O
```

---

## Hinweise für Cursor

1. Erstelle alle 6 Dateien im Repo-Root
2. Python-Script braucht `requests` als einzige Dependency
3. Alle zsh-Dateien müssen executable sein (`chmod +x`)
4. [username] in README und LICENSE ersetzen
