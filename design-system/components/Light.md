# Light

One lamp of the traffic light: lit when its state is active, otherwise a dim outline with its default label.

**Provide:** which light (`red`, `yellow`, `green`), whether it is lit, and the label. The lit lamp shows the session's label (for example `Approve?`); unlit lamps show their defaults: `Ready`, `Thinking…`, `Done`.

**Lit:** fill with `signal-*` plus `glow-*` (18px blur) and a `highlight` radial in the upper part. Label in `lamp-label-lit`, coloured `on-red` on red and `on-signal` on yellow and green. Yellow pulses at 0.8 Hz between `opacity-pulse-min` and full intensity. Red and green never animate.

**Unlit:** fill with `*-unlit-fill` and a `lamp-ring-width` ring in `*-unlit-ring`, label in `lamp-label-unlit` and `*-unlit-label`.

**Label fit:** centre the label and keep `space-label-inset` on each side. If it does not fit, shrink it by 0.5px at a time, down to 9px.

**Accessibility:** the word and the lamp's position carry the state as well as the colour. The source's white-on-red (3.4:1) and unlit red label (2.7:1) sit below 4.5:1 and are kept exact.

Source: `Sources/main.swift` (`drawLight`, `drawCentered`).
