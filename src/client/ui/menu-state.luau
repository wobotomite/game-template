-- IS A MENU OPEN, and how dark should the world behind it go.
--
-- One shared answer, because several things need it and none of them can see
-- each other: the backdrop blurs, `hud-veil` hides the HUD, the touch buttons
-- stand down, and the gamepad navigator takes over A and B. A panel that
-- tracked its own open flag would leave each of those to find out some other
-- way.
--
-- REFCOUNTED, not a flag. Panels nest and overlap -- a confirmation opened from
-- a settings window, a shop opened over a pause menu -- and the closing one is
-- routinely not the last one. A single boolean gets cleared by whichever panel
-- shuts first, which un-blurs the world under a panel that is still open. So
-- each panel registers a HOLDER and the menu is open while any holder is.
--
-- The holder is the panel's own table (a component instance, a module), used as
-- an identity: it is never read, only compared, so two panels of the same kind
-- cannot collide the way two panels with the same string name would.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const ui_sounds = require(ReplicatedStorage.Client.audio["ui-sounds"])
const M = require(ReplicatedStorage.Shared.settings).ui.MENU_BACKDROP

const holders: { [{}]: number } = {}

-- The mode name, not a boolean, because it is also what `hud-veil` reports and
-- what the touch layer tests. Today the only two values are "none" and "menu".
const state = vide.source "none"
const effective_brightness = vide.source(M.BRIGHTNESS)

return table.freeze {
	-- Open or close this holder's claim on the menu state. `brightness` is how
	-- dark this panel wants the world behind it, defaulting to the shared
	-- value; passing it again on a later `set(holder, true)` re-states it, and
	-- passing nil keeps whatever the holder asked for last.
	set = function(holder: {}, open: boolean, brightness: number?)
		const was_open = next(holders) ~= nil
		if open then
			holders[holder] = brightness or holders[holder] or M.BRIGHTNESS
		else
			holders[holder] = nil
		end
		const is_open = next(holders) ~= nil

		-- MINIMUM across every open panel, and the default is the ceiling: the
		-- darkest request wins and nothing can ever brighten the backdrop. A
		-- panel that needs the world dimmed to be readable stays readable when
		-- a second panel opens on top of it.
		local target = M.BRIGHTNESS
		for _, value in holders do
			target = math.min(target, value)
		end
		effective_brightness(target)
		state(if is_open then "menu" else "none")

		-- Only on the EDGE -- the first panel opening and the last one closing.
		-- Per-panel would play the sound again for every nested confirmation,
		-- which is the audio version of the bug the refcount exists to fix.
		if is_open ~= was_open then
			if is_open then
				ui_sounds.open()
			else
				ui_sounds.close()
			end
		end
	end,
	state = function(): string
		return state()
	end,
	brightness = function(): number
		return effective_brightness()
	end,
}
