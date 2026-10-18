# LastRun

The footer row that summarises the last finished run: how long it took and how many output tokens it produced.

**Provide:** the run's seconds and output tokens, or nothing.

**Format:** caption `Last Run` on the left in `text-secondary`; the value on the right in `text-primary`; both in `footer`. Try, longest first, until one fits with `space-footer-gap`:
1. `4m 44s · 4.6k tokens`
2. `4.6k tokens`

With no run yet, show `—`. Durations: `42s`, `4m 44s`, `1h 12m`. Tokens: `812`, `4.6k`, `365k`, `1.25M`.

**Don't:** show context-window usage here; it belongs in the `ContextMenu`. Don't add icons or units other than `tokens`.

Source: `Sources/main.swift` (`drawFooter`, `Format`).
