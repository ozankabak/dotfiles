#!/usr/bin/env bash
# Run on the host (not from inside sandbox-exec) to verify sensitive-read denies.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/agent-sandbox-sensitive.XXXXXXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/.ssh"
printf 'protected\n' > "$TEST_DIR/.env"
printf 'protected\n' > "$TEST_DIR/service.key"
printf 'protected\n' > "$TEST_DIR/.ssh/id_ed25519"
printf 'ordinary\n' > "$TEST_DIR/application.toml"

expect_denied() {
    local path="$1"
    if "$ROOT/scripts/agent-sandbox" --agent codex --target-dir "$TEST_DIR" -- \
        python3.14 -c 'import pathlib, sys; pathlib.Path(sys.argv[1]).read_text()' "$path"; then
        echo "Expected sensitive path to be denied: $path" >&2
        exit 1
    fi
}

expect_allowed() {
    local path="$1"
    "$ROOT/scripts/agent-sandbox" --agent codex --target-dir "$TEST_DIR" -- \
        python3.14 -c 'import pathlib, sys; pathlib.Path(sys.argv[1]).read_text()' "$path"
}

expect_denied "$TEST_DIR/.env"
expect_denied "$TEST_DIR/service.key"
expect_denied "$TEST_DIR/.ssh/id_ed25519"
expect_allowed "$TEST_DIR/application.toml"

echo "Agent sandbox sensitive-read verification passed."
