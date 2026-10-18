# ContextMenu

The single menu, opened from a right-click on the widget or from the menu-bar dot: status information first, then controls.

**Order:**
1. Information rows (disabled): `Code Traffic Light`, `Status: <label>` (plus ` (sleeping)` when dimmed), `Last Run: <summary>`, `Context: 365k / 1M (36%)`.
2. Separator.
3. `Show Widget` / `Hide Widget`, `Reset Position`, `Launch at Login` (checkmark), `Done Sound ›`.
4. Separator.
5. `Quit` (⌘Q).

**Done Sound submenu:** `Off`, `System Alert`, a separator, then every sound in /System/Library/Sounds (default `Glass`), with a checkmark on the current choice. Choosing one plays it as a preview.

Use the native NSMenu: do not restyle it. Set copy in `menu-item`.

Source: `Sources/main.swift` (`populate`, `makeSoundMenu`).
