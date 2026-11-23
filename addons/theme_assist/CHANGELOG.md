# Changelog (shipped with the addon)

## 2.5.0

The first stable release. Godot 4.4 or newer. Developed and tested on 4.7.2. Over 2.4.1; nothing breaks. This release fixes bugs only.

### Fixed

- Pixel and Framed: applying a pixel look with `TaLook.apply()` while a pixel look was already applied (again after a change, or Pixel then Framed) made the framebuffer the whole canvas, so the UI drew at a fraction of its size. Each apply now measures the display again
- `TaLook.load_saved()` handed back the same object every time and reloaded it from disk, so loading again undid the edits made to the look an earlier load returned. In the Playground, a token edit made after opening on a saved look went back to the saved value, and Save wrote the old look. A deleted save also still read as saved, with load errors, until the game restarted. Each load is now its own copy
- A `TaModal` opened with `open()` after one answer ignored its buttons and Esc while its focus trap held focus, so the player was stuck. Every open is now a new question. A `TaDialog` shown with `popup_centered()` after one answer had the same problem and is fixed the same way
- A `confirmed` or `canceled` handler that asks the next question on the same `TaModal` or `TaDialog` no longer has that question closed straight away
- The pause overlay (`scenes/pause.tscn`) freed while open, for example when Quit changes scene, left `SceneTree.paused` on, so the next scene started paused. It now gives the pause back
- `look.fallback_fonts` reached only the body, bold, and italic faces. Titles, captions, badges, tags, and counts still showed emoji as boxes on web exports. Every face the Theme sets now gets the chain, and the title's letter spacing and the count face's trimmed line are kept
- `TaKillFeed`: lines waiting past the limit never showed when every line on screen closed in the same frame
- Scrolling the mouse wheel over a toast dismissed it. Only a click does now
- `TaWorldAttach` switched from `SCREEN` to `BILLBOARD` while running kept its canvas position, so the billboard came out empty
- `TaVignette.hold()` faded away when called while a `flash()` was still fading
- `TaChip.set_stacked(false)` leaked its stack node
- `TaFocus.trap()` called twice on a control before it entered the tree logged an error
