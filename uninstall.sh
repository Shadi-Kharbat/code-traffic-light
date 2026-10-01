#!/bin/bash
# Removes Claude Traffic Light: hooks from ~/.claude/settings.json, the app, and its state files.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
TARGET_DIR="$HOME/.claude/traffic-light"
APP_DST="$HOME/Applications/Claude Traffic Light.app"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.pre-traffic-light-uninstall.bak"
  TMP="$(mktemp)"
  jq '
    def clean:
      map(select(((.hooks // []) | map(.command // "") | join(" ") | contains("claude-status-hook")) | not));
    if .hooks then
      .hooks |= with_entries(.value |= clean)
      | .hooks |= with_entries(select(.value | length > 0))
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$TMP"
  jq -e . "$TMP" >/dev/null && mv -f "$TMP" "$SETTINGS"
  echo "Hooks removed from $SETTINGS (backup: $SETTINGS.pre-traffic-light-uninstall.bak)"
fi

pkill -x ClaudeTrafficLight 2>/dev/null || true
rm -rf "$APP_DST" "$TARGET_DIR"
echo "Removed $APP_DST and $TARGET_DIR"
