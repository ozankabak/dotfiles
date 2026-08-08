#!/usr/bin/env python3
"""Render shared agent instructions from INSTRUCTIONS.md.j2."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "INSTRUCTIONS.md.j2"
TARGETS = {
    ROOT / ".claude/CLAUDE.md": {
        "agent_name": "Claude",
        "instruction_filename": "CLAUDE.md",
        "agent_home_name": "claude",
    },
    ROOT / ".codex/AGENTS.md": {
        "agent_name": "Codex",
        "instruction_filename": "AGENTS.md",
        "agent_home_name": "codex",
    },
}


def render(template: str, variables: dict[str, str]) -> str:
    """Substitute the template variables into the given string.

    Args:
        template: The instruction template text.
        variables: Template-variable names and their replacement values.

    Returns:
        The resulting instruction text, containing specific values for each
        template variable.
    """
    for variable, value in variables.items():
        template = template.replace(f"{{{{ {variable} }}}}", value)
    return template


def main() -> None:
    """Render and write both instruction files."""
    template = TEMPLATE.read_text()
    for target, variables in TARGETS.items():
        target.write_text(render(template, variables))


if __name__ == "__main__":
    main()
