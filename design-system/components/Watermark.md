# Watermark

The eight-point sparkle drawn very faintly behind the lamps, tinted with the active light's colour. It is the closest thing the product has to a mark.

**Geometry:** centred on the card, radius 46% of the card height. Long points at 0°, 90°, 180° and 270°, short points at 46% length between them. Each side is a cubic curve whose control points both sit at 17% of the radius, on the bisecting angle, so the sides are concave. It is drawn as one path, so the alpha stays even.

**Opacity:** `opacity-watermark` (0.10) at rest; `opacity-watermark-working` (0.18) on yellow.

**Motion (yellow only):** radius breathes ±5%, the star spins 0.10 rad per pulse radian, and each point flexes ±8%.

**Don't:** raise its opacity above 0.18 in the widget, outline it, or place it in front of the lamps. At full strength it is for docs only, never in the widget.

Source: `Sources/main.swift` (`drawLogo`).
