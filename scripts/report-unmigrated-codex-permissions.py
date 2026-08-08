#!/usr/bin/env python3
"""List Claude permissions that cannot become Codex execution-policy rules."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / ".claude/settings.json"
DECISIONS = ("allow", "ask", "deny")


def is_bash_permission(permission: str) -> bool:
    """Return whether a Claude permission is a Bash command rule.

    Args:
        permission: A Claude permission string.

    Returns:
        Whether the permission can be migrated to a Codex execution-policy rule.
    """
    return permission.startswith("Bash(") and permission.endswith(")")


def unmigrated_permissions(permissions: dict[str, object]) -> dict[str, list[str]]:
    """Collect non-Bash Claude permissions by their decision class.

    Args:
        permissions: Claude permissions dictionary.

    Returns:
        Non-Bash permissions keyed by Claude decision class.

    Raises:
        ValueError: If the permissions dictionary does not use the expected format.
    """
    result: dict[str, list[str]] = {}
    for decision in DECISIONS:
        entries = permissions.get(decision, [])
        if not isinstance(entries, list) or not all(isinstance(entry, str) for entry in entries):
            raise ValueError(f"permissions.{decision} must be a list of strings")
        result[decision] = [entry for entry in entries if not is_bash_permission(entry)]
    return result


def main() -> None:
    """Print the non-command permissions omitted by the Codex rule generator."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()

    settings = json.loads(args.source.read_text())
    omitted = unmigrated_permissions(settings["permissions"])
    for decision in DECISIONS:
        print(f"{decision} ({len(omitted[decision])}):")
        for permission in omitted[decision]:
            print(f"  {permission}")
        print()

    print(
        "Unmigrated non-command permissions: "
        + ", ".join(f"{decision}={len(omitted[decision])}" for decision in DECISIONS)
    )


if __name__ == "__main__":
    main()
