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


def parse_commands(content: str) -> list[str]:
    """Extract commands from LLM response."""

    # Try to extract JSON from markdown code block
    md_match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", content)
    if md_match:
        content = md_match.group(1).strip()

    # Try to find JSON object
    json_match = re.search(
        r'\{[^{}]*"commands"\s*:\s*\[.*?\][^{}]*\}', content, re.DOTALL
    )
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
        lines: list[str] = []
        for line in content.split("\n"):
            line = line.strip()
            if not line:
                continue
            # Skip common non-command patterns
            if line.startswith(("#", "{", "}", "[", "]", '"', "//")):
                continue
            # Remove list prefixes
            line = re.sub(r"^[\d]+[\.\)]\s*", "", line)
            line = re.sub(r"^[-*]\s*", "", line)
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


