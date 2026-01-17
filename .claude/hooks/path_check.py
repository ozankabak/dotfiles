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

TMP_ROOTS = {Path("/tmp").resolve(), Path("/private/tmp").resolve()}
if tmpdir := os.environ.get("TMPDIR"):
    try:
        TMP_ROOTS.add(Path(tmpdir).expanduser().resolve())
    except OSError:
        pass
CLAUDE_HOME = Path("~/.claude").expanduser().resolve()

_DEV_OK = frozenset(
    {
        "/dev/null",
        "/dev/zero",
        "/dev/random",
        "/dev/urandom",
        "/dev/stdin",
        "/dev/stdout",
        "/dev/stderr",
        "/dev/fd/0",
        "/dev/fd/1",
        "/dev/fd/2",
        "/dev/fd0",
        "/dev/fd1",
        "/dev/fd2",
        "/dev/tty",
        "/dev/ptmx",
    }
)

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

    Handles flags with paths (``-I/usr/include``, ``--prefix=/opt``) and plain paths.
    Redirect operators are split by shlex, so paths after redirects are plain tokens.

    Args:
        token: A single shell token.

    Yields:
        Path strings extracted from the token.
    """
    if not token:
        return
    # Check for --flag=path or -Xpath patterns:
    if token.startswith("-") and (m := _FLAG_WITH_PATH.match(token)):
        value = m.group(1)
        if "/" in value or value.startswith("~"):
            yield value
    # Plain path or relative path:
    elif "/" in token or token.startswith("~"):
        yield token


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
    elif (Path(expanded).resolve()).is_relative_to(CLAUDE_HOME):
        return None
    # Flags without embedded paths are OK:
    elif expanded.startswith("-") and "/" not in expanded and "~" not in expanded:
        return None

    try:
        resolved = (root / expanded).resolve()
    except OSError:
        return expanded

    if resolved.is_relative_to(root) or any(
        resolved.is_relative_to(t) for t in TMP_ROOTS
    ):
        return None
    return expanded


def _paren_end(s: str, i: int) -> int:
    """Return the index after a balanced ")", or ``len(s)`` otherwise.

    Skips quoted strings so that parentheses inside quotes don't affect the
    depth count. Handles single quotes, double quotes (with ``\\"`` escapes),
    and escaped parentheses.

    Args:
        s: String containing parentheses.
        i: Index of the character after the opening "(".

    Returns:
        Index after the matching ")", or ``len(s)`` otherwise.
    """
    d, n = 1, len(s)
    while i < n and d:
        c = s[i]
        if c == "'":
            i = s.find("'", i + 1) + 1 or n
        elif c == '"':
            i += 1
            while i < n and s[i] != '"':
                i += 2 if s[i : i + 2] == '\\"' else 1
            i += 1
        elif c == "\\":
            i += 2
        else:
            d += (c == "(") - (c == ")")
            i += 1
    return i


def subcommands(cmd: str) -> Iterator[str]:
    """Extract nested commands from ``$(...)``, ``<(...)``, ``>(...)``, and backticks.

    Scans the raw command string for substitution constructs. Skips content
    inside single quotes, ANSI-C quotes (``$'...'``), and escaped chars (``\\$``,
    ``\\<``, ``\\>``). Handles nested escaped backticks in old-style
    substitutions.

    Args:
        cmd: Shell command string.

    Yields:
        Inner command strings from substitution constructs.
    """
    i, n = 0, len(cmd)
    while i < n:
        c, c2 = cmd[i], cmd[i : i + 2]
        if c == "'":  # single quotes: literal, skip
            i = cmd.find("'", i + 1) + 1 or n
        elif c2 in ("\\\\", "\\$", "\\<", "\\>", "\\`"):  # escaped: literal, skip
            i += 2
        elif c2 == "$'":  # ANSI-C quotes: literal, skip
            i += 2
            while i < n and cmd[i] != "'":
                i += 2 if cmd[i : i + 2] == "\\'" else 1
            if i < n:
                i += 1
        elif c2 in ("$(", "<(", ">("):  # paren substitution: EXECUTES
            end = _paren_end(cmd, i + 2)
            if cmd[end - 1 : end] == ")":
                yield cmd[i + 2 : end - 1]
            i = end
        elif c == "`":  # backtick substitution: EXECUTES
            j = i + 1
            while j < n and cmd[j] != "`":
                j += 2 if cmd[j : j + 2] == "\\`" else 1
            if j >= n:
                return
            yield (content := cmd[i + 1 : j])
            if "\\`" in content:
                yield from subcommands(content.replace("\\`", "`"))
            i = j + 1
        else:
            i += 1


def _neutralize_escapes(cmd: str) -> str:
    """Replace escaped substitution content with placeholders for shlex.

    Escaped constructs like ``\\$(...)`` don't execute in shell, so we replace
    them before shlex tokenization to avoid false positives on paths inside.
    Also handles ``\\<(...)``, ``\\>(...)``, and paired ``\\`...\\```.

    Args:
        cmd: Shell command string.

    Returns:
        Sanitized command string with escaped substitutions neutralized.
    """
    out, i, n = [], 0, len(cmd)
    while i < n:
        c2, c3 = cmd[i : i + 2], cmd[i : i + 3]
        if cmd[i] == "'":  # single quotes: preserve verbatim
            j = cmd.find("'", i + 1) + 1 or n
            out.append(cmd[i:j])
            i = j
        elif c2 == "\\\\":  # escaped backslash: preserve
            out.append("\\\\")
            i += 2
        elif c3 in ("\\$(", "\\<(", "\\>("):  # escaped paren subst: neutralize
            out.append("_")
            i = _paren_end(cmd, i + 3)
        elif c2 == "\\`":  # escaped backticks: neutralize paired span
            j = cmd.find("\\`", i + 2)
            out.append("_")
            i = j + 2 if j >= 0 else i + 2
        else:
            out.append(cmd[i])
            i += 1
    return "".join(out)


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
    # Neutralize escaped substitutions before shlex (they don't execute,
    # avoid false positives):
    sanitized = _neutralize_escapes(cmd)
    # Check all tokens (shlex splits on redirect operators, so paths after
    # redirects become separate tokens and are checked via _extract_paths):
    try:
        lex = shlex.shlex(sanitized, posix=True, punctuation_chars=";&|()<>")
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
