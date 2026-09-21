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

	-- Widgets. `button-hotkey` and `input-label` are deliberately NOT here:
	-- they are how a button grows a key cap, and a panel that wants one wants a
	-- button.
	window = require(script.window),
	dialog = require(script.dialog),
	button = require(script.button),
	hold_button = require(script["hold-button"]),
	hotbar = require(script.hotbar),
	icon = require(script.icon),
	lock_icon = require(script["lock-icon"]),
	text = require(script.text),

	-- Layers. `screen` puts widgets on the player's screen, `surface` puts the
	-- same widgets on a part in the world, and `console` is the walk-up prompt
	-- that opens one.
	screen = screen.screen,
	mount = screen.mount,
	surface = require(script.surface),
	console = require(script.console),

	-- Primitives, for a panel building something the kit has no widget for. A
	-- panel that uses these still looks like the rest of the game.
	slab = base.slab,
	rule = base.rule,
	hairline = base.hairline,
	stroke = base.stroke,
	eased = base.eased,
	blink = base.blink,
}
