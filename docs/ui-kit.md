# The UI kit

One require gets you every widget a panel is built out of:

```luau
local kit = require(ReplicatedStorage.Client.ui.kit)
```

`src/client/ui/kit/init.luau` is the whole public surface. The widgets
themselves reach into `src/client/ui/kit/__base.luau` — the theme tables and the
drawing primitives — and only the parts a panel legitimately needs are
re-exported. If you find yourself requiring a file inside `kit/` by name, that
is either a missing export or a widget that wants writing.

## Restyling a game is two tables

No widget in the kit writes a colour, a size, a font or an asset id of its own.
Everything comes from the `ui` section of `src/shared/settings.luau` and from
`src/shared/assets.luau`:

- **`settings.ui.COLORS`** — the palette. `ACCENT` is the one colour the game is
  *about*; `SURFACE`, `TEXT`, `TEXT_DIM` and the rest are the substrate.
- **`settings.ui.METRICS`** — the grid: text size, gap, padding, row heights.
- **`settings.ui.STYLE`** — the look proper: transparencies, stroke weights,
  corner radii, the hairline.
- **`assets.fonts`** and **`assets.icons`** — a heading face, a body face, and
  the handful of glyphs the kit itself draws.

Player-facing words go in `src/shared/strings.luau`, under `ui` and `controls`.

**Every uploaded asset may be unset, and the kit still renders.** A font id of
`""` falls back to a stock face; an icon id of `0` draws the slot and nothing
in it. This is not politeness — it is how a game built from this template looks
on the first day, before anything has been uploaded, and a kit that needs its
assets to draw at all cannot be evaluated until after the work of uploading them
is done.

## The widgets

| call | what it is |
|---|---|
| `kit.text` | the only text primitive. `body` picks the monospace face, `dim` the secondary colour |
| `kit.icon` | an image slot that degrades to empty when the id is unset |
| `kit.button` | the standard button. `accent = true` draws the one action a panel expects you to take |
| `kit.hold_button` | the same plus `hold`: seconds it must be held, filling as it goes |
| `kit.window` | a titled sheet with a body and a footer of buttons — see below |
| `kit.dialog` | a window shorthand: some centred lines and some buttons |
| `kit.hotbar` | a row of numbered slots, the selected one lifted |
| `kit.lock_icon` | the padlock, drawn rather than uploaded |

And the primitives, for building something the kit has no widget for while still
looking like the rest of the game: `slab`, `rule`, `hairline`, `stroke`,
`eased`, `blink`.

Two files are deliberately **not** exported: `src/client/ui/kit/button-hotkey.luau`
and `src/client/ui/kit/input-label.luau`. They are how a button grows a key cap,
and a panel that wants one of those wants a button.

## "Full screen" means a centred window

This is the single layout decision in the kit worth stating outright, because
the phrase misleads:

> **A full-screen panel is a centred window fitted to its content, sitting over
> the blurred backdrop. It is not a frame stretched to the viewport.**

A panel stretched edge to edge has to invent something to put in the corners, so
it ends up with a vast empty middle and text pinned to the rim — which reads as
a website, not as a game. A window sized to what it actually contains, floating
over a world that is still visibly there behind it, reads as *the game, paused*.
`src/client/ui/menu-backdrop.luau` is what makes the difference legible: it
blurs and darkens the rendered world rather than drawing a dark frame, so every
other layer is dimmed too and the window is unmistakably in front.

Give `kit.window` a `width` and, if it needs one, a `height`; let its body grow
and its footer take what it needs. The arithmetic for that lives in
`src/client/ui/kit/window-fit.luau` — three sums, lifted out of the vide tree
because arithmetic buried in a vide tree is arithmetic no spec can reach, and
pinned by `tests/window-fit.spec.luau`. The failure it guards is invisible: a
footer that reserves one gap too few clips its bottom row of buttons, only on
the window with the most buttons, only at the scale where it is tallest.

## Layers

`kit.screen` instead of `vide.create "ScreenGui"`, always. It is what makes
"hide the HUD" — for a cutscene, a death, an open menu — one call rather than a
flag threaded through every panel in the game.

- `menu = true` marks a screen as *part of* a menu, so an open menu does not
  veil it.
- `keep_veiled = true` marks a screen that is not HUD at all: the touch buttons,
  a loading cover.
- `layer` is the DisplayOrder. The kit does not rank layers for you.

`kit.mount` mounts a standalone screen for a feature that owns its UI end to
end: it spawns, waits for the player to be loaded, and parents into PlayerGui.
Nothing renders from nil state, which is why the wait is there.

`kit.surface` puts the same widgets on a part in the world, one build per tagged
part, as a SurfaceGui in PlayerGui rather than in the workspace. `kit.console`
is the walk-up prompt that opens one.

`src/client/ui/app.luau` is the root: it fixes the `px` scale floor, starts the
backdrop, and returns the alert layer. A feature's own screen does **not** go
there — it mounts itself.

## The menu spine

- `src/client/ui/menu-state.luau` — who has a menu open, and how bright the
  backdrop should be behind it. A panel opens by registering a holder.
- `src/client/ui/hud-veil.luau` — the one switch every screen consults.
- `src/client/ui/menu-backdrop.luau` — the blur and the darkening, on the
  camera.
- `src/client/ui/hud-inset.luau` — two unrelated jobs: how much of the bottom of
  the screen Roblox's own touch controls have taken, and how much the game's own
  bottom-anchored HUD has claimed. Anything anchored to the bottom edge asks.

`src/client/ui/pages/alerts.luau` is the toast stack. It is deliberately
anonymous: a toast says what happened, never who it happened to.

## Input

`src/client/input/input-state.luau` is the reactive answer to "what is the
player holding right now" — gamepad, touch, keyboard — and it is what
`src/client/ui/controller-ui.luau` uses to decide whether to draw a key cap, a
button glyph, or nothing. Register a button with `controller-ui` and it joins
the gamepad focus ring for free.

`src/client/input/touch-gestures.luau` turns raw touches into taps, drags and
pinches with thresholds from `settings.controls`;
`src/client/input/mobile.luau` is the on-screen button layer built on the kit;
`src/client/input/mouse-unlock.luau` frees the cursor while a menu is open and
answers `is_open()`; `src/client/input/menu-camera.client.luau` is the slow
drift behind an open menu.

Key binding itself is not the kit's: that is `src/util/input/init.luau`, whose
contexts sink, prioritise and unbind as a group.

## Hooks the kit assumes

`src/util/ui/hooks/px.luau` is the scale. Every size a widget draws is in
*design* pixels and goes through `px`; the floor is set once, at boot, by
`src/client/ui/app.luau`. `src/util/ui/hooks/use-atom.luau` is how a panel reads
charm state. State lives in charm, instances in vide — a rule implemented inside
a vide tree is a rule no spec can test.

Sound is a seam, not a feature: `src/client/audio/ui-sounds.luau` is a
placeholder whose four hooks (`hover`, `click`, `open`, `close`) do nothing.
Point them at real cues when the game has any.
