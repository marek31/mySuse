// Shared look of the key cheat-sheet wallpapers (keys-niri.typ, keys-plasma.typ). Kanagawa palette, like Noctalia.
// One 16:10 image, 3840x2400 (page 1280x800 pt at 216 ppi): fills the 1920x1200 X1 panel exactly; on 16:9
// screens (Dell 4K) crop mode cuts ~40 pt off top and bottom, so the margins keep text clear of that and of the left bar.
// Each sheet picks its text size and column count so it fills the page: raise `size` until the last column is full,
// lower it if `typst compile` makes a second page.
#let bg = rgb("#1f1f28")
#let fg = rgb("#dcd7ba")
#let dim = rgb("#727169")
#let line-c = rgb("#2a2a37")
#let blue = rgb("#7e9cd8")
#let green = rgb("#98bb6c")
#let yellow = rgb("#e6c384")
#let pink = rgb("#d27e99")
#let violet = rgb("#957fb8")
#let aqua = rgb("#7aa89f")
#let orange = rgb("#ffa066")
#let mono = ("JetBrains Mono", "DejaVu Sans Mono")

#let sheet(title, subtitle, size: 12.9pt, cols: 4, body) = {
  set page(width: 1280pt, height: 800pt, fill: bg,
    margin: (left: 100pt, right: 48pt, top: 66pt, bottom: 60pt))
  set text(font: ("Inter", "Noto Sans", "DejaVu Sans"), size: size, fill: fg)
  set par(leading: 0.5em)
  grid(columns: (auto, 1fr), column-gutter: 14pt, align: bottom,
    text(size: 1.98em, weight: "bold", fill: blue, title),
    text(size: 0.9em, fill: dim, subtitle))
  v(4pt)
  line(length: 100%, stroke: 0.6pt + line-c)
  v(6pt)
  columns(cols, gutter: 26pt, body)
}

// section(color, "Title", ("keys", "what"), ...) - never split across columns
#let section(color, title, ..rows) = block(breakable: false, width: 100%, below: 1.35em, {
  text(size: 1.08em, weight: "bold", fill: color, upper(title))
  v(-0.2em)
  grid(columns: (auto, 1fr), column-gutter: 0.7em, row-gutter: 0.48em,
    ..rows.pos().map(((k, d)) => (text(font: mono, size: 0.92em, fill: color, k), d)).flatten())
})

// cmd(color, "Title", ("command", "what"), ...) - command above its description, for long command lines
#let cmd(color, title, ..rows) = block(breakable: false, width: 100%, below: 1.35em, {
  text(size: 1.08em, weight: "bold", fill: color, upper(title))
  v(-0.2em)
  for (c, d) in rows.pos() {
    block(below: 0.52em, {
      text(font: mono, size: 0.875em, fill: color, c)
      if d != "" { linebreak(); text(size: 0.9em, fill: dim, d) }
    })
  }
})
