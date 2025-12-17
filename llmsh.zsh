#!/usr/bin/env zsh

 # ============================================
 # llmsh - LLM-powered command suggestions
 # ============================================

 # Store plugin directory at load time (before ZLE context)
 typeset -g LLMSH_PLUGIN_DIR="${0:A:h}"

 # Source utilities first
 source "${LLMSH_PLUGIN_DIR}/utils.zsh"

 # Load external configuration if present
 _llmsh_load_config() {
     local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
     local config_file="${config_home}/llmsh/config.zsh"

     if [ -f "$config_file" ]; then
         source "$config_file"
     fi
 }

 _llmsh_load_config

 # Default configuration (only if not set by environment or config file)
 (( ! ${+LLMSH_HOTKEY} )) && typeset -g LLMSH_HOTKEY='^o'
 (( ! ${+LLMSH_MODEL} )) && typeset -g LLMSH_MODEL='llama3'
 (( ! ${+LLMSH_COMMAND_COUNT} )) && typeset -g LLMSH_COMMAND_COUNT='5'
 (( ! ${+LLMSH_URL} )) && typeset -g LLMSH_URL='http://localhost:11434'
 (( ! ${+LLMSH_TOKEN} )) && typeset -g LLMSH_TOKEN=''
 (( ! ${+LLMSH_TIMEOUT} )) && typeset -g LLMSH_TIMEOUT='30'
 (( ! ${+LLMSH_PYTHON} )) && typeset -g LLMSH_PYTHON='python3'

 # Log file
 LLMSH_LOG_FILE="/tmp/llmsh_debug.log"

log_debug() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" >> "$LLMSH_LOG_FILE" 2>&1
}

# Spinner state
typeset -g _llmsh_spinner_pid=""

_llmsh_spinner_start() {
    if [ -n "$LLMSH_NO_SPINNER" ]; then
        return
    fi

    # Use ANSI colors for spinner (with $'...' syntax for escape sequences)
    local color_info=""
    local color_reset=""
    if [ -t 2 ] && [ -z "$LLMSH_NO_COLOR" ]; then
        color_info=$'\033[36m'
        color_reset=$'\033[0m'
    fi

    local message="Querying LLM..."
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local frame_count=${#frames[@]}

    # Run spinner in subshell with trap to handle termination cleanly
    (
        # Ignore SIGINT and SIGTERM in the spinner process to prevent termination messages
        trap '' INT TERM
        # Redirect only stdout to /dev/null, keep stderr for spinner output
        exec >/dev/null
        local i=0
        while :; do
            local frame_idx=$((i % frame_count + 1))
            local frame="${frames[$frame_idx]}"
            printf "\r%s%sINFO:%s %s %s" "$color_info" "$frame" "$color_reset" "$message" "$color_reset" >&2
            sleep 0.1
            i=$((i + 1))
        done
    ) &!
    _llmsh_spinner_pid=$!
}

_llmsh_spinner_stop() {
    if [ -z "$_llmsh_spinner_pid" ]; then
        return
    fi

    # Kill the spinner process if it's still running
    if kill -0 "$_llmsh_spinner_pid" 2>/dev/null; then
        # Send TERM signal
        kill "$_llmsh_spinner_pid" 2>/dev/null || true
        # Wait briefly for graceful termination
        local count=0
        while [ $count -lt 10 ] && kill -0 "$_llmsh_spinner_pid" 2>/dev/null; do
            sleep 0.01
            count=$((count + 1))
        done
        # Force kill if still running (but suppress error messages)
        if kill -0 "$_llmsh_spinner_pid" 2>/dev/null; then
            kill -9 "$_llmsh_spinner_pid" 2>/dev/null || true
        fi
        # Wait for process to fully terminate (suppress all output)
        wait "$_llmsh_spinner_pid" 2>/dev/null || true
    fi
    _llmsh_spinner_pid=""

    # Clear the spinner line
    printf $'\r\033[K' >&2 2>/dev/null || true
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

    log_debug "llmsh_suggest called with BUFFER: $BUFFER"

    if ! validate_requirements; then
        log_debug "validate_requirements failed"
        zle reset-prompt
        return 1
    fi

    local user_query="$BUFFER"

    if [ -z "$user_query" ]; then
        echo ""
        llmsh_info "Type a description first, then press ${LLMSH_HOTKEY}"
        zle reset-prompt
        return 0
    fi

    zle end-of-line
    zle reset-prompt
    print

    # Start spinner
    _llmsh_spinner_start

    # Export env vars for Python script
    export LLMSH_URL
    export LLMSH_MODEL
    export LLMSH_TOKEN
    export LLMSH_COMMAND_COUNT
    export LLMSH_TIMEOUT

    local commands
    local exit_code=0

    # Always stop spinner, even on errors
    {
        commands=$("$LLMSH_PYTHON" "${LLMSH_PLUGIN_DIR}/llmsh_api.py" "$user_query" 2>&1)
        exit_code=$?
    } always {
        _llmsh_spinner_stop
    }

    log_debug "Python exit code: $exit_code"
    log_debug "Python output: $commands"

    if [ $exit_code -ne 0 ] || [ -z "$commands" ]; then
        log_debug "No commands returned for: $user_query (exit_code: $exit_code)"
        if [ -n "$commands" ]; then
            log_debug "Python output (may contain errors): $commands"
        fi
        llmsh_error "No commands received from LLM. Check /tmp/llmsh_debug.log"
        zle reset-prompt
        return 0
    fi

    # Filter out empty lines and potential error messages
    local clean_commands=$(echo "$commands" | grep -v "^$" | grep -v "^Usage:" | grep -v "^Error:")

    if [ -z "$clean_commands" ]; then
        log_debug "No clean commands after filtering"
        llmsh_error "No valid commands received from LLM. Check /tmp/llmsh_debug.log"
        zle reset-prompt
        return 0
    fi

    # Let user select with fzf
    local selected=$(echo "$clean_commands" | fzf --ansi --height=~10 --cycle --prompt="Select command: " 2>&1)
    local fzf_exit=$?

    if [ $fzf_exit -ne 0 ] && [ $fzf_exit -ne 130 ]; then
        log_debug "fzf exited with code: $fzf_exit"
    fi

    if [ -n "$selected" ]; then
        BUFFER="$selected"
        CURSOR=${#BUFFER}
        log_debug "Selected: $selected"
        # Optional: Show brief confirmation (can be disabled if too verbose)
        if [ -z "$LLMSH_NO_SPINNER" ]; then
            # Brief visual feedback - command is now in buffer
        fi
    fi

    zle reset-prompt
    return 0
}

# Register widget and keybinding
autoload -U llmsh_suggest
zle -N llmsh_suggest
bindkey "$LLMSH_HOTKEY" llmsh_suggest


