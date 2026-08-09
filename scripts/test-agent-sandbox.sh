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
expect_profile_contains 0 "includes ${AGENT} Keychain grant" "login.keychain-db"
expect_profile_contains 0 "includes ${AGENT} securityd grant" "com.apple.securityd"

echo ""
echo "=== Workspace Access ==="
expect_status 0 "allow ordinary workspace read" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).read_text()' \
    "$TEST_DIR/config/application.toml"
expect_status 0 "allow workspace write" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
    "$TEST_DIR/generated.txt"
expect_status 0 "allow workspace directory listing" run_sandbox \
    'from pathlib import Path; import sys; list(Path(sys.argv[1]).iterdir())' "$TEST_DIR"
expect_status 0 "allow workspace metadata" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).stat()' "$TEST_DIR"
expect_status 0 "allow workspace chmod" run_sandbox \
    'from pathlib import Path; import os; import sys; path = Path(sys.argv[1]); path.touch(); os.chmod(path, 0o644)' \
    "$TEST_DIR/.chmod-test"
expect_status 0 "allow workspace symlink" run_sandbox \
    'from pathlib import Path; import os; import sys; target = Path(sys.argv[1]); link = Path(sys.argv[2]); target.touch(); os.symlink(target, link)' \
    "$TEST_DIR/.link-target" "$TEST_DIR/.link"

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
expect_status 1 "deny ~/.zshrc read" run_sandbox \
    'from pathlib import Path; Path.home().joinpath(".zshrc").read_text()'
expect_status 1 "deny home directory listing" run_sandbox \
    'from pathlib import Path; Path.home().iterdir().__next__()'
expect_status 0 "allow temporary-file write" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
    "$TEMP_FILE"
expect_status 0 "allow temporary-directory listing" run_sandbox \
    'from pathlib import Path; list(Path("/tmp").iterdir())'
expect_status 0 "allow temporary-directory metadata" run_sandbox \
    'from pathlib import Path; Path("/tmp").stat()'
expect_status 0 "allow private temporary-file write" run_sandbox \
    'from pathlib import Path; path = Path("/private/tmp/agent-sandbox-test"); path.write_text("ok"); path.unlink()'
expect_status 0 "allow macOS temporary-file write" run_sandbox \
    'import tempfile; path = tempfile.NamedTemporaryFile(delete=True); path.write(b"ok"); path.close()'
expect_status 1 "deny system-file write" run_sandbox \
    'from pathlib import Path; Path("/etc/agent-sandbox-test").write_text("blocked")'
expect_status 1 "deny /var-file write" run_sandbox \
    'from pathlib import Path; Path("/var/agent-sandbox-test").write_text("blocked")'
expect_status 1 "deny home-file write" run_sandbox \
    'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("blocked")' "$OUTSIDE_FILE"

echo ""
echo "=== Sensitive Home Paths ==="
expect_status 1 "deny ~/.ssh listing" run_sandbox \
    'from pathlib import Path; path = Path.home() / ".ssh"; list(path.iterdir()) if path.exists() else (_ for _ in ()).throw(PermissionError())'
expect_status 1 "deny ~/.gnupg listing" run_sandbox \
    'from pathlib import Path; path = Path.home() / ".gnupg"; list(path.iterdir()) if path.exists() else (_ for _ in ()).throw(PermissionError())'
expect_status 1 "deny ~/.aws/credentials read" run_sandbox \
    'from pathlib import Path; path = Path.home() / ".aws/credentials"; path.read_text() if path.exists() else (_ for _ in ()).throw(PermissionError())'

echo ""
echo "=== Runtime Compatibility ==="
expect_status 0 "allow standard-device I/O" run_sandbox \
    'from pathlib import Path; Path("/dev/null").read_text()'
expect_status 0 "allow standard-device write" run_sandbox \
    'from pathlib import Path; Path("/dev/null").write_text("ok")'
expect_status 0 "allow standard-device reads" run_sandbox \
    'open("/dev/zero", "rb").read(1); open("/dev/urandom", "rb").read(1)'
expect_status 0 "allow standard output and error" run_sandbox \
    'import os; os.write(1, b""); os.write(2, b"")'
expect_status 0 "allow subprocess execution" run_sandbox \
    'import subprocess; import sys; subprocess.run(["ls", "-la", sys.argv[1]], capture_output=True, timeout=5, check=True); subprocess.run(["cat", "/etc/hosts"], capture_output=True, timeout=5, check=True)' \
    "$TEST_DIR"
expect_status 0 "allow multiprocessing primitives" run_sandbox \
    'from multiprocessing import Semaphore, shared_memory; semaphore = Semaphore(); shared = shared_memory.SharedMemory(create=True, size=1); shared.close(); shared.unlink()'
expect_status 0 "allow socket creation" run_sandbox \
    'import socket; sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM); sock.close()'
expect_status 0 "allow local DNS resolution" run_sandbox \
    'import socket; socket.getaddrinfo("localhost", None)'
expect_status 0 "allow HTTP requests" run_sandbox \
    'import urllib.request; urllib.request.urlopen("http://httpbin.org/get", timeout=5).read(1)'
expect_status 0 "allow environment reads and writes" run_sandbox \
    'import os; os.environ.get("HOME"); os.environ["AGENT_SANDBOX_TEST"] = "ok"; del os.environ["AGENT_SANDBOX_TEST"]'
if [[ "$AGENT" == "codex" ]]; then
    expect_status 0 "allow custom CODEX_HOME write" run_sandbox_with_codex_home \
        'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("ok")' \
        "$CODEX_HOME_DIR/config.toml"
fi

echo ""
echo "================================"
echo "Agent sandbox: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && echo "All tests passed!" || exit 1
