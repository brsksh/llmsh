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


def query_llm(user_query: str) -> list[tuple[str, str]]:
    """Send query to Ollama API and return command suggestions with descriptions."""

    url = os.environ.get("LLMSH_URL", "http://localhost:11434")
    model = os.environ.get("LLMSH_MODEL", "llama3")
    token = (os.environ.get("LLMSH_TOKEN", "") or "").strip()
    count = os.environ.get("LLMSH_COMMAND_COUNT", "5")
    timeout = int(os.environ.get("LLMSH_TIMEOUT", "30"))

    prompt = f"""Generate {count} shell commands for this task: {user_query}

Return ONLY a JSON object with a "commands" key containing a list of objects.
Each object must have "cmd" (the shell command) and "description" (short one-line explanation).
No explanations outside JSON, no markdown, just valid JSON.

Example response:
{{"commands": [{{"cmd": "ls -la", "description": "List all files with details"}}, {{"cmd": "find . -type f", "description": "Find regular files in current tree"}}]}}"""

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
            timeout=timeout,
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
    except requests.exceptions.RequestException as exc:
        log(f"Request error: {exc}")
        return []
    except Exception as exc:  # pylint: disable=broad-except
        log(f"Unexpected error: {exc}")
        return []


def parse_commands(content: str) -> list[tuple[str, str]]:
    """Extract commands (and optional descriptions) from LLM response."""

    # Try to extract JSON from markdown code block
    md_match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", content)
    if md_match:
        content = md_match.group(1).strip()

    # Extract outermost {...} so nested objects (cmd/description) are included
    start = content.find('{"commands"')
    if start == -1:
        start = content.find('{')
    if start != -1:
        depth = 0
        for i in range(start, len(content)):
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
                if depth == 0:
                    content = content[start : i + 1]
                    break

    try:
        data = json.loads(content)
        commands = data.get("commands", [])

        if not isinstance(commands, list):
            return []

        result: list[tuple[str, str]] = []
        for item in commands:
            if isinstance(item, dict):
                cmd = (item.get("cmd") or "").strip()
                desc = (item.get("description") or "").strip()
                if cmd:
                    result.append((cmd, desc))
            elif isinstance(item, str) and item.strip():
                # Legacy: plain list of command strings
                result.append((item.strip(), ""))
        return result

    except json.JSONDecodeError:
        log("JSON parse failed, trying line extraction")

        # Fallback: extract lines that look like commands (no description)
        lines: list[tuple[str, str]] = []
        for line in content.split("\n"):
            line = line.strip()
            if not line:
                continue
            if line.startswith(("#", "{", "}", "[", "]", '"', "//")):
                continue
            line = re.sub(r"^[\d]+[\.\)]\s*", "", line)
            line = re.sub(r"^[-*]\s*", "", line)
            line = line.strip('`"\'')
            if line:
                lines.append((line, ""))

        return lines

    return []


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: llmsh_api.py <query>", file=sys.stderr)
        sys.exit(1)

    suggestions = query_llm(sys.argv[1])

    if not suggestions:
        sys.exit(1)

    for cmd, description in suggestions:
        print(cmd + "\t" + description)


