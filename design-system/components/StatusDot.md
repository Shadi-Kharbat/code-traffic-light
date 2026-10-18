# StatusDot

The menu-bar status item: a filled circle in the current signal colour.

**Size:** an 18 × 18 canvas (`status-item`) with the dot inset 4px, so it draws at 10px. It is not a template image: it keeps `signal-*` in light and dark menu bars.

**Tooltip:** `Claude Code: <label>`, for example `Claude Code: Thinking…`.

**Click:** opens the `ContextMenu`. The dot stays visible when the widget is hidden, and the done sound still plays.

Source: `Sources/main.swift` (`updateStatusIcon`).
