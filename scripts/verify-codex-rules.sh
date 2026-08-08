#!/usr/bin/env bash
# Verify that the generated Codex execution policy matches Claude Bash permissions.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

python3.14 scripts/generate-codex-rules.py --check

rule_count="$(rg -c '^prefix_rule' .codex/rules/default.rules)"
if [[ "$rule_count" != "339" ]]; then
    echo "Expected 339 Codex prefix rules, found $rule_count." >&2
    exit 1
fi

check_decision() {
    local expected="$1"
    shift
    local output actual
    output="$(codex execpolicy check --rules .codex/rules/default.rules -- "$@")"
    actual="$(jq -r '.decision' <<<"$output")"
    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected %s for %q, got %s.\n' "$expected" "$*" "$actual" >&2
        exit 1
    fi
}

check_decision allow ls
check_decision prompt npm publish
check_decision forbidden git push --force origin main
check_decision forbidden gh repo delete example/repository

echo "Codex execution-policy verification passed."
