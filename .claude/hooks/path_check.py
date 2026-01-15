#!/usr/bin/env python3
"""Claude Code PreToolUse hook to validate shell commands stay within sandbox.

This hook checks that all file paths in Bash commands resolve within the
project directory or /tmp. It handles redirects, flag-embedded paths,
tilde expansion, environment variables, and nested subcommands.

Usage:
    Configure in ~/.claude/settings.json:
    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "/path/to/path_check.py"}]
          }
        ]
      }
    }
"""

import json
import os
import re
import shlex
import sys
from pathlib import Path
from typing import Iterator

TMP = Path("/tmp").resolve()
CLAUDE_HOME = Path("~/.claude").expanduser().resolve()

_DEV_OK = frozenset({
    "/dev/null", "/dev/zero", "/dev/random", "/dev/urandom",
    "/dev/stdin", "/dev/stdout", "/dev/stderr",
    "/dev/fd/0", "/dev/fd/1", "/dev/fd/2",
    "/dev/fd0", "/dev/fd1", "/dev/fd2",
    "/dev/tty", "/dev/ptmx",
})

# Redirect operators - longer patterns first to avoid partial matches.
_REDIR_OP = r"(?:>>|<>|>&|&>|>|<)"
REDIR = re.compile(rf"(?:\d+)?{_REDIR_OP}\s*([^\s;&|]+)")
_REDIRECT_PREFIX = re.compile(rf"^(?:\d+)?{_REDIR_OP}")

# Flag patterns that embed absolute paths: -I/path, --prefix=/path, etc.
_FLAG_WITH_PATH = re.compile(r"^--?[a-zA-Z][-a-zA-Z0-9_]*[=:]?(.+)$")


def _expand(p: str) -> str:
    """Expand ~ and environment variables in a path.

    Args:
        p: Path string potentially containing ``~`` or ``$VAR``.

    Returns:
        Expanded path string.
    """
    return os.path.expandvars(os.path.expanduser(p))


def _extract_paths(token: str) -> Iterator[str]:
    """Yield potential filesystem paths from a shell token.

    Handles redirects (``2>/dev/null``), flags with paths (``-I/usr/include``,
    ``--prefix=/opt``), and plain paths.

    Args:
        token: A single shell token.

    Yields:
        Path strings extracted from the token.
    """
    # Strip redirect prefix if present:
    stripped = _REDIRECT_PREFIX.sub("", token, count=1)
    if not stripped:
        return
    # Check for --flag=path or -Xpath patterns:
    elif stripped.startswith("-") and (m := _FLAG_WITH_PATH.match(stripped)):
        value = m.group(1)
        if "/" in value or value.startswith("~"):
            yield value
    # Plain path or relative path:
    elif "/" in stripped or stripped.startswith("~"):
        yield stripped


def inside(p: str, root: Path) -> str | None:
    """Check if a path resolves within sandbox boundaries.

    Args:
        p: Path string to validate (may contain ``~`` or ``$VAR``).
        root: Project root defining the sandbox.

    Returns:
        None if safe, otherwise the expanded path string for error messages.
    """
    if not p:
        return None
    elif (expanded := _expand(p)) in _DEV_OK:
        return None
    elif (Path(expanded).expanduser().resolve()).is_relative_to(CLAUDE_HOME):
        return None
    # Flags without embedded paths are OK:
    elif expanded.startswith("-") and "/" not in expanded and "~" not in expanded:
        return None

    try:
        resolved = (root / expanded).resolve()
    except OSError:
        return expanded

    if resolved.is_relative_to(root) or resolved.is_relative_to(TMP):
        return None
    return expanded


def subcommands(cmd: str) -> Iterator[str]:
    """Extract nested commands from ``$(...)``, ``<(...)``, ``>(...)`` and backticks.

    Args:
        cmd: Shell command string.

    Yields:
        Inner command strings from substitution constructs.
    """
    i = 0
    n = len(cmd)
    while i < n:
        if cmd[i:i + 2] in ("$(", "<(", ">("):
            depth, start = 1, i + 2
            for j in range(start, n):
                depth += (cmd[j] == "(") - (cmd[j] == ")")
                if depth == 0:
                    yield cmd[start:j]
                    i = j
                    break
            else:
                break  # Unclosed parenthesis
        elif cmd[i] == "`" and (end := cmd.find("`", i + 1)) > 0:
            yield cmd[i + 1:end]
            i = end
        i += 1


def check(cmd: str, root: Path) -> str | None:
    """Validate a shell command accesses only sandbox-safe paths.

    Args:
        cmd: Shell command string.
        root: Project root defining sandbox boundary.

    Returns:
        Error message if violation found, None if safe.
    """
    # Recurse into subcommands:
    for sub in subcommands(cmd):
        if err := check(sub, root):
            return err
    # Check redirect targets:
    for m in REDIR.finditer(cmd):
        if err := inside(m.group(1), root):
            return f"Redirect '{err}' outside sandbox"
    # Check all tokens:
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        return None

    for token in tokens:
        for path in _extract_paths(token):
            if err := inside(path, root):
                return f"Path '{err}' outside sandbox"
    return None


def main() -> None:
    """Hook entry point - read JSON from stdin, validate, output result."""
    payload = json.load(sys.stdin)
    cmd = payload.get("tool_input", {}).get("command", "")
    env_value = os.environ.get("CLAUDE_PROJECT_DIR")
    root = Path(env_value or payload.get("cwd", ".")).resolve()

    if err := check(cmd, root):
        json.dump({"decision": "block", "reason": err}, sys.stdout)
    else:
        json.dump({"decision": "approve"}, sys.stdout)


if __name__ == "__main__":
    main()

