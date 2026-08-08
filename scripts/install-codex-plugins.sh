#!/usr/bin/env bash
# Install the Codex plugins corresponding to tracked Claude plugin settings.

set -euo pipefail

MARKETPLACE="claude-plugins-official"
MARKETPLACE_SOURCE="https://github.com/anthropics/claude-plugins-official.git"
PLUGIN="clangd-lsp@claude-plugins-official"

marketplaces="$(codex plugin marketplace list --json)"
if ! jq -e --arg name "$MARKETPLACE" \
    '.marketplaces[] | select(.name == $name)' >/dev/null <<<"$marketplaces"; then
    codex plugin marketplace add "$MARKETPLACE_SOURCE"
fi

plugins="$(codex plugin list --json)"
if jq -e --arg plugin "$PLUGIN" \
    '.installed[] | select(.pluginId == $plugin and .enabled)' >/dev/null <<<"$plugins"; then
    echo "Codex plugin setup is current: $PLUGIN"
    exit 0
fi

if jq -e --arg plugin "$PLUGIN" \
    '.installed[] | select(.pluginId == $plugin)' >/dev/null <<<"$plugins"; then
    codex plugin remove "$PLUGIN"
fi

codex plugin add "$PLUGIN"

echo "Codex plugin setup is current: $PLUGIN"
