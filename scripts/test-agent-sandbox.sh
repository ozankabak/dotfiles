#!/usr/bin/env bash
# Comprehensive host-only verification for the agent-sandbox profile.

set -uo pipefail

if [[ "${1:-}" != "--agent" || ( "${2:-}" != "claude" && "${2:-}" != "codex" ) || $# -ne 2 ]]; then
    echo "Usage: $0 --agent <claude|codex>" >&2
    exit 1
fi

AGENT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_DIR="$(mktemp -d /tmp/agent-sandbox-test.XXXXXXXXXX)"
OUTSIDE_FILE="$(mktemp "$HOME/.agent-sandbox-test.XXXXXXXXXX")" || exit 1
TEMP_FILE="$(mktemp /tmp/agent-sandbox-temp.XXXXXXXXXX)" || exit 1
PROFILE_FILE="$TEST_DIR/profile.sb"
CODEX_HOME_DIR="$(mktemp -d "$HOME/.agent-sandbox-codex-home.XXXXXXXXXX")" || exit 1
OUTPUT_FILE="$TEST_DIR/output"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_DIR" "$OUTSIDE_FILE" "$TEMP_FILE" "$CODEX_HOME_DIR"' EXIT

mkdir -p "$TEST_DIR/config" "$TEST_DIR/.ssh" "$TEST_DIR/.aws" "$TEST_DIR/.gnupg"
printf 'protected\n' > "$TEST_DIR/.env"
printf 'protected\n' > "$TEST_DIR/config/.env.local"
printf 'protected\n' > "$TEST_DIR/config/service.pem"
printf 'protected\n' > "$TEST_DIR/config/service.key"
printf 'protected\n' > "$TEST_DIR/config/id_rsa_backup"
printf 'protected\n' > "$TEST_DIR/.ssh/id_ed25519"
printf 'protected\n' > "$TEST_DIR/.aws/credentials"
printf 'protected\n' > "$TEST_DIR/.gnupg/private-key"
printf 'ordinary\n' > "$TEST_DIR/config/application.toml"
run_sandbox() {
    "$ROOT/scripts/agent-sandbox" --agent "$AGENT" --target-dir "$TEST_DIR" -- \
        python3 -I -c "$@"
}

run_sandbox_with_codex_home() {
    env CODEX_HOME="$CODEX_HOME_DIR" "$ROOT/scripts/agent-sandbox" --agent "$AGENT" \
        --target-dir "$TEST_DIR" -- python3 -I -c "$@"
}

expect_status() {
    local expected="$1"
    local description="$2"
    shift 2

    if "$@" >"$OUTPUT_FILE" 2>&1; then
        actual=0
    else
        actual=1
    fi

    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((PASS++))
    else
        echo "✗ $description"
        echo "  expected exit status: $expected, got: $actual" >&2
        sed 's/^/  /' "$OUTPUT_FILE" >&2
        ((FAIL++))
    fi
}

expect_profile_contains() {
    local expected="$1"
    local description="$2"
    local pattern="$3"

    if [[ ! -f "$PROFILE_FILE" ]]; then
        echo "✗ $description" >&2
        echo "  effective profile was not rendered" >&2
        ((FAIL++))
        return
    fi

    if grep -Fq "$pattern" "$PROFILE_FILE"; then
        actual=0
    else
        actual=1
    fi

    if [[ "$actual" == "$expected" ]]; then
        echo "✓ $description"
        ((PASS++))
    else
        echo "✗ $description" >&2
        echo "  expected profile match: $expected, got: $actual" >&2
        ((FAIL++))
    fi
}

echo "=== Generated Profile ==="
if "$ROOT/scripts/agent-sandbox" --agent "$AGENT" --target-dir "$TEST_DIR" \
    --write-profile "$PROFILE_FILE" >"$OUTPUT_FILE" 2>&1; then
    echo "✓ render effective profile"
    ((PASS++))
else
    echo "✗ render effective profile" >&2
    sed 's/^/  /' "$OUTPUT_FILE" >&2
    ((FAIL++))
fi

expect_profile_contains 0 "includes local sensitive-file policy" "Prevent sensitive-file reads"
if [[ "$AGENT" == "claude" ]]; then
    expect_profile_contains 0 "includes Claude Keychain grant" "login.keychain-db"
else
    expect_profile_contains 1 "omits Claude Keychain grant" "login.keychain-db"
fi

echo ""
echo "=== Workspace Access ==="
expect_status 0 "allow ordinary workspace read" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).read_text()' \
    "$TEST_DIR/config/application.toml"
expect_status 0 "allow workspace write" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
    "$TEST_DIR/generated.txt"

echo ""
echo "=== Sensitive Workspace Reads ==="
for path in \
    "$TEST_DIR/.env" \
    "$TEST_DIR/config/.env.local" \
    "$TEST_DIR/config/service.pem" \
    "$TEST_DIR/config/service.key" \
    "$TEST_DIR/config/id_rsa_backup" \
    "$TEST_DIR/.ssh/id_ed25519" \
    "$TEST_DIR/.aws/credentials" \
    "$TEST_DIR/.gnupg/private-key"; do
    expect_status 1 "deny ${path#"$TEST_DIR/"} read" run_sandbox \
        'from pathlib import Path; import sys; Path(sys.argv[1]).read_text()' "$path"
done

echo ""
echo "=== Host and Temporary Paths ==="
expect_status 0 "allow system read" run_sandbox \
    'from pathlib import Path; Path("/etc/hosts").read_text()'
expect_status 1 "deny home-file read" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).read_text()' "$OUTSIDE_FILE"
expect_status 0 "allow temporary-file write" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
    "$TEMP_FILE"
expect_status 1 "deny system-file write" run_sandbox \
    'from pathlib import Path; Path("/etc/agent-sandbox-test").write_text("blocked")'

echo ""
echo "=== Runtime Compatibility ==="
expect_status 0 "allow standard-device I/O" run_sandbox \
    'from pathlib import Path; Path("/dev/null").read_text()'
expect_status 0 "allow multiprocessing primitives" run_sandbox \
    'from multiprocessing import Semaphore, shared_memory; semaphore = Semaphore(); shared = shared_memory.SharedMemory(create=True, size=1); shared.close(); shared.unlink()'
expect_status 0 "allow local DNS resolution" run_sandbox \
    'import socket; socket.getaddrinfo("localhost", None)'
if [[ "$AGENT" == "codex" ]]; then
    expect_status 0 "allow custom CODEX_HOME write" run_sandbox_with_codex_home \
        'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
        "$CODEX_HOME_DIR/config.toml"
fi

echo ""
echo "================================"
echo "Agent sandbox: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && echo "All tests passed!" || exit 1
