-- A SCREENGUI THAT KNOWS ABOUT THE VEIL, and the helper that mounts one.
--
-- Every layer the game puts on screen goes through `screen` rather than
-- `vide.create "ScreenGui"`, because that is what makes "hide the HUD" -- for a
-- cutscene, a death, an open menu -- one call to `hud-veil` instead of a flag
-- threaded through every panel in the game.
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const wait_for_loaded = require(ReplicatedStorage.Client.boot["wait-for-loaded"])

const base = require(script.Parent["__base"])
const hud_veil = require(script.Parent.Parent["hud-veil"])

type Usable<T> = base.Usable<T>

export type ScreenProps = {
	Name: string,
	-- DisplayOrder. The kit does not rank layers for you; `settings.ui.ALERTS`
	-- and `settings.controls.TOUCH` carry the two the kit itself owns.
	layer: number?,
	Enabled: Usable<boolean>?,
	IgnoreGuiInset: boolean?,
	ScreenInsets: Enum.ScreenInsets?,
	ClipToDeviceSafeArea: boolean?,

	-- This screen stays up while the HUD is veiled: for the things that are
	-- not HUD -- the menu layer itself, the touch buttons, a loading cover.
	keep_veiled: boolean?,
	-- This screen IS part of a menu, so an open menu does not veil it. Without
	-- this a panel would hide itself the moment it registered as open.
	menu: boolean?,
	[number]: any,
}

function screen(props: ScreenProps): ScreenGui
	const gui = vide.create "ScreenGui" {
		Name = props.Name,
		-- The HUD survives respawning. The default destroys and rebuilds every
		-- ScreenGui on death, which throws away the state of anything the
		-- player had open and is almost never what a game wants.
		ResetOnSpawn = false,
		DisplayOrder = props.layer,
		Enabled = if props.keep_veiled
			then props.Enabled
			else function(): boolean
				-- An explicit false still wins; otherwise the veil decides.
				return base.peek(props.Enabled) ~= false and not hud_veil.veiled(props.menu)
			end,
		IgnoreGuiInset = props.IgnoreGuiInset,
		ScreenInsets = props.ScreenInsets,
		ClipToDeviceSafeArea = props.ClipToDeviceSafeArea,
		-- Sibling, so a widget's ZIndex is compared against its siblings rather
		-- than globally. Global ZIndex means any child of any panel can draw
		-- over an unrelated panel, which makes layering unpredictable the
		-- moment two features are on screen at once.
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}
	-- Children only: the named props above are not instances, and applying the
	-- whole table would try to write `layer`, `menu` and `keep_veiled` as
	-- ScreenGui properties.
	vide.apply(gui)(table.move(props, 1, #props, 1, {} :: { any }))
	return gui
end

-- Mount a standalone screen, for a layer that is not a child of `app` -- the
-- touch buttons, anything a feature owns end to end.
--
-- SPAWNED AND WAITING, in that order. `wait_for_loaded` yields, and a caller
-- is usually a module being required at boot: yielding there would stall every
-- module behind it. The wait itself is why nothing renders from nil state -- see
-- the comment in `src/client/init.client.luau`.
function mount(build: (Player) -> Instance)
	task.spawn(function()
		wait_for_loaded()
		const player = Players.LocalPlayer
		vide.mount(function()
			return build(player)
		end, player:WaitForChild "PlayerGui")
	end)
end

return table.freeze {
	screen = screen,
	mount = mount,
}
