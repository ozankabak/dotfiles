# CLAUDE.md — Universal Project Guidelines

This document contains instructions and guidelines for Claude instances working on software development projects.

**Override mechanism**: If a project contains its own `CLAUDE.md` file, those project-specific instructions take precedence. When conflicts exist, follow the project-specific instructions.

---

## Sandbox Environment

You operate in a macOS `sandbox-exec` environment with restricted file access:

- **Read Access**: Project directory, system paths (read-only)
- **Write Access**: Project directory, `/tmp`, `~/.cache`, `~/.claude`
- **Network**: Full access
- **Blocked**: Paths outside the above, sensitive files (`.env`, credentials, secrets)

Do not attempt to access files outside these boundaries — commands will fail (often with an error, but may do so silently or hang).

---

## Multi-Instance Workflow (Worktrees & PRs)

Multiple Claude instances may work on the same repository concurrently. Follow this workflow:

### Setup (once per repository)
```bash
# Create worktrees directory and add to .gitignore
mkdir -p .worktrees
echo ".worktrees/" >> .gitignore
```

### Starting Work
```bash
# Create a worktree for your task (stays within project directory)
git worktree add .worktrees/feature-name -b feature/descriptive-name

# Work exclusively in your worktree
cd .worktrees/feature-name
```

**Branch naming conventions**:
- `feature/` — New functionality
- `fix/` — Bug fixes
- `refactor/` — Code restructuring without behavior change
- `docs/` — Documentation only
- `chore/` — Maintenance, dependencies, tooling

### During Development
- Work in your branch, never commit directly to `main`/`master`.
- Make atomic, conventional commits as you complete incremental milestones.
- Keep commits small and testable.

### Completing Work
Once you make sure you did not accidentally check in any extra files, and your changes look good to you, open a PR with:
1. **Descriptive title**: Conventional commit format (e.g., `feat(auth): add OAuth2 provider support`)
2. **Body sections**:
   - Summary of changes
   - Testing approach and coverage status
   - Breaking changes (if any)
3. **Inline comments**: Add review comments on critical or non-obvious code sections using `gh pr comment`.
```bash
gh pr create --title "feat(scope): description" --body "$(cat <<'EOF'
## Summary
- What this PR accomplishes and/or key changes made.

## Testing
- Testing approach.
- Coverage status.

## Review Notes
- Any architectural decisions.
- Potential impacts on other components.
- Areas needing careful review, if any.
- Discussion of performance implications, if any.
- Comparative analysis with alternative approaches, if relevant.

## Breaking Changes
- List any breaking changes here, or do not add this section at all. Only add this section if the project CLAUDE.md specifically requires documenting breaking changes.
EOF
)"

# Add inline comments for complex sections (only for complex or non-obvious code)
gh api repos/{owner}/{repo}/pulls/{pr}/comments -f body="Explanation of this section" -f path="src/file.py" -f line=42
```

### Handling Review Feedback
When responding to PR review comments:
- Always add new commits (do not amend or force-push during review).
- Use descriptive commit messages: `fix: address review feedback on error handling`.
- Squash commits on merge if the repository is configured to do so.

### Worktree Cleanup
After your PR merges, clean up the worktree:
```bash
git worktree remove .worktrees/feature-name
git branch -d feature/descriptive-name
```

### Conflict Resolution
When your branch conflicts with `main` (or the target branch):
- Rebase your branch onto the latest `main` (i.e. target branch) before opening or updating a PR.
- If multiple worktrees have conflicting changes, coordinate via `## Session Notes` in `PROJECT.md` (see below).

---

## Project Planning & `PROJECT.md` Management

### Creating the Initial Plan

Given the initial description of the project, create a `PROJECT.md` file that summarizes your understanding of the project, its goals, and a detailed step-by-step plan to implement it.

Maintain this file with hierarchical check boxes for all non-trivial tasks and/or steps.

If you do not have enough information to create a initial plan, create a preliminary plan and interview me with what you know to fill in the blanks. As you go through the process, when you reach a stage where you feel like you can create a plan with enough details, you may:
- Treat any remaining uncertain areas as work steps (discovery tasks),
- Add them to the "Status" section as steps,
- Refine them later during development.

### Structure of the `PROJECT.md` File
```markdown
# Overview

A few paragraphs describing your understanding of the project, overall project goals and context.

# Goals

- List goals and success criteria.
- This is a living list and will evolve over time.
- As you make progress, new goals may emerge or existing ones may change.

# Non-Goals

- List any non-goals to clarify scope.
- If you are not clear about non-goals initially, no need to add this section until you have clarity.

# Status

## Current Sprint

### Feature: Description
- [ ] Step 1: Foundation work
  - [ ] Substep 1a
  - [ ] Substep 1b
- [ ] Step 2: Core implementation
- [ ] Step 3: Testing to 100% coverage
- [ ] Step 4: Performance review and optimization

## Completed
- [x] Previous completed items (move here, don't delete)

## Session Notes
- [2024-01-11] Accumulate notes here as you work on the project.
- [2024-01-10] Finish each session with a brief summary of what was done, blockers, next steps.
```

### Rules
1. **Never recreate** `PROJECT.md` — update existing content.
2. **Update immediately** as work progresses — never defer to the end of session. This is **very important** - update it as you go.
3. **Check off steps** with `[x]` the moment they're complete.
4. **Break down steps** as understanding develops.
5. **Document decisions** and deviations from the original plan.
6. **Reflect true state** — `PROJECT.md` **must** always show current project status.
7. **Never include** `PROJECT.md` in a PR - it is for your internal use only until project completion.

### Session Handoff
When finishing a session or before context becomes stale:
1. Ensure `PROJECT.md` is fully up-to-date with current progress.
2. Commit or stash any work-in-progress.
3. Add a brief summary note under `## Session Notes` in `PROJECT.md`, e.g.:
   ```markdown
   ## Session Notes
   - [2024-01-15] Completed auth module, starting on API integration. Blocked on OAuth config.
   ```

---

## Resuming Work on Existing Projects

When starting a new session on a project with existing code:

1. **Read `PROJECT.md` first** — Understand current state, goals, and what's in progress.
2. **Check `## Session Notes`** — Review context from previous sessions, especially blockers.
3. **Review recent commits** — Run `git log --oneline -20` to understand recent momentum.
4. **Understand before modifying** — Read existing code before making changes. Don't "improve" code you don't understand sufficiently.
5. **Don't restart from scratch** — Build on existing work; refactor incrementally if necessary.

If the project has no `PROJECT.md` file, create one by analyzing the codebase and documenting your understanding before making changes.

---

## When to Ask for Clarification

Pause and ask before proceeding when:
1. **Ambiguous requirements** affect architecture or design decisions.
2. **Security-sensitive choices**; e.g. authentication, authorization, data handling.
3. **Destructive operations** like deleting data, dropping tables, removing files.
4. **Significant trade-offs** where multiple valid approaches exist with different implications.
5. **Scope uncertainty** — unclear whether something is in or out of scope. Is it a goal, or a step towards an existing goal, or a non-goal?
6. **External integrations** — unclear API contracts or third-party dependencies.

When in doubt, ask. A brief clarification is cheaper than rework. Any clarification resolving your confusion about (1), (4) or (5) **must** end up, in some form, at some appropriate section of the `PROJECT.md` file.

---

## Incremental Development Approach

### Planning Principles
1. **Testability drives boundaries**: Each step **must** be independently testable.
2. **Small, atomic steps**: Prefer more smaller steps over fewer large ones.
3. **Test infrastructure first**: The first milestone is always achieving 100% test coverage infrastructure.
4. **Maintain coverage**: Every PR **must** maintain 100% coverage. Use `# pragma: no cover` only when truly necessary or justifiable. For cases that warrant the use of this escape hatch, you **must** document your justification under the `Session Notes` section in the `PROJECT.md` file - AND mention these exemptions when you finish the project.

### Step Sequence Template
1. Set up testing infrastructure and CI hooks.
2. Implement core types/interfaces with tests.
3. Implement functionality incrementally, tests first.
4. Integration tests for component interactions.
5. Review your work with respect to performance and computational complexity. Identify and fix bottlenecks or suboptimal algorithms and/or data structures. Iterate, as necessary, to fix.
6. **Final step (always)**: Review your work with respect to idiomatic programming and succinctness (not in comments or docstrings, in code). Iterate, as necessary, to find the best form.

### Commit Discipline
- Run tests, type-checking (when applicable) and any other checks before every commit.
- Use concise conventional commits: `type(scope): description`
- Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- For larger commits, add explanation paragraphs, e.g.:
  ```
  feat(parser): add streaming JSON support

  This enables processing of large files without loading entirely into memory.
  Uses a state-machine approach to handle partial reads across chunk boundaries.
  ```

---

## Language-Specific Tooling

### Python
**Always use the latest stable Python version** (currently 3.14+).

#### Toolchain
- **Package manager**: `uv` (not `pip`, `poetry`, or `pipenv`)
  - *IMPORTANT*: Activate the project's virtual environment as a first, one-time step in **every session** before you run any Python code:
  ```bash
  source .venv/bin/activate
  ```
- **Linting/Formatting**: `ruff` (replaces black, isort, flake8)
- **Type checking**: `mypy` (strict mode)
- **Testing**: `pytest` with `pytest-cov`, `pytest-asyncio`
- **Hooks**: `pre-commit`

**Simple `pyproject.toml` baseline**:
```toml
[project]
requires-python = ">=3.14"

[dependency-groups]
dev = ["pre-commit", "ruff", "mypy", "pytest", "pytest-cov"]

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "D"]

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ruff.format]
quote-style = "double"

[tool.mypy]
strict = true

[tool.coverage.run]
branch = true

[tool.coverage.report]
fail_under = 100
```

**Simple `.pre-commit-config.yaml` baseline**:
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.1
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.14.1
    hooks:
      - id: mypy
        additional_dependencies: []  # Add type stubs as needed
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
```

Note that the versions above may be out of date; always use the latest stable versions unless the project specifies otherwise.

**Style conventions**:
- Line length: 100 characters
- Quotes: double quotes (`"string"`)
- Docstrings: Google style, always present on public APIs
- Type hints: Complete coverage, use modern syntax (`X | None` not `Optional[X]`)
- Imports: stdlib → third-party → relative (enforced by ruff `I`)
- Modules: Define `__all__` explicitly
- Naming: `snake_case` functions, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, `_private` prefix

### C/C++
**Always use the latest stable standard** (currently C++23).

#### Toolchain
- **Build system**: `xmake`
- **Compiler**: Latest GCC or Clang with full C++23 support
- **Testing**: Leverage xmake targets

**xmake.lua baseline**:
```lua
set_languages("c++23")
add_rules("mode.debug", "mode.release")
set_policy("build.c++.modules", true)

target("lib")
    set_kind("static")
    add_files("src/*.cpp", "modules/*.cppm")

target("test")
    set_kind("binary")
    add_deps("lib")
    add_files("test/*.cpp")
```

**Style conventions**:
- Use zero-cost abstractions where applicable. For example, avoid `std::function` when there is an alternative that does not increase the complexity significantly.
- CRTP for static polymorphism (avoid virtual functions where possible)
- C++ concepts for template constraints
- `std::optional` for nullable returns
- `snake_case` methods, `PascalCase` classes, `_private` prefix
- Modules (`.cppm`) for clean interfaces

### Rust
**Follow Apache DataFusion conventions** (PMC-level standards).

#### Toolchain
- **Package manager**: `cargo`
- **Linting**: `clippy` (pedantic)
- **Formatting**: `rustfmt`
- **Testing**: `cargo test` with `cargo-llvm-cov` for coverage

**Cargo.toml baseline**:
```toml
[lints.rust]
unsafe_code = "deny"

[lints.clippy]
pedantic = "warn"
```

**Style conventions**:
- Follow Rust API guidelines
- Comprehensive error types with `thiserror`
- Property-based testing with `proptest` where applicable
- Documentation tests for public APIs

---

## Dependency Policy

When adding new dependencies:
1. **Prefer stdlib** — Use standard library features over external packages when reasonable.
2. **Evaluate before adding**:
   - Maintenance status (recent commits, responsive maintainers)
   - License compatibility with the project (F/OSS licenses are always acceptable unless the project specifies otherwise)
   - Transitive dependency footprint (very important, consider vendoring in the functionality if too large)
3. **Version pinning**:
   - During early development, before the first public release: Use the latest versions unless the project specifies otherwise. In case of conflicts or instability, you may use bounds if necessary.
   - After first release: Pin exact versions in applications, allow ranges in libraries.

---

## Code Quality Standards

### Before Every Commit
```bash
# Python
uv run ruff check --fix .
uv run ruff format .
uv run mypy .
uv run pytest --cov --cov-fail-under=100

# C++
xmake build
xmake run test

# Rust
cargo fmt --check
cargo clippy -- -D warnings
cargo test
cargo llvm-cov --fail-under-lines 100
```

### Testing Philosophy
1. Test infrastructure is milestone zero — nothing ships without it.
2. 100% coverage is the baseline, not the goal.
3. Tests document behavior — write them as specifications.
4. Use `# pragma: no cover` only for genuinely untestable code (OS-specific branches, defensive assertions).
5. Integration tests complement, not replace, unit tests.
6. Bugfixes, refactors and API changes often create testing gaps or affect/invalidate existing tests. When working on such tasks, you **must** diligently scan for all relevant tests and update them accordingly AND add any missing tests to maintain 100% coverage.

**When can you defer tests?**:
- For exploratory prototypes or spikes - **must** be clearly marked as such.
- Proof-of-concept code that will be rewritten.
- Scripts intended for one-time use.

In these cases, add a `# TODO: Add tests before production use` comment. If you decide to adopt the code in production later, add a high-priority work item to `PROJECT.md` to add test coverage. Unless the project specifies otherwise, house all such code in one single folder (e.g., `scripts/`).

### Code Style Philosophy
1. **Idiomatic first**: Use language-native patterns and standard library features.
2. **Succinct over verbose**: Three clear lines beat a premature abstraction.
3. **No over-engineering**: Solve the current problem, not hypothetical futures.
4. **Delete unused code**: No backwards-compatibility shims for removed features.

---

## Error Handling

### Exception Design
For languages with exceptions:
1. **Use domain-specific hierarchies** — Create a base exception for your module (e.g., `AgentException`), then specific subclasses.
2. **Always chain causes when possible** — Use `raise NewError("message") from original_error` to preserve the context.
3. **Include actionable context** — Error messages **must** help diagnose the problem.

### Error Message Quality
Good error messages answer: *What failed? Why? What values were involved? How to fix?*

```python
# Bad
raise ValueError("Invalid input")

# Good
raise ValueError(f"Cannot resolve forward reference {py_type.__forward_arg__!r}") from e

# Bad
raise ToolArgumentError("Conversion failed")

# Good
raise ToolArgumentError(f"Invalid value for parameter '{name}': expected {expected_type}") from e
```

### Cause Chain Serialization
When serializing exceptions (e.g., for APIs or logs), preserve the chain when possible. Python example:
```python
if obj.__cause__ is not None:
    result["caused_by"] = serialize_exception(obj.__cause__)
```

---

## Security Basics

1. **Validate at boundaries** — Sanitize all user input and external API responses at system entry points.
2. **Never hardcode secrets** — Use environment variables or secret management tools; never commit credentials.
3. **Escape output appropriately**:
   - SQL: Use parameterized queries, never string interpolation.
   - HTML: Escape user content to prevent XSS.
   - Shell: Use proper quoting or avoid shell interpolation entirely.
4. **Principle of least privilege** — Request only necessary permissions; avoid running as root/admin.
5. **Dependency vigilance** — Check for known vulnerabilities before any release (`uv pip audit`, `cargo audit`, `npm audit`) and act accordingly (e.g. find alternatives, change versions).

---

## Performance Mindset

Every implementation plan must end with a performance review step:

1. **Identify hot paths**: Where will this code run frequently?
2. **Check complexity**: Are algorithms optimal for the data size?
3. **Profile if uncertain**: If uncertain, measure before optimizing.
4. **Common pitfalls**:
   - O(n²) when O(n log n) or O(n) exists.
   - Repeated allocations in loops.
   - Blocking I/O in async contexts.
   - Unnecessary copying of large structures.

Fix issues found before marking work complete.

---

## Quick Reference

| Task | Command |
|------|---------|
| Create worktree | `git worktree add .worktrees/name -b branch-name` |
| Run Python tests | `uv run pytest --cov` |
| Run Python checks | `uv run ruff check . && uv run mypy .` |
| Build C++ | `xmake build` |
| Run C++ tests | `xmake run test` |
| Run Rust checks | `cargo clippy && cargo test` |
| Create PR | `gh pr create --title "type: desc" --body "..."` |
| Add PR comment | `gh api repos/OWNER/REPO/pulls/N/comments -f ...` |

