-- THE ROOT OF THE CLIENT'S UI: mounted once by `src/client/init.client.luau`,
-- and the only place that runs before any panel exists.
--
-- Three jobs, in order, and the order matters:
--   1. fix the scale floor, before any widget measures anything
--   2. start the menu backdrop, which then watches `menu-state` on its own
--   3. return the alert layer, so there is always somewhere to put a message
--
-- A FEATURE'S OWN SCREEN DOES NOT GO HERE. Anything a feature owns end to end
-- mounts itself with `kit.mount`, which waits for the player to be loaded and
-- puts a screen straight into PlayerGui. This module is the handful of things
-- that belong to no feature and must exist before the first one does.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const alerts = require(script.Parent.pages.alerts)
const kit = require(script.Parent.kit)
const menu_backdrop = require(script.Parent["menu-backdrop"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)
const ui = require(ReplicatedStorage.Shared.settings).ui

function app(): ScreenGui
	-- BEFORE `usePx`, not after: the floor is read when the scale is computed,
	-- and a widget built against the hook's own default would be laid out once
	-- at the wrong size and never told.
	px.setMinimumScale(ui.SCALE.MINIMUM)
	px.usePx()

	-- Returns nothing to parent: the blur and the colour correction live on the
	-- camera, not in this tree. Called for its effect, and cleaned up with the
	-- root that called it.
	menu_backdrop()

	return kit.screen {
		Name = "Alerts",
		layer = ui.ALERTS.LAYER,
		-- MENU, so an open panel does not veil the toasts. A message that the
		-- game could not do what the player just asked for arrives WHILE the
		-- panel they asked from is still open; veiling it there would hide the
		-- alert exactly when it was worth reading.
		menu = true,
		-- The topbar is Roblox's; a toast column anchored to the bottom does not
		-- collide with it, and honouring the inset would only shorten the screen
		-- the column measures itself against.
		IgnoreGuiInset = true,

		alerts(),
	}
end

return app
