# Code Traffic Light design system

Design rules and tokens for the widget, extracted from `Sources/main.swift`. Token values live in [`tokens.json`](tokens.json); component guidelines are in [`components/`](components).

Code Traffic Light is a floating macOS widget that shows what Claude Code is doing, as three lamps in a row. It should feel like a built-in macOS desktop widget: a translucent dark card, system type, nothing ornamental. One lamp is lit at a time, and that lamp's colour is the entire message.

## The three states

The state model is the core of the system. Every surface (card, menu-bar dot, watermark, menu text) shows the same single state.

| Light | Token | Label | Meaning |
|---|---|---|---|
| Red | `signal-red` | `Ready`, or `Approve?` | Claude is waiting for you. |
| Yellow | `signal-yellow` | `Thinking…` | Claude is thinking, running tools or processing. The only state that animates. |
| Green | `signal-green` | `Done` | The run finished. Hold for 10 s with the done sound, then return to red. |

- Order is always red, yellow, green, left to right. Never reorder or hide a lamp. Unlit lamps stay visible as dim outlines, so the row reads as a traffic light at a glance.
- Merging sessions: working beats done, and done (within 10 s) beats ready. Show one state, never a mix.
- Red is the resting state, not an error. Do not use `signal-red` for failures, and do not introduce a fourth colour.

## Content

- Labels are one or two words in title case: `Ready`, `Thinking…`, `Done`, `Approve?`. Use the real ellipsis character `…`, not three dots.
- The footer reads `Last Run` on the left and a summary on the right in the form `4m 44s · 4.6k tokens`, joined by a middle dot with spaces. When it does not fit, drop the duration and show `4.6k tokens`. With no data, show `—`.
- Durations: `42s`, `4m 44s`, `1h 12m`. Token counts: `812`, `4.6k` (one decimal under 10k), `365k`, `1.25M`. Context: `365k / 1M (36%)`.
- Menu items are plain verbs or nouns in title case: `Show Widget`, `Hide Widget`, `Reset Position`, `Launch at Login`, `Done Sound`, `Quit`. Information rows read `Status: …`, `Last Run: …`, `Context: …`. Add ` (sleeping)` to the status when the widget is dimmed.
- No emoji in the UI. The README uses 🔴🟡🟢 only in docs tables.

## Colour

- The widget is dark only: the panel forces the dark appearance. There is no light theme.
- Fill a lit lamp with its signal token at full strength, plus its `glow-*` shadow and a white `highlight` fading downward from the upper part of the lamp.
- Draw an unlit lamp as `*-unlit-fill` with a 1.5px `*-unlit-ring` and its label in `*-unlit-label`.
- Label colour on a lit lamp: `on-red` on red, `on-signal` on yellow and green.
- Card text: `text-secondary` for the `Last Run` caption and `text-primary` for its value.
- The live card is the `.hudWindow` blur material. Wherever blur is not available (renders, docs), paint `card-backdrop` instead, over `wallpaper-top` → `wallpaper-bottom` at -70°.
- Contrast notes from the source, kept exact: white on `signal-red` is 3.4:1. The unlit red caption is 2.7:1 and the unlit green caption 3.8:1. They pass as recognisable states because position and the lit lamp carry the meaning, but do not reuse these pairs for running text.
- Colour is never the only signal. Every lamp carries its word, and position (left, middle, right) also encodes the state.

## Type

- Set everything in the system family (`system`, SF Pro on macOS). No other faces.
- Lit lamp caption: `lamp-label-lit`, 15px bold. Unlit lamp caption: `lamp-label-unlit`, 14px semibold. Captions are centred in the lamp and shrink in 0.5px steps, down to 9px, until they fit with `space-label-inset` on each side.
- Footer: `footer`, 12px medium, for both caption and value. Menu: `menu-item`.

## Layout and size

- Card: `widget-width` × `widget-height` (340 × 158), `radius-card` (22px) with a continuous corner, a 1px `hairline` edge and the system window shadow.
- Lamps: three at `lamp-diameter` (86px). They sit `space-card-x` (22px) in from each side and `space-card-top` (20px) from the top, with `space-lamp-gap` (19px) between them.
- Footer: one row, vertically centred in the space below the lamps. The caption is left-aligned and the value right-aligned, both at `space-card-x`.
- Default position: the top-right of the visible screen area, `space-screen-x` from the right and `space-screen-y` from the top. People can drag the card anywhere, and their position is remembered.

## Motion

Motion means "working". Only yellow animates; red and green are still.

- Tick: 20 Hz (every 0.05 s).
- Yellow pulse: 0.8 Hz sine. Intensity runs from `opacity-pulse-min` (0.72) to 1.0, lamp alpha is 0.40 + 0.60 × intensity, and the glow alpha is 0.85 × intensity.
- Watermark while working: it breathes (radius ± 5% at 0.7× the pulse rate), slowly spins, and each point flexes by ± 8%. Its opacity rises from `opacity-watermark` to `opacity-watermark-working`.
- Sleep: after 10 minutes with no activity, while red and not hovered, the whole widget fades to `opacity-sleep` over 0.8 s. Hover or any event fades it back.
- Done: green holds for 10 s, then switches back to red with no transition.

## Sound

The done sound plays once when the light turns green (default `Glass`, any system sound, `System Alert`, or `Off`). It is rate-limited to once every 1.5 s, and it never plays on the first tick after launch.

## Iconography

- There is no logo file. The mark is the eight-point sparkle the widget draws as its watermark. It has four long points and four short points at 46%, with concave sides pulled to 17% of the radius. See `Watermark`. It is a generic sparkle, tinted with the active light's colour and always very faint.
- The menu-bar icon is a plain filled circle in the current signal colour (`StatusDot`). It is not a template image, so it keeps its colour in light and dark menu bars.
- No other icons are used.

## Source notes

- The app is Swift/AppKit with no CSS or token file. Every value here was read from `Sources/main.swift`: the NSColor sRGB components are converted to hex, with alpha folded into 8-digit hex.
- The app uses the macOS system font, so there are no font files.
- Menu-item size (13px) is the macOS default menu font, not a value set in code.
- If you change a value in `Sources/main.swift`, update `tokens.json` to match.
