#!/bin/bash
# Code Traffic Light — Copyright (c) 2026 Shadi Kharbat. MIT License.
# Installs Code Traffic Light:
#   1. builds the app (if needed)
#   2. copies the hook script to ~/.claude/traffic-light/
#   3. merges the hooks into ~/.claude/settings.json (backup is kept)
#   4. copies the app to ~/Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)"; exit 1; }

TARGET_DIR="$HOME/.claude/traffic-light"
HOOK_PATH="$TARGET_DIR/traffic-light-hook.sh"
SETTINGS="$HOME/.claude/settings.json"
APP_SRC="build/Code Traffic Light.app"
APP_DST="$HOME/Applications/Code Traffic Light.app"
OLD_APP_DST="$HOME/Applications/Claude Traffic Light.app"   # name used before v1.1

# 1. build
if [ ! -x "$APP_SRC/Contents/MacOS/CodeTrafficLight" ] || [ "${REBUILD:-0}" = "1" ]; then
  bash "$(dirname "$0")/build.sh"
fi

# 2. hook script
mkdir -p "$TARGET_DIR/sessions"
cp traffic-light-hook.sh "$HOOK_PATH"
rm -f "$TARGET_DIR/claude-status-hook.sh" "$TARGET_DIR/source/claude-status-hook.sh"   # pre-v1.1 name
chmod +x "$HOOK_PATH"

# 3. settings.json
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$TARGET_DIR/settings.backup.$(date +%Y%m%d-%H%M%S).json"
cp "$SETTINGS" "$BACKUP"

TMP="$(mktemp)"
jq --arg cmd "\"$HOOK_PATH\"" '
  def clean:
    map(select(((.hooks // []) | map(.command // "") | join(" ") | test("claude-status-hook|traffic-light-hook")) | not));
  def entry($args; $matcher; $timeout):
    {"hooks": [{"type": "command", "command": ($cmd + " " + $args), "timeout": $timeout}]}
    + (if $matcher == null then {} else {"matcher": $matcher} end);
  .hooks //= {}
  | .hooks.SessionStart     = ((.hooks.SessionStart     // []) | clean) + [entry("SessionStart"; null; 5)]
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | clean) + [entry("UserPromptSubmit"; null; 5)]
  | .hooks.PreToolUse       = ((.hooks.PreToolUse       // []) | clean) + [entry("PreToolUse"; "*"; 5)]
  | .hooks.PostToolUse      = ((.hooks.PostToolUse      // []) | clean) + [entry("PostToolUse"; "*"; 5)]
  | .hooks.PreCompact       = ((.hooks.PreCompact       // []) | clean) + [entry("PreCompact"; null; 5)]
  | .hooks.Notification     = ((.hooks.Notification     // []) | clean)
                              + [entry("Notification permission_prompt"; "permission_prompt"; 5),
                                 entry("Notification idle_prompt"; "idle_prompt"; 5)]
  | .hooks.Stop             = ((.hooks.Stop             // []) | clean) + [entry("Stop"; null; 20)]
  | .hooks.SessionEnd       = ((.hooks.SessionEnd       // []) | clean) + [entry("SessionEnd"; null; 5)]
' "$SETTINGS" > "$TMP"
jq -e . "$TMP" >/dev/null
mv -f "$TMP" "$SETTINGS"

# 4. keep a copy of the source next to the hook, so it can be rebuilt later
#    (edit ~/.claude/traffic-light/source/Sources/main.swift, then REBUILD=1 ~/.claude/traffic-light/source/install.sh)
mkdir -p "$TARGET_DIR/source/Sources"
cp Sources/main.swift "$TARGET_DIR/source/Sources/"
cp Info.plist build.sh install.sh uninstall.sh traffic-light-hook.sh README.md LICENSE "$TARGET_DIR/source/"

# 5. app
mkdir -p "$HOME/Applications"
if pgrep -xq CodeTrafficLight; then
  osascript -e 'tell application id "local.code-traffic-light" to quit' >/dev/null 2>&1 || pkill -x CodeTrafficLight || true
  sleep 0.5
fi
# migrate from the pre-v1.1 name: quit it, remove it, keep its saved position and sound choice
if pgrep -xq ClaudeTrafficLight; then pkill -x ClaudeTrafficLight || true; sleep 0.5; fi
rm -rf "$OLD_APP_DST"
if defaults read local.claude-traffic-light >/dev/null 2>&1 && ! defaults read local.code-traffic-light >/dev/null 2>&1; then
  defaults export local.claude-traffic-light - 2>/dev/null | defaults import local.code-traffic-light - 2>/dev/null || true
fi
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
open "$APP_DST"

echo
echo "✅ Installed."
echo "   App:      $APP_DST"
echo "   Hook:     $HOOK_PATH"
echo "   Settings: $SETTINGS   (backup: $BACKUP)"
echo "   Source:   $TARGET_DIR/source"
echo
echo "New Claude Code sessions will drive the widget. Right-click the widget or use the menu-bar dot for options."
