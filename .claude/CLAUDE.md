# CLAUDE.md - Universal Project Guidelines

This document contains instructions and guidelines for Claude instances working on software development projects.

**Override mechanism**: If a project contains its own `CLAUDE.md` file, those project-specific instructions take precedence. When conflicts exist, follow the project-specific instructions.

## Sandbox Environment

You operate in a macOS `sandbox-exec` environment with restricted file access:

- **Read Access**: Project directory, system paths (read-only)
- **Write Access**: Project directory, `/tmp`, `~/.cache`, `~/.claude`
- **Network**: Full access
- **Blocked**: Paths outside the above, sensitive files (`.env`, credentials, secrets)

Do not attempt to access files outside these boundaries - commands will fail (often with an error, but may do so silently or hang).

## Multi-Instance Workflow (Worktrees & PRs)

Multiple Claude instances may work on the same repository concurrently. Follow this workflow:

### Setup (once per repository)
```bash
# Create worktrees directory and add to .gitignore
mkdir -p .worktrees
echo ".worktrees/" >> .gitignore
```

### Starting Work
You **must** start a new project by creating a new git worktree/branch. **Never** work directly in the main project directory unless the user instructs otherwise.
```bash
# Create a worktree for your task (stays within project directory)
git worktree add .worktrees/feature-name -b feature/descriptive-name

# Work exclusively in your worktree
cd .worktrees/feature-name
```

**Branch naming conventions**:
- `feature/` - New functionality
- `fix/` - Bug fixes
- `refactor/` - Code restructuring without behavior change
- `docs/` - Documentation only
- `chore/` - Maintenance, dependencies, tooling

### During Development
- Work in your branch, never commit directly to `main`/`master`.
- Conform to existing coding style and commenting style/language.
- Make atomic, conventional commits as you complete incremental milestones. **Never** defer a commit once a step is complete.
- Keep commits small and testable.

### Completing Work
Follow this checklist when completing your work with a PR:
- **Make sure** you did not accidentally check in any extra files (like any temporary files or the project file `PROJECT.md`).
- **Make sure** you did the performance/computational complexity *and* idiomatic programming/succinctness self-reviews (more on these below), and the final state of the code looks good to you.
- **Make sure** that all project documentation (e.g., the `README.md` file, anything under `docs/`) reflect your changes. This step is **very important**, as failure to do this results in documentation rot over time.
Once you are done with this checklist, open a PR with:
1. **Descriptive title**: Conventional commit format (e.g., `feat(auth): add OAuth2 provider support`)
2. **Body sections**:
   - Summary of changes
   - Testing approach and coverage status
   - Review notes
   - Breaking changes (if any)
3. **Guiding comments**: Add review comments on critical or non-obvious code sections using `gh api` (example below).
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
   - List any breaking changes here. Do not add this section if there aren't any.
   - Only add this section if project instructions specifically require documenting breaking changes.
   EOF
   )"
   # Add inline comments for complex sections (only for complex or non-obvious code)
   gh api repos/{owner}/{repo}/pulls/{pr}/comments -f body="Explanation of this section" -f path="src/file.py" -f line=42
   ```

### Handling Review Feedback
When responding to PR review comments:
- Always add new commits (do not amend or force-push during review).
- Use descriptive commit messages: `fix: address review feedback on error handling`.
- When you make a new commit to address a review, update the PR body to reflect the change if necessary. **Always** keep the PR body accurate and up-to-date with the changes in the PR.
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
- If multiple worktrees have conflicting changes, coordinate via `Session Notes` in `PROJECT.md` (see below).

## Project Planning and Management

### Creating the Initial Plan

Given the initial description of the project, create a `PROJECT.md` file (*in the project worktree*) that summarizes your understanding of the project, its goals, and a detailed step-by-step plan to implement it.

Maintain this file with hierarchical check boxes for all non-trivial tasks and/or steps.

If you do not have enough information to create a initial plan, create a preliminary plan and interview the user with what you know to fill in the blanks. As you go through the process, when you reach a stage where you feel like you can create a plan with enough details, you may:
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
1. **Never recreate** `PROJECT.md` - update existing content.
2. **Update immediately** as work progresses - never defer to the end of session. This is **very important** - update it as you go.
3. **Check off steps** with `[x]` the moment they're complete.
4. **Break down steps** as understanding develops.
5. **Document decisions** and deviations from the original plan.
6. **Reflect true state** - `PROJECT.md` **must** always show current project status.
7. **Never include** `PROJECT.md` in a PR - it is for your internal use only until project completion.

### Session Handoff
When finishing a session or before context becomes stale:
1. Ensure `PROJECT.md` is fully up-to-date with current progress.
2. Commit or stash any work-in-progress.
3. Add a brief summary note under `Session Notes` in `PROJECT.md`, e.g.:
   ```markdown
   ## Session Notes
   - [2024-01-15] Completed auth module, starting on API integration. Blocked on OAuth config.
   ```

## Resuming Work on Existing Projects

When starting a new session on a project with existing code:

1. **Read `PROJECT.md` first** - Understand current state, goals, and what's in progress.
2. **Check `Session Notes`** - Review context from previous sessions, especially blockers.
3. **Review recent commits** - Run `git log --oneline -20` to understand recent momentum.
4. **Understand before modifying** - Read existing code before making changes. Don't "improve" code you don't understand sufficiently.
5. **Don't restart from scratch** - Build on existing work; refactor incrementally if necessary.

If the project has no `PROJECT.md` file, create one by analyzing the codebase and documenting your understanding before making changes.

## When to Ask for Clarification

Pause and ask before proceeding when:
1. **Ambiguous requirements** affect architecture or design decisions.
2. **Security-sensitive choices**; e.g. authentication, authorization, data handling.
3. **Destructive operations** like deleting data, dropping tables, removing files.
4. **Significant trade-offs** where multiple valid approaches exist with different implications.
5. **Scope uncertainty** - unclear whether something is in or out of scope. Is it a goal, or a step towards an existing goal, or a non-goal?
6. **External integrations** - unclear API contracts or third-party dependencies.

When in doubt, ask. A brief clarification is cheaper than rework. Any clarification resolving your confusion about (1), (4) or (5) **must** end up, in some form, at some appropriate section of the `PROJECT.md` file.

## Incremental Development Approach

### Planning Principles
1. **Testability drives boundaries**: Each step **must** be independently testable.
2. **Small, atomic steps**: Prefer more smaller steps over fewer large ones.
3. **Test infrastructure first**: The first milestone is always achieving 100% test coverage infrastructure.
4. **Always maintain coverage**: Every PR **must** maintain 100% coverage - plan and design accordingly. Use `# pragma: no cover` only when truly necessary or justifiable. For cases that warrant the use of this escape hatch, you **must** document your justification under the `Session Notes` section in the `PROJECT.md` file - AND mention these exemptions when you finish the project.
5. **Always keep documentation up-to-date**: Every PR **must** update all relevant documentation - plan accordingly. Documentation **must never** diverge from what is in the codebase.

### Step Sequence Template
1. Set up testing infrastructure and CI hooks.
2. Implement core types/interfaces with tests.
3. Implement functionality incrementally, **always with their tests**.
4. Integration tests for component interactions.
5. Review your work with respect to performance and computational complexity. Identify and fix bottlenecks or suboptimal algorithms and/or data structures. Iterate, as necessary, to fix.
6. **Final step (always)**: Review your work with respect to idiomatic programming and succinctness (not in comments or docstrings, in code). Iterate, as necessary, to find the best form.

### Commit Discipline
- **Always** commit after every step is complete.
- Run tests, type-checking (when applicable) and any other checks before every commit.
- Use concise conventional commits: `type(scope): description`
- Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- Unless the commit is tiny, add an explanation paragraph, e.g.:
  ```
  feat(parser): add streaming JSON support

  This enables processing of large files without loading entirely into memory.
  Uses a state-machine approach to handle partial reads across chunk boundaries.
  ```

## Language-Specific Tooling

### Python
**Always use the latest stable Python version** (currently 3.14+).

#### Toolchain
- **Package manager**: `uv` (not `pip`, `poetry`, or `pipenv`)
  - *IMPORTANT*: After you create your worktree, create a virtual environment for your worktree via `uv` and activate it as a first, one-time step in **every session** before you run any Python code:
    ```bash
    # Create virtual environment for the worktree and activate:
    uv venv
    source .venv/bin/activate
    ```
- **Linting/Formatting**: `ruff` (replaces black, isort, flake8)
- **Type checking**: `mypy` (strict mode)
- **Testing**: `pytest` with the following plugins:
  - `pytest-asyncio` to test async functionality,
  - `pytest-cov` for coverage,
  - `syrupy` for snapshots,
  - `pytest-rerunfailures` for non-deterministic or flaky tests,
  - `pytest-examples` for documentation tests
- **Hooks**: `pre-commit`
- **Documentation**: `mkdocs` with the following plugins:
  - `mkdocs-material` for Material theme,
  - `mkdocstrings[python]` for documentation generation,
  - `markdown-exec` to facilitate testable examples

**Simple `pyproject.toml` baseline**:
```toml
[project]
name = "myproject"
version = "0.1.0"
readme = "README.md"
requires-python = ">=3.14"

[dependency-groups]
dev = ["pre-commit", "ruff", "mypy", "pytest", "pytest-asyncio", "pytest-cov", "syrupy"]
docs = ["mkdocs", "mkdocs-material", "mkdocstrings[python]"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build]
sources = ["src"]

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "D"]

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ruff.format]
docstring-code-format = true
docstring-code-line-length = 88

[tool.mypy]
strict = true
ignore_missing_imports = true
pretty = true

[tool.coverage.run]
branch = true
omit = [
  "*/tests/*",
  "*/__pycache__/*",
  ".venv/*",
]

[tool.coverage.report]
fail_under = 100 # Enable after initial development; remove during prototyping
show_missing = true
skip_empty = true
precision = 2
exclude_also = [
  '^\s+case\s+.*?\s+as\s+_unreachable:\s*$',
  '^\s+assert_never\(.*?\)\s*$',
]

[tool.coverage.html]
directory = "htmlcov"

[tool.pytest.ini_options]
asyncio_mode = "auto"
markers = [
  "integration: marks tests as integration tests requiring real API calls (deselect with '-m \"not integration\"')",
]
addopts = "-v -m \"not integration\""
testpaths = ["src", "tests"]
```

**Simple `.pre-commit-config.yaml` baseline**:
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.10
    hooks:
      - id: ruff-format
      - id: ruff
        args: [--fix]
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.19.1
    hooks:
      - id: mypy
        additional_dependencies: ["pytest"]
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: trailing-whitespace
        exclude: '\.ambr$'  # Exclude syrupy snapshot files (preserve docstring formatting)
      - id: end-of-file-fixer
      - id: check-yaml
        name: check-yaml (mkdocs.yml)
        files: '^mkdocs\.yml$'
        args: [--unsafe]  # Use PyYAML to allow anchors
      - id: check-yaml
        name: check-yaml (general)
        exclude: '^mkdocs\.yml$'
      - id: check-added-large-files
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest
        language: python
        types: [python]
        stages: [manual]
        additional_dependencies: [pytest, pytest-cov]
```

Note that the versions above may be out of date; always use the latest stable versions unless the project specifies otherwise.

**Snapshot testing**:
- Snapshot files (`.ambr`) are stored in `__snapshots__/` directories co-located with tests
- Update snapshots with: `uv run pytest --snapshot-update`

**Project-specific automation**:

Add local pre-commit hooks for project-specific automation. For example, to automatically link/update section(s) of the `README.md` file to the project documentation, one can use:
```yaml
repos:
  - repo: local
    hooks:
      - id: update-readme-structure
        name: update-readme-structure
        entry: python -m docs.update_readme_structure
        language: python
        pass_filenames: false
        files: ^(src/.*\.py|docs/.*\.py)$  # Only run when relevant files change
```

This pattern is useful for:
- Keeping generated files in sync
- Running project-specific validation
- Ensuring documentation matches code

#### Style Conventions
- Line length: 100 characters
- Quotes: double quotes (`"string"`)
- Docstrings: Google style, always present on public APIs
- Type hints: Complete coverage, use modern syntax:
  - Use `X | None`, not `Optional[X]`
  - Prefer inline generic type variables to explicit definitions when possible
  - Use `Self` (from `typing`) for methods returning the same type
  - Use type alias syntax (PEP 695) when appropriate:
    ```python
    type JsonValue[T = None | bool | int | float | str] = (
        T | Sequence[JsonValue[T]] | Mapping[str, JsonValue[T]]
    )
    ```
- Use `Protocol` classes for structural typing when you need an interface without inheritance:
  - Use `@runtime_checkable` if `isinstance` checks are necessary
  - Protocol methods use `...` (ellipsis) as body, with `# pragma: no cover`
  - Prefer protocols over ABCs when there is no implementation sharing
- Use pattern matching with exhaustiveness checks (i.e. `case _ as _unreachable: assert_never(...)`)
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
    add_files("src/*.cpp")
    add_files("modules/*.cppm", {public = true})

target("test")
    set_kind("binary")
    add_deps("lib")
    add_files("test/*.cpp")
```

#### Style Conventions
- Use zero-cost abstractions where applicable. For example, avoid `std::function` when there is an alternative that does not increase the complexity significantly.
- Avoid virtual functions via CRTP to use static polymorphism when possible *and* the resulting complications in type signatures only affect a small subset of the codebase.
- C++ concepts for template constraints
- `std::optional` for nullable returns
- `snake_case` methods, `PascalCase` classes, `_private` prefix
- Modules (`.cppm`) for clean interfaces

#### Usage Notes

On macOS, the default `clang` does not support C++ modules yet. Use `xmake f --toolchain=gcc-15` to explicitly select the GCC toolchain.

### Rust
**Always use the latest stable Rust version** (currently 1.93+). Unless these universal guidelines or project-specific instructions specify otherwise, **follow Apache DataFusion conventions** (PMC-level standards).

#### Toolchain
- **Package manager**: `cargo`
- **Linting**: `clippy` (pedantic)
- **Formatting**: `rustfmt`
- **Testing**: `cargo test` with:
  - `cargo-tarpaulin` for coverage,
  - `cargo-insta` for snapshots,
  - `cargo test --doc` for documentation tests

**Cargo.toml baseline**:
```toml
[workspace]
resolver = "3"  # Necessary for edition 2024
members = ["crates/*"]

[workspace.package]
version = "0.1.0"
edition = "2024"
rust-version = "1.93"
license = "LicenseRef-Proprietary" # Use appropriate license here

[workspace.dependencies]
thiserror = "2"

[workspace.lints.rust]
unsafe_code = "deny"
unused_qualifications = "deny"

[workspace.lints.clippy]
large_futures = "warn"
used_underscore_binding = "warn"
or_fun_call = "warn"
uninlined_format_args = "warn"
inefficient_to_string = "warn"
needless_pass_by_value = "warn"
allow_attributes = "warn"

[profile.release]
codegen-units = 1
lto = true
strip = true
```

If there are member crates, use the following baseline:
```toml
[package]
name = "mylib"
version = "0.1.0"
edition = { workspace = true }
license = { workspace = true }

[lints]
workspace = true

[dependencies]
thiserror = { workspace = true }
```

#### Style Conventions
- Follow Rust API guidelines
- Comprehensive error types with `thiserror`
- Property-based testing with `proptest` where applicable
- Documentation tests for public APIs

## Dependency Policy

When adding new dependencies:
1. **Prefer stdlib** - Use standard library features over external packages when reasonable.
2. **Evaluate before adding**:
   - Maintenance status (recent commits, responsive maintainers)
   - License compatibility with the project (F/OSS licenses are always acceptable unless the project specifies otherwise)
   - Transitive dependency footprint (very important, consider vendoring in the functionality if too large)
3. **Version pinning**:
   - During early development, before the first public release: Use the latest versions unless the project specifies otherwise. In case of conflicts or instability, you may use bounds if necessary.
   - After first release: Pin exact versions in applications, allow ranges in libraries.

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
1. Test infrastructure is milestone zero - nothing ships without it.
2. 100% coverage is the baseline, not the goal.
3. Tests document behavior - write them as specifications.
4. Use `# pragma: no cover` only for genuinely untestable code (OS-specific branches, defensive assertions).
5. **Always** expect full contents of a variable unless it is dynamic. Use snapshotting for:
   - Serialized data structures
   - Error message formatting
   - Complex JSON schemas or API responses
   - Anything where the expected output is large and change-tracking is valuable
6. Integration tests complement, not replace, unit tests.
7. Bugfixes, refactors and API changes often create testing gaps or affect/invalidate existing tests. When working on such tasks, you **must** diligently scan for all relevant tests and update them accordingly AND add any missing tests to maintain 100% coverage.
8. Think of documentation examples as minimal E2E tests (and write them as such). Unless there is strong reason as to otherwise, they **must** be executable and run as part of documentation tests.

**When can you defer tests?**
- For exploratory prototypes or spikes - **must** be clearly marked as such.
- Proof-of-concept code that will be rewritten.
- Scripts intended for one-time use.

In these cases, add a `# TODO: Add tests before production use` comment. If you decide to adopt the code in production later, add a high-priority work item to `PROJECT.md` to add test coverage. Unless the project specifies otherwise, house all such code in one single folder (e.g., `scripts/`).

### Code Style Philosophy
1. **Idiomatic first**: Use language-native patterns and standard library features.
2. **Succinct over verbose**: Three clear lines beat a premature abstraction.
3. **No over-engineering**: Solve the current problem, not hypothetical futures.
4. **Delete unused code**: No backwards-compatibility shims for removed features.

## Error Handling

### Exception Design
For languages with exceptions:
1. **Use domain-specific hierarchies** - Create a base exception for your module (e.g., `AgentException`), then specific subclasses.
2. **Always chain causes when possible** - Use `raise NewError("message") from original_error` to preserve the context.
3. **Include actionable context** - Error messages **must** help diagnose the problem.

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

## Security Basics

1. **Validate at boundaries** - Sanitize all user input and external API responses at system entry points.
2. **Never hardcode secrets** - Use environment variables or secret management tools; never commit credentials.
3. **Escape output appropriately**:
   - SQL: Use parameterized queries, never string interpolation.
   - HTML: Escape user content to prevent XSS.
   - Shell: Use proper quoting or avoid shell interpolation entirely.
4. **Principle of least privilege** - Request only necessary permissions; avoid running as root/admin.
5. **Dependency vigilance** - Check for known vulnerabilities before any release (`uv pip audit`, `cargo audit`, `npm audit`) and act accordingly (e.g. find alternatives, change versions).

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

## Agent Workflow Checklist

### Phase 1A: New Project Setup

Use this when starting a brand new project from scratch.

- [ ] **Create worktree**:
  ```bash
  mkdir -p .worktrees
  git worktree add .worktrees/project-name -b feature/initial-implementation
  cd .worktrees/project-name
  ```

- [ ] **Set up `.gitignore`** with language-specific patterns:
  - Python: `.worktrees/`, `.venv/`, `__pycache__/`, `*.pyc`, `.coverage`, `htmlcov/`, `.pytest_cache/`, `PROJECT.md`
  - Rust: `.worktrees/`, `target/`, `PROJECT.md`
  - C++: `.worktrees/`, `build/`, `.xmake/`, `PROJECT.md`

- [ ] **Create initial `PROJECT.md`** with preliminary understanding (see structure in [Project Planning and Management](#project-planning-and-management))

- [ ] **Clarify requirements** if necessary (see [When to Ask for Clarification](#when-to-ask-for-clarification) section)

- [ ] **Create project structure and config files**:
  - Python: `pyproject.toml`, `src/pkgname/__init__.py`, `tests/`, `README.md`
  - Rust: `Cargo.toml`, `crates/*/src/lib.rs`
  - C++: `xmake.lua`, `src/`, `modules/`, `test/`

- [ ] **Set up environment**:
  - Python: `uv venv && source .venv/bin/activate && uv sync --group dev`
  - Rust: `cargo build`
  - C++: `xmake f --toolchain=gcc-15 && xmake build`

- [ ] **Set up pre-commit hooks** (if applicable):
  ```bash
  uv run pre-commit install
  ```

- [ ] **Initial commit**:
  ```bash
  git add -A && git commit -m "chore: initial project setup"
  ```

- [ ] **Refine `PROJECT.md`** with detailed implementation plan

### Phase 1B: Resume Existing Project

Use this when continuing work on an existing project.

- [ ] **Navigate to worktree**: `cd .worktrees/project-name`

- [ ] **Activate environment**:
  - Python: `source .venv/bin/activate`

- [ ] **Read `PROJECT.md`** - understand current state, goals, what's in progress

- [ ] **Check session notes** - review blockers, context from previous sessions

- [ ] **Review recent commits**: `git log --oneline -10`

### Phase 2: Development Loop

For each task:

- [ ] **Mark task in-progress** in `PROJECT.md`

- [ ] **Implement** the change (with tests)

- [ ] **Run checks**:
  - Python:
    ```bash
    uv run ruff format . && uv run ruff check --fix .
    uv run mypy .
    uv run pytest --cov
    ```
  - Rust:
    ```bash
    cargo fmt && cargo clippy -- -D warnings && cargo test
    ```
  - C++:
    ```bash
    xmake build && xmake run test
    ```

- [ ] **Commit** with conventional message:
  ```bash
  git add -A && git commit -m "type(scope): description"
  ```

- [ ] **Mark as complete** in `PROJECT.md`

### Phase 3: Review

Before finalizing:

- [ ] **Performance review** (see [Performance Mindset](#performance-mindset))

- [ ] **Idiomatic code review** (see [Code Style Philosophy](#code-style-philosophy))

- [ ] **Security review** if applicable (see [Security Basics](#security-basics))

- [ ] **Update documentation** - Ensure `README.md`, `docs/`, docstrings reflect current state

- [ ] **Verify clean state** - Ensure no unintended files and/or secrets are in the changeset

### Phase 4: PR & Cleanup

- [ ] **Push branch** (if remote exists):
  ```bash
  git push -u origin type/descriptive-name
  ```

- [ ] **Create PR** (see [Completing Work](#completing-work) for template and inline comments)

- [ ] **Update `PROJECT.md`** Session Notes with summary

- [ ] **After merge**, clean up:
  ```bash
  git worktree remove .worktrees/task-name
  git branch -d type/descriptive-name
  ```

### Phase 5: Session Handoff

If ending session before project completion, go through the steps in [Session Handoff](#session-handoff).

