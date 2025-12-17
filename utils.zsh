#!/usr/bin/env zsh

# ============================================
# llmsh - Utility functions
# ============================================

# Color configuration
if [ -t 1 ] && [ -z "$LLMSH_NO_COLOR" ]; then
    LLMSH_COLOR_INFO=$'%F{cyan}'
    LLMSH_COLOR_WARN=$'%F{yellow}'
    LLMSH_COLOR_ERROR=$'%F{red}'
    LLMSH_COLOR_RESET=$'%f'
else
    LLMSH_COLOR_INFO=""
    LLMSH_COLOR_WARN=""
    LLMSH_COLOR_ERROR=""
    LLMSH_COLOR_RESET=""
fi

llmsh_info() {
    print -P "${LLMSH_COLOR_INFO}INFO:${LLMSH_COLOR_RESET} $*"
}

llmsh_warn() {
    print -P "${LLMSH_COLOR_WARN}WARNING:${LLMSH_COLOR_RESET} $*"
}

llmsh_error() {
    print -P "${LLMSH_COLOR_ERROR}ERROR:${LLMSH_COLOR_RESET} $*"
}

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
        llmsh_error "$cmd not found. Install with: $install_cmd $cmd"
        return 1
    fi
    return 0
}

check_ollama_reachable() {
    local auth_header=""
    if [ -n "$LLMSH_TOKEN" ]; then
        auth_header="Authorization: Bearer $LLMSH_TOKEN"
    fi

    local http_code
    local curl_output
    curl_output=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        -H "$auth_header" \
        "${LLMSH_URL}/api/tags" 2>&1)
    http_code=$(echo "$curl_output" | tail -n 1)

    if [[ ! "$http_code" =~ ^[0-9]+$ ]] || [[ ! "$http_code" =~ ^(200|401|403)$ ]]; then
        if [[ ! "$http_code" =~ ^[0-9]+$ ]]; then
            llmsh_error "Cannot reach Ollama at ${LLMSH_URL} (curl error: $curl_output)"
        else
            llmsh_error "Cannot reach Ollama at ${LLMSH_URL} (HTTP: $http_code)"
        fi
        return 1
    fi
    return 0
}

