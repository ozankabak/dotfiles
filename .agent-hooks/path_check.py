#!/usr/bin/env python3
"""Validate Claude and Codex shell commands against one common path policy.

This hook mirrors the macOS sandbox profile (``scripts/agent-sandbox.noread.sb``
plus ``scripts/agent-sandbox.overlay.sb``) so that it never rejects a command the
sandbox would permit. It handles redirects, paths in flags (e.g. -I/usr/include),
tilde expansion, environment variables, and subcommands.

The hook is advisory; the sandbox is the enforcing boundary. Run
``scripts/test-agent-sandbox.sh`` to verify that the tables below still cover every
grant in the profile.

Usage:
    Claude ~/.claude/settings.json:
        {
          "hooks": {
            "PreToolUse": [{
              "matcher": "Bash",
              "hooks": [{
                "type": "command",
                "command": "python3 ~/.agent-hooks/path_check.py --agent claude"
              }]
            }]
          }
        }

    Codex ~/.codex/hooks.json:
        {
          "hooks": {
            "PreToolUse": [{
              "matcher": "^Bash$",
              "hooks": [{
                "type": "command",
                "command": "python3 ~/.agent-hooks/path_check.py --agent codex"
              }]
            }]
          }
        }
"""

import argparse
import json
import os
import re
import shlex
import sys
from collections.abc import Iterable, Iterator
from pathlib import Path
from typing import Literal, NamedTuple

AGENTS = ("claude", "codex")


def _resolve(path: str) -> Path | None:
    """Resolve a policy or candidate path, tolerating unresolvable input.

    Args:
        path: Path string, possibly containing ``~``.

    Returns:
        The fully resolved path, or ``None`` when resolution fails.
    """
    try:
        return Path(os.path.expanduser(path)).resolve()
    except OSError:
        return None


def _resolve_all(paths: Iterable[str]) -> frozenset[Path]:
    """Resolve every entry of a policy table, dropping unresolvable ones.

    Resolution collapses the symlink aliases the profile has to spell out twice
    (``/etc`` and ``/private/etc``, ``/var`` and ``/private/var``), and makes
    absolute, ``~`` and ``$HOME`` spellings of the same location compare equal.

    Args:
        paths: Policy path strings.

    Returns:
        Frozen set of resolved paths.
    """
    return frozenset(r for p in paths if (r := _resolve(p)) is not None)


# The tables below mirror the OS level sandbox; see:
# - scripts/agent-sandbox.noread.sb
# - scripts/agent-sandbox.overlay.sb

# (allow file-read* (subpath ...)): readable; the sandbox denies writes.
READ_ROOTS = _resolve_all(
    (
        "/usr",
        "/bin",
        "/opt",
        "/var",
        "/etc",
        "/System",
        "/nix",
        "/run",
        "/Library/Java",
        "/Library/Developer",
        "/Library/Preferences",
        # The profile grants specific plists plus a ByHost regex; the hook
        # approximates that with the containing directory.
        "~/Library/Preferences",
        "/Library/Application Support/ClaudeCode",
        "/Applications/Xcode.app",
        "/Applications/Xcode-beta.app",
        "~/.config/git",
        "~/.config/jj",
        "~/.gitconfig",
        "~/.config/nix",
        "~/.local/share/nix",
        "~/.local/state/nix",
        "~/.nix-profile",
        "~/.config/gh",
        "~/.config/mcp",
        "~/.config/direnv",
        "~/.local/share/direnv",
        "~/.direnvrc",
        "~/.rustup",
        "~/Library/Java",
        "~/Library/Keychains",
    )
)

# (allow file-read* (literal ...)): the directory itself, not its contents.
# The profile also emits one literal per parent of TARGET_DIR; we add those
# per-invocation from the project root, which is not known at import time.
READ_LITERALS = _resolve_all(
    ("/", "/dev", "/private", "/Library", "~/Library", "~/Library/Caches", "~/.config")
)

# (allow file-read* file-write* ...): full access.
WRITE_ROOTS = _resolve_all(
    (
        "/tmp",
        "/private/tmp",
        "/var/folders",
        "/dev/fd",
        os.environ.get("TMPDIR") or "/tmp",
        os.environ.get("CODEX_HOME") or "~/.codex",
        "~/.cache",
        # The profile grants every agent home unconditionally, so both agents get
        # both. This is deliberate: it allows one agent to repair the other.
        "~/.claude",
        "~/.claude.json",
        "~/.claude.json.backup",
        "~/.codex",
        "~/.gemini",
        "~/.agents",
        "~/.agent-hooks",
        "~/.cargo",
        "~/.elan",
        "~/.local/share/uv",
        "~/.nix-defexpr",
        "~/.sbt",
        "~/.ivy2",
        "~/.m2",
        "~/.jgit",
        "~/.config/jgit",
        "~/.config/sbt",
        "~/Library/Caches/claude-cli-nodejs",
        "~/Library/Caches/lima",
        "~/Library/Caches/sbt",
        "~/Library/Caches/Coursier",
        "~/Library/Caches/ScalaCli",
        "~/Library/Caches/com.thesamet.scalapb.protocbridge.protocbridge",
    )
)

# (deny file-read* ...): credential stores are exceptions of the readable roots
# above. Checked before the allow tables, since the profile's later deny wins.
DENY_ROOTS = _resolve_all(
    (
        "/etc/sudoers",
        "/etc/sudoers.d",
        "/etc/master.passwd",
        "/etc/krb5.keytab",
        "/etc/ssh",
        "/etc/ssl/private",
        "/var/db/dslocal",
    )
)

# Redirect operators whose following token is written, not read. shlex emits
# these as standalone tokens when punctuation_chars is set.
_WRITE_OPS = frozenset({">", ">>", ">|", ">&", "&>", "&>>", "<>"})

# (regex #"^/dev/tty*") and (regex #"^/dev/pty*") from the profile.
_DEV_PREFIXES = ("/dev/tty", "/dev/pty")

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
        "/dev/ptmx",
        "/dev/dtracehelper",
    }
)

# Redirect operators are deliberately absent: they belong to the command they
# follow rather than separating it from the next one.
_SEPARATOR_CHARS = frozenset(";&|(){}")

type FlagKind = Literal["script", "path", "nonpath", "command"]


class FlagUse(NamedTuple):
    """What a flag's value is, and where it sits."""

    kind: FlagKind
    """Whether the value is inline code, a path, never a path, or a command."""

    value_follows: bool
    """Whether the value is the next token rather than part of this one.

    ``cut -d /`` carries its value separately; ``cut -d/`` embeds it.
    """


class ArgSpec(NamedTuple):
    """How one command's arguments map onto filesystem paths.

    Commands absent from the table keep the conservative default, where every
    argument containing a separator can be a path. The table only ever relaxes
    that, so an incomplete entry degrades to the old behavior rather than to a
    gap.
    """

    takes_pattern: bool = False
    """Whether the first non-flag argument is a script or regex rather than a path."""

    script_flags: tuple[str, ...] = ()
    """Flags whose value is inline code, e.g. ``sed -e``."""

    path_flags: tuple[str, ...] = ()
    """Flags whose value is a path, e.g. ``sed -f``."""

    nonpath_flags: tuple[str, ...] = ()
    """Flags whose value is never a path, e.g. ``cut -d``."""

    command_flags: tuple[str, ...] = ()
    """Flags introducing a command line of their own, e.g. ``find -exec``."""

    bundled_script: bool = False
    """Whether a bundled short flag ending in ``e`` takes code, as in ``perl -ne``."""

    wrapper_operands: tuple[str, ...] | None = None
    """Positionals spent before the name of the command this one runs.

    ``None`` for an ordinary command; ``()`` for a wrapper that runs the very next
    argument, as ``env`` does; and one kind per positional otherwise. So, ``timeout 5
    sed ...`` spends a non-path argument on the duration and ``flock ./lock sed ...``
    spends a path argument on the lock file.

    A wrapper needs its own flags descriptions. Without that, ``nice -n 10 sed``
    reads ``-n`` as the command name and the ``sed`` rules never apply.
    """

    def flag_use(self, token: str) -> FlagUse | None:
        """Classify a flag token.

        Args:
            token: A token beginning with ``-``.

        Returns:
            How the flag carries its value, or ``None`` when the flag is unknown.
        """
        for kind, flags in (
            ("script", self.script_flags),
            ("path", self.path_flags),
            ("nonpath", self.nonpath_flags),
            ("command", self.command_flags),
        ):
            for flag in flags:
                if token == flag:
                    return FlagUse(kind, value_follows=True)
                prefix = f"{flag}=" if flag.startswith("--") else flag
                if token.startswith(prefix):
                    return FlagUse(kind, value_follows=False)
        if self.bundled_script and re.fullmatch(r"-[A-Za-z]*e", token):
            return FlagUse("script", value_follows=True)
        return None


_ARG_SPECS = {
    "sed": ArgSpec(
        takes_pattern=True,
        script_flags=("-e", "--expression"),
        path_flags=("-f", "--file"),
    ),
    "awk": ArgSpec(
        takes_pattern=True,
        path_flags=("-f", "--file"),
        nonpath_flags=("-F", "-v", "--field-separator", "--assign"),
    ),
    "grep": ArgSpec(
        takes_pattern=True,
        script_flags=("-e", "--regexp"),
        path_flags=("-f", "--file"),
    ),
    "rg": ArgSpec(takes_pattern=True, script_flags=("-e", "--regexp")),
    "ag": ArgSpec(takes_pattern=True),
    "jq": ArgSpec(takes_pattern=True, path_flags=("-f", "--from-file")),
    "cut": ArgSpec(nonpath_flags=("-d", "--delimiter")),
    "sort": ArgSpec(nonpath_flags=("-t", "--field-separator")),
    "find": ArgSpec(
        nonpath_flags=("-name", "-iname", "-path", "-ipath", "-regex", "-iregex"),
        command_flags=("-exec", "-execdir", "-ok", "-okdir"),
    ),
    "perl": ArgSpec(script_flags=("-e", "-E"), bundled_script=True),
    "ruby": ArgSpec(script_flags=("-e",), bundled_script=True),
    "python": ArgSpec(script_flags=("-c",)),
    "python3": ArgSpec(script_flags=("-c",)),
    "node": ArgSpec(script_flags=("-e", "--eval", "-p", "--print")),
    "env": ArgSpec(
        wrapper_operands=(),
        path_flags=("-C", "--chdir"),
        nonpath_flags=("-u", "--unset"),
    ),
    "nice": ArgSpec(wrapper_operands=(), nonpath_flags=("-n", "--adjustment")),
    "stdbuf": ArgSpec(
        wrapper_operands=(),
        nonpath_flags=("-i", "-o", "-e", "--input", "--output", "--error"),
    ),
    "xargs": ArgSpec(
        wrapper_operands=(),
        path_flags=("-a", "--arg-file"),
        nonpath_flags=(
            "-n",
            "-I",
            "-i",
            "-L",
            "-P",
            "-s",
            "-E",
            "-d",
            "--max-args",
            "--replace",
            "--max-lines",
            "--max-procs",
            "--max-chars",
            "--delimiter",
        ),
    ),
    "timeout": ArgSpec(
        wrapper_operands=("nonpath",),
        nonpath_flags=("-s", "--signal", "-k", "--kill-after"),
    ),
    "flock": ArgSpec(wrapper_operands=("path",)),
    "chroot": ArgSpec(wrapper_operands=("path",)),
    "taskset": ArgSpec(wrapper_operands=("nonpath",)),
    "ionice": ArgSpec(wrapper_operands=(), nonpath_flags=("-c", "-n", "-p", "--class")),
    "git": ArgSpec(
        wrapper_operands=(),
        path_flags=("-C", "--git-dir", "--work-tree"),
        nonpath_flags=("-c",),
    ),
}

# Keywords, block delimiters and option-less runners that introduce a command
# rather than being one. Without them ``do sed '/x/d' ./f`` reads ``do`` as the
# command, and the ``sed`` rules never apply to what follows.
_ARG_SPECS.update(
    dict.fromkeys(
        (
            "if",
            "then",
            "elif",
            "else",
            "fi",
            "while",
            "until",
            "do",
            "done",
            "for",
            "in",
            "case",
            "esac",
            "select",
            "function",
            "!",
            "{",
            "}",
            "command",
            "builtin",
            "exec",
            "nohup",
            "setsid",
            "time",
        ),
        ArgSpec(wrapper_operands=()),
    )
)
_ARG_SPECS["egrep"] = _ARG_SPECS["fgrep"] = _ARG_SPECS["grep"]
_ARG_SPECS["gawk"] = _ARG_SPECS["mawk"] = _ARG_SPECS["awk"]
_ARG_SPECS["gsed"] = _ARG_SPECS["sed"]
_ARG_SPECS["gtimeout"] = _ARG_SPECS["timeout"]

# Flag patterns that embed absolute paths: -I/path, --prefix=/path, etc.
_FLAG_WITH_PATH = re.compile(r"^--?[a-zA-Z][-a-zA-Z0-9_]*[=:]?(.+)$")

# A here-document introducer, capturing the quote (if any) and the delimiter.
# The trailing character class keeps `<<<` here-strings from matching.
_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# Names the profile refuses to read inside the project directory. Recognizes
# a bare token as a path worth checking and judges a resolved one.
_SENSITIVE_NAME = re.compile(r"^(?:\.env(?:\..*)?|[^/]*\.(?:pem|key)|id_rsa[^/]*)$")
_SENSITIVE_DIRECTORIES = frozenset({".ssh", ".aws", ".gnupg"})


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
    elif "/" in token or token.startswith("~") or _SENSITIVE_NAME.fullmatch(token):
        yield token


def _is_sensitive_workspace_path(resolved: Path, root: Path) -> bool:
    """Return whether a workspace path matches Claude's sensitive-read denies.

    Args:
        resolved: Fully resolved candidate path.
        root: Resolved workspace root.

    Returns:
        ``True`` when the path is a protected workspace file or directory.
    """
    try:
        relative = resolved.relative_to(root)
    except ValueError:
        return False
    return bool(_SENSITIVE_NAME.fullmatch(relative.name)) or any(
        part in _SENSITIVE_DIRECTORIES for part in relative.parts
    )


def _can_access_path(resolved: Path, root: Path, *, writing: bool) -> bool:
    """Return whether the profile grants the necessary access to a resolved path.

    Args:
        resolved: Fully resolved candidate path.
        root: Resolved project root.
        writing: Whether the command writes to the path rather than reading it.

    Returns:
        ``True`` when the sandbox profile permits the access.
    """
    if resolved.is_relative_to(root) or any(
        resolved.is_relative_to(w) for w in WRITE_ROOTS
    ):
        return True
    if writing:
        return False
    # Parent directories of the project root are listable but not readable, which
    # is what the sandbox profile's literal rules grant.
    return (
        resolved in READ_LITERALS
        or resolved in root.parents
        or any(resolved.is_relative_to(r) for r in READ_ROOTS)
    )


def inside(p: str, root: Path, *, writing: bool = False) -> str | None:
    """Check if a path resolves within sandbox boundaries.

    Args:
        p: Path string to validate (may contain ``~`` or ``$VAR``).
        root: Project root defining the sandbox.
        writing: Whether the path is a redirect target, so writable access is necessary.

    Returns:
        ``None`` if safe, otherwise a message explaining the rejection.
    """
    if (
        not p
        or (expanded := _expand(p)) in _DEV_OK
        or expanded.startswith(_DEV_PREFIXES)
    ):
        return None

    try:
        resolved = (root / expanded).resolve()
    except OSError:
        return f"Path '{expanded}' outside sandbox"

    if any(resolved.is_relative_to(d) for d in DENY_ROOTS):
        return f"Path '{expanded}' is a credential store, sandbox profile denies access"
    if _is_sensitive_workspace_path(resolved, root):
        return f"Path '{expanded}' is a protected sensitive path"
    if _can_access_path(resolved, root, writing=writing):
        return None
    if writing and _can_access_path(resolved, root, writing=False):
        return f"Path '{expanded}' is read-only under the sandbox profile"
    return f"Path '{expanded}' outside sandbox"


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


def _strip_heredocs(cmd: str, *, quoted_only: bool = False) -> str:
    """Remove here-document bodies, which are data rather than arguments.

    A body is text a command receives on standard input, so its lines are not
    filesystem paths. A body introduced by an unquoted delimiter does undergo
    substitution, so those are kept when scanning for nested commands.

    Args:
        cmd: Shell command string, possibly spanning lines.
        quoted_only: Remove only bodies whose delimiter was quoted, as in
            ``<<'EOF'``, where the shell performs no substitution.

    Returns:
        The command with the selected here-document bodies removed.
    """
    lines, out, i = cmd.splitlines(), [], 0
    while i < len(lines):
        out.append(lines[i])
        heredocs = [(m.group(1), m.group(2)) for m in _HEREDOC.finditer(lines[i])]
        i += 1
        for quote, delimiter in heredocs:
            keep = quoted_only and not quote
            while i < len(lines) and lines[i].strip() != delimiter:
                if keep:
                    out.append(lines[i])
                i += 1
            i += 1  # The terminator line is not an argument either.
    return "\n".join(out)


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


def _path_tokens(tokens: list[str]) -> Iterator[tuple[str, bool]]:
    """Yield the tokens of a command line that denote filesystem paths.

    Tracks where each simple command starts so that per-command argument rules
    apply, and drops the arguments those rules mark as scripts, patterns or
    non-path flag values. Without this, ``sed '/pattern/d'`` and ``cut -d/``
    read as absolute paths.

    Args:
        tokens: Tokens of one command line, as produced by shlex.

    Yields:
        Tuples of (token, whether it is a redirect target).
    """
    spec = wrapper = pending = None
    operands: tuple[str, ...] = ()
    awaiting_command, redirect, only_operands = True, False, False
    for token in tokens:
        # An empty argument, as in the BSD ``sed -i ''`` idiom, does not constitute
        # an operand and must not consume the script or pattern role. Neither is the
        # newline a backslash continuation leaves behind.
        if not token.strip():
            continue
        # Separators and brace delimiters end the current simple command, as does
        # any token ending in "(", which covers process substitution's `<(` and `>(`.
        if not set(token) - _SEPARATOR_CHARS or token.endswith("("):
            spec = wrapper = pending = None
            operands = ()
            awaiting_command, redirect, only_operands = True, False, False
            continue
        if token in _WRITE_OPS:
            redirect = True
            continue
        writing, redirect = redirect, False

        if pending:
            # The value of the preceding flag, e.g. the 10 of ``nice -n 10``.
            if pending == "path":
                yield token, writing
            pending = None
        elif token == "--" and not awaiting_command:
            # Everything after ``--`` is an operand, even if it looks like a flag.
            only_operands = True
        elif awaiting_command:
            if token.startswith("-"):
                yield token, writing
                if wrapper:
                    use = wrapper.flag_use(token)
                else:
                    use = None
                if use and use.value_follows:
                    pending = use.kind
            elif "=" in token.partition("/")[0]:
                yield token, writing  # VAR=value prefix
            elif operands:
                # A positional the wrapper spends before naming its command.
                if operands[0] == "path":
                    yield token, writing
                operands = operands[1:]
            else:
                # The shell reads and executes the command name, so check it too:
                yield token, writing
                found = _ARG_SPECS.get(token.rsplit("/", 1)[-1])
                if found and found.wrapper_operands is not None:
                    wrapper, operands = found, found.wrapper_operands
                else:
                    spec, awaiting_command = found, False
        elif spec and not only_operands and token.startswith("-"):
            use = spec.flag_use(token)
            if use is None or (use.kind == "path" and not use.value_follows):
                yield token, writing
            if use and use.kind == "command":
                # ``find -exec CMD ;`` introduces a command line of its own.
                spec = wrapper = None
                operands, awaiting_command = (), True
            elif use:
                if use.value_follows:
                    pending = use.kind
                if use.kind != "nonpath":
                    # A script or file supplied by flag consumes the operand role,
                    # so the next bare argument is an ordinary path.
                    spec = spec._replace(takes_pattern=False)
        elif spec and spec.takes_pattern:
            # The first bare operand is the script or pattern, not a path.
            spec = spec._replace(takes_pattern=False)
        else:
            yield token, writing


def check(cmd: str, root: Path) -> str | None:
    """Validate a shell command accesses only sandbox-safe paths.

    Args:
        cmd: Shell command string.
        root: Project root defining sandbox boundary.

    Returns:
        Error message if violation found, ``None`` if safe.
    """
    # Recurse into subcommands. A body introduced by a quoted delimiter is literal,
    # so it holds no commands to recurse into:
    for sub in subcommands(_strip_heredocs(cmd, quoted_only=True)):
        if err := check(sub, root):
            return err
    # Drop every here-document body before tokenizing, then neutralize escaped
    # substitutions, since neither supplies arguments to the command:
    sanitized = _neutralize_escapes(_strip_heredocs(cmd))
    # Check all tokens (shlex splits on redirect operators, so paths after
    # redirects become separate tokens and are checked via _extract_paths):
    try:
        lex = shlex.shlex(sanitized, posix=True, punctuation_chars=";&|()<>")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        return None

    for token, writing in _path_tokens(tokens):
        for path in _extract_paths(token):
            if err := inside(path, root, writing=writing):
                return err
    return None


def main() -> None:
    """Read a hook payload and emit the permission decision.

    Writes:
        The agent-specific JSON decision to standard output.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", choices=AGENTS)
    parser.add_argument(
        "--dump-policy",
        action="store_true",
        help="Print the path policy as JSON and exit.",
    )
    args = parser.parse_args()
    if args.dump_policy:
        json.dump(
            {
                "deny_roots": sorted(str(p) for p in DENY_ROOTS),
                "read_roots": sorted(str(p) for p in READ_ROOTS),
                "read_literals": sorted(str(p) for p in READ_LITERALS),
                "write_roots": sorted(str(p) for p in WRITE_ROOTS),
                "device_literals": sorted(_DEV_OK),
                "device_prefixes": sorted(_DEV_PREFIXES),
            },
            sys.stdout,
        )
        return
    if not (agent := args.agent):
        parser.error("--agent is required unless --dump-policy is given")

    try:
        payload = json.load(sys.stdin)
        cmd = payload.get("tool_input", {}).get("command", "")
        env_value = os.environ.get(f"{agent.upper()}_PROJECT_DIR")
        root = Path(env_value or payload.get("cwd", ".")).resolve()
        err = check(cmd, root)
    except Exception as exc:  # noqa: BLE001 - any failure must refuse, not approve.
        # Codex reads an empty response as approval, so a crash would silently
        # disable the check for it while blocking Claude. Refuse for both, and
        # name the cause so it reads as a hook bug rather than a policy decision.
        err = f"exception during path checking: {type(exc).__name__}: {exc}"
        print(err, file=sys.stderr)
    if agent == "claude":
        if err:
            output = {"decision": "block", "reason": err}
        else:
            output = {"decision": "approve"}
    elif err:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": err,
            }
        }
    else:
        return  # Codex reads silence as approval.
    json.dump(output, sys.stdout)


if __name__ == "__main__":
    main()
