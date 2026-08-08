#!/usr/bin/env python3.14
"""Render shared agent instructions from INSTRUCTIONS.md.j2."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "INSTRUCTIONS.md.j2"
TARGETS = (
    (ROOT / ".claude/CLAUDE.md", "Claude", "CLAUDE.md", "claude"),
    (ROOT / ".codex/AGENTS.md", "Codex", "AGENTS.md", "codex"),
)


def render(template: str, agent_name: str, instruction_filename: str, agent_home_name: str) -> str:
    """Substitute the supported template variables.

    Args:
        template: Shared instruction template text.
        agent_name: Display name of the target agent.
        instruction_filename: Target instruction filename.
        agent_home_name: Name of the agent state directory under the home directory.

    Returns:
        Rendered instruction text.
    """
    replacements = {
        "{{ agent_name }}": agent_name,
        "{{ instruction_filename }}": instruction_filename,
        "{{ agent_home_name }}": agent_home_name,
    }
    for variable, value in replacements.items():
        template = template.replace(variable, value)
    return template


def main() -> None:
    """Render both tracked instruction files.

    Returns:
        None. The rendered files are written to their tracked locations.
    """
    template = TEMPLATE.read_text()
    for target, agent_name, instruction_filename, agent_home_name in TARGETS:
        target.write_text(render(template, agent_name, instruction_filename, agent_home_name))


if __name__ == "__main__":
    main()
