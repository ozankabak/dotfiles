#!/usr/bin/env python3
"""Verify that ``path_check.py`` covers every filesystem grant in the sandbox profile.

The macOS sandbox profile is the enforcing boundary; ``.agent-hooks/path_check.py``
is an advisory pre-flight check that must never reject what the profile permits.
This script renders the effective profile, extracts its filesystem grants, and
fails if any of them falls outside the hook's policy tables.

This script only covers ``file-read*`` and ``file-write*`` grants. It reports
metadata-only grants (``file-read-metadata``) but does not enforce them: the
hook treats them as readable, which is more permissive than the profile and
therefore cannot cause a false rejection. It reports ``regex`` terms rather
than silently skip them.

Usage:
    scripts/check-policy-sync.py --profile <sandbox_profile.sb> --target-dir <dir>
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Literal, NamedTuple, Self

type Rule = Literal["allow", "deny"]
type Kind = Literal["subpath", "literal", "regex"]
type Access = Literal["read", "write", "metadata"]

# Operations that make a grant readable or writable, and therefore checkable.
_WRITE_OPS = ("file-write*", "file-write-create")
_READ_OPS = ("file-read*", "file-read-data")
_TERM_HEADS = ("subpath", "literal", "regex")

_STRING_APPEND = re.compile(r'\(string-append\s+\(param\s+"(\w+)"\)\s+"([^"]*)"')
_PARAM = re.compile(r'\(param\s+"(\w+)"\)')
_QUOTED = re.compile(r'^"([^"]*)"$')


class Grant(NamedTuple):
    """One filesystem term of one ``allow`` or ``deny`` rule.

    A rule conferring several access classes yields one grant per class, so that a
    ``deny`` revoking only the write half leaves the read half checkable.
    """

    rule: Rule
    """Whether the enclosing rule confers access or revokes it."""

    kind: Kind
    """The term's matcher: a directory tree, a single path, or a pattern."""

    path: str
    """The expanded path, or the raw pattern source when kind is ``regex``."""

    access: Access
    """The access class this grant covers."""


class Policy(NamedTuple):
    """The hook's path policy, as reported by ``path_check.py --dump-policy``."""

    deny_roots: frozenset[Path]
    """Trees the hook refuses outright, exceptions to the readable trees below."""

    read_roots: frozenset[Path]
    """Trees the hook accepts for reads only."""

    read_literals: frozenset[Path]
    """Paths readable in themselves, without their contents."""

    write_roots: frozenset[Path]
    """Trees the hook accepts for both reads and writes."""

    device_literals: frozenset[str]
    """Device paths accepted verbatim, such as ``/dev/null``."""

    device_prefixes: tuple[str, ...]
    """Device path prefixes accepted for any suffix, such as ``/dev/tty``,
    standing in for the profile's regex terms."""

    @classmethod
    def from_hook(cls, hook: Path) -> Self:
        """Load the policy by invoking the hook.

        Args:
            hook: Path to ``path_check.py``.

        Returns:
            The decoded policy.
        """
        policy_output = subprocess.run(
            [sys.executable, str(hook), "--dump-policy"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        table = json.loads(policy_output)
        return cls(
            deny_roots=frozenset(Path(p) for p in table["deny_roots"]),
            read_roots=frozenset(Path(p) for p in table["read_roots"]),
            read_literals=frozenset(Path(p) for p in table["read_literals"]),
            write_roots=frozenset(Path(p) for p in table["write_roots"]),
            device_literals=frozenset(table["device_literals"]),
            device_prefixes=tuple(table["device_prefixes"]),
        )

    def covers(self, path: Path, access: Access, root: Path) -> bool:
        """Return whether the hook permits at least the access a grant confers.

        Args:
            path: Resolved grant path.
            access: The access the profile grants.
            root: Resolved project root.

        Returns:
            ``True`` when the hook already permits the access.
        """
        if str(path) in self.device_literals or str(path).startswith(
            self.device_prefixes
        ):
            return True
        if path.is_relative_to(root) or any(
            path.is_relative_to(w) for w in self.write_roots
        ):
            return True
        if access == "write":
            return False
        # Parents of the project root are listable but not readable, matching the
        # literal rules agent-sandbox generates for them.
        literals = self.read_literals | set(root.parents) | {root}
        return path in literals or any(path.is_relative_to(r) for r in self.read_roots)


def strip_comments(text: str) -> str:
    """Remove ``;;`` comments while preserving quoted strings.

    Args:
        text: Sandbox profile source.

    Returns:
        Profile source with comments removed.
    """

    def strip(line: str) -> str:
        in_string = False
        for i, char in enumerate(line):
            if char == '"':
                in_string = not in_string
            elif char == ";" and not in_string:
                return line[:i]
        return line

    return "\n".join(strip(line) for line in text.splitlines())


def forms(text: str) -> Iterator[str]:
    """Track parenthesis balance and yield top-level parenthetic forms (including parentheses).

    Args:
        text: Profile source sans comments, or the body of one form.

    Yields:
        Form strings.
    """
    depth, start, in_string = 0, 0, False
    for i, char in enumerate(text):
        if char == '"':
            in_string = not in_string
        elif in_string:
            continue
        elif char == "(":
            if not depth:
                start = i
            depth += 1
        elif char == ")":
            depth -= 1
            if not depth:
                yield text[start : i + 1]


def terms(form: str) -> Iterator[tuple[Kind, str]]:
    """Yield the path terms of a form, descending into wrappers like ``require-all``.

    Tracks parenthesis balance while scanning rather than a regex so that it captures
    constructs such as ``(string-append (param "HOME_DIR") "/.cargo")`` whole.

    Args:
        form: A single ``allow`` or ``deny`` form.

    Yields:
        Tuples of (head, argument source).
    """
    for inner in forms(form[1:-1]):
        # Split on any whitespace: the profile wraps long terms across lines,
        # so a head is not always followed by a space.
        head, *rest = inner[1:-1].strip().split(None, 1)
        if head in _TERM_HEADS:
            if rest:
                yield head, rest[0].strip()
            else:
                yield head, ""
        else:
            yield from terms(inner)


def expand(argument: str, params: dict[str, str]) -> str | None:
    """Resolve a profile path term into a concrete path string.

    Args:
        argument: The term's argument source, e.g. ``(string-append …)``.
        params: Values for ``-D`` profile parameters.

    Returns:
        The concrete path, or ``None`` when the term cannot be expanded.
    """
    argument = argument.strip()
    if m := _QUOTED.match(argument):
        return m.group(1)
    if m := _STRING_APPEND.match(argument):
        return params[m.group(1)] + m.group(2)
    if m := _PARAM.match(argument):
        return params[m.group(1)]
    return None


def grants(profile: str, params: dict[str, str]) -> Iterator[Grant]:
    """Yield every filesystem grant and revocation in a rendered sandbox profile.

    Args:
        profile: Sandbox profile source.
        params: Values for ``-D`` profile parameters.

    Yields:
        One grant per path term of each ``allow``/``deny`` rule.
    """
    for form in forms(strip_comments(profile)):
        rule, _, operations = form[1:].partition(" ")
        if rule not in ("allow", "deny"):
            continue
        operations = operations[: operations.find("(")]
        # A rule may confer read and write at once. Emit one grant per access class,
        # so that a deny revoking only the write half leaves the read half checkable.
        accesses: list[Access] = []
        if any(op in operations for op in _WRITE_OPS):
            accesses.append("write")
        if any(op in operations for op in _READ_OPS):
            accesses.append("read")
        elif "file-read-metadata" in operations:
            accesses.append("metadata")
        for kind, argument in terms(form):
            # A regex term is reported verbatim; it cannot be compared mechanically.
            path = argument if kind == "regex" else expand(argument, params)
            if path is not None:
                yield from (Grant(rule, kind, path, a) for a in accesses)


def refuses_read(rules: list[Grant], path: Path) -> bool:
    """Return whether the profile's effective policy refuses to read a path.

    Sandbox profiles are last-match-wins, and the base profile denies ``/`` before
    re-allowing individual trees, so the verdict is the final matching read rule
    rather than the presence of any deny. Does not match regex terms.

    Args:
        rules: Every grant of the profile, in file order.
        path: Resolved path to evaluate.

    Returns:
        ``True`` when refuses reads of the path.
    """
    refuse = False
    for grant in rules:
        if grant.access == "read" and grant.kind != "regex":
            term = Path(grant.path).resolve()
            if grant.kind == "subpath":
                matches = path.is_relative_to(term)
            else:
                matches = path == term
            if matches:
                refuse = grant.rule == "deny"
    return refuse


def main() -> None:
    """Compare the rendered profile against the hook policy and report drift.

    Writes:
        A per-grant report to standard output; exits non-zero on drift.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--target-dir", type=Path, required=True)
    parser.add_argument("--hook", type=Path, required=True)
    args = parser.parse_args()

    home = os.path.expanduser("~")
    root = args.target_dir.resolve()
    params = {
        "TARGET_DIR": str(root),
        "TMP_DIR": "/tmp",
        "HOME_DIR": home,
        "CACHE_DIR": f"{home}/.cache",
        "CODEX_HOME_DIR": os.environ.get("CODEX_HOME", f"{home}/.codex"),
    }
    policy = Policy.from_hook(args.hook)
    rules = list(grants(args.profile.read_text(), params))

    # A later deny revokes an earlier allow (sandbox profiles are last-match-wins),
    # so a revoked grant is not something the hook needs to cover.
    revocations = {(g.path, g.access) for g in rules if g.rule == "deny"}
    allows = [g for g in rules if g.rule == "allow"]

    # The hook must not invent restrictions either: every tree it refuses outright
    # should have a corresponding sandbox profile deny.
    orphan_refusals = [
        p for p in sorted(policy.deny_roots) if not refuses_read(rules, p)
    ]

    # One rule can yield several grants per path, so report each path once. Write
    # grants come first, and covering a write also covers the read.
    regexes = dict.fromkeys(g.path for g in allows if g.kind == "regex")
    missing = dict[str, Grant]()
    for grant in allows:
        if grant.kind == "regex" or grant.access == "metadata":
            continue
        if (grant.path, grant.access) in revocations:
            continue
        if not policy.covers(Path(grant.path).resolve(), grant.access, root):
            missing.setdefault(grant.path, grant)

    for path in regexes:
        print(f"  did not check (regex term): {path}")
    for grant in missing.values():
        print(
            f"✗ profile grants {grant.access} on {grant.path}, hook policy does not cover it"
        )
    for path in orphan_refusals:
        print(f"✗ hook denies {path}, sandbox profile does not")
    if failures := len(missing) + len(orphan_refusals):
        print(f"\nPath policy: {failures} rule(s) out of sync with the hook")
        sys.exit(1)
    print("✓ hook policy and sandbox profile agree")


if __name__ == "__main__":
    main()
