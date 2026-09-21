-- SHOULD THE HUD BE HIDDEN RIGHT NOW.
--
-- Every screen the kit builds asks this before it draws (see `kit/screen`), so
-- hiding the HUD for a cutscene, a death, a camera shot or a loading cover is
-- one call here rather than a flag threaded into every panel in the game.
--
-- REFCOUNTED like `menu-state`, and for the same reason: two things can want
-- the HUD gone at once (a cutscene that starts while a transition is fading)
-- and the one that finishes first must not reveal it under the other. Here the
-- holder is a STRING rather than a table, because the callers are features
-- ("cutscene", "death") of which there is one each, and a name is greppable
-- when a HUD is stuck hidden and you need to know who is holding it.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const menu_state = require(script.Parent["menu-state"]).state

const holders: { [string]: true } = {}

const state = vide.source(false)

function set(holder: string, on: boolean)
	if on then
		holders[holder] = true
	else
		holders[holder] = nil
	end
	state(next(holders) ~= nil)
end

-- An open menu veils the HUD too: the panel is what the player is reading, and
-- a health bar drawn over it is noise.
--
-- `ignore_menu` is for the screens that ARE the menu layer -- the panel itself,
-- the backdrop, anything a player is meant to keep seeing while a menu is up.
-- Without it a panel would hide itself the moment it opened.
function veiled(ignore_menu: boolean?): boolean
	return state() or (not ignore_menu and menu_state() ~= "none")
end

return table.freeze {
	set = set,
	veiled = veiled,
}
