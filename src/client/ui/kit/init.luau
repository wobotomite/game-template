-- THE WIDGET KIT: one require for everything a panel is built out of.
--
-- A game's UI code requires this module and nothing else in this folder. The
-- widgets themselves reach for `__base` directly, which is the private half --
-- the theme tables and the primitives -- and only the parts a panel legitimately
-- needs are re-exported here.
--
-- The whole look lives in `settings.ui` and `assets.fonts`: no widget in here
-- writes a colour, a size or a font of its own, so restyling a game is those
-- two tables. See the UI kit doc in `docs`.
const base = require(script["__base"])
const screen = require(script.screen)

export type Usable<T> = base.Usable<T>

return table.freeze {
	-- The theme, for the cases a panel genuinely needs a raw value -- tinting
	-- an icon, colouring a chart. Reach for a widget first.
	COLORS = base.COLORS,
	METRICS = base.METRICS,

	-- Widgets.
	icon = require(script.icon),
	text = require(script.text),

	-- Layers.
	screen = screen.screen,
	mount = screen.mount,

	-- Primitives, for a panel building something the kit has no widget for. A
	-- panel that uses these still looks like the rest of the game.
	slab = base.slab,
	rule = base.rule,
	hairline = base.hairline,
	stroke = base.stroke,
	eased = base.eased,
	blink = base.blink,
}
