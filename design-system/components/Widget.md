# Widget

The floating card that shows Claude Code's current state as three lamps and a Last Run row.

**Use it** as the single, always-on-top status surface. There is one per Mac, and it merges every Claude Code session into one state.

**Provide:** the resolved state (`red` | `yellow` | `green`), the active label, and the Last Run figures (seconds, output tokens).

**Anatomy:** the `Watermark` (behind everything, clipped to the card), three `Light`s in red/yellow/green order, and the `LastRun` row centred in the space below the lamps. Edge: `hairline` at `hairline-width`. Corners: `radius-card`, continuous.

**Behaviour:**
- Drag anywhere on the card to move it. Right-click to open the `ContextMenu`.
- It joins all Spaces, stays above full-screen apps, never takes focus, and has no Dock icon.
- Sleep: after 10 min idle on red, and not hovered, it fades to `opacity-sleep`.

**Do:** keep it at `widget-width` × `widget-height`. Keep all three lamps visible.
**Don't:** add buttons, text or a title bar. Don't use a light appearance.

Source: `Sources/main.swift` (`TrafficLightView.draw`).
