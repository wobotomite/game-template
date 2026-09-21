-- THE WORLD BEHIND AN OPEN MENU: blurred and darkened, eased in and out.
--
-- Mounted once by `src/client/ui/app` and then left alone -- it watches
-- `menu-state` and needs no telling. A panel opens by registering a holder
-- there, and this follows.
--
-- WHY IT IS A POST-PROCESSING EFFECT rather than a dark frame behind the
-- panel. A frame can only cover what is inside its own ScreenGui, so every
-- other layer -- the HUD, a second panel, the touch buttons -- would sit on top
-- of the dimming, un-dimmed. Blur and colour correction apply to the rendered
-- world, under all of it, which is also what makes the panel read as being in
-- front of the game rather than pasted onto it.
--
-- A "full screen" panel in this kit is a CENTRED WINDOW FITTED TO ITS CONTENT
-- sitting over this backdrop -- not a frame stretched to the viewport. The
-- backdrop is what makes the difference legible: the world is still there,
-- recognisably, just pushed back.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const kit = require(script.Parent.kit)
const menu_state = require(script.Parent["menu-state"])
const M = require(ReplicatedStorage.Shared.settings).ui.MENU_BACKDROP

return function()
	-- Effects parent to the CAMERA, not to Lighting, so they apply to this
	-- player's view only. The camera is replaced on respawn and by any code
	-- that builds its own, so the parent follows it rather than being read
	-- once.
	const camera = vide.source(workspace.CurrentCamera)
	vide.cleanup(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		camera(workspace.CurrentCamera)
	end))

	const amount = kit.eased(function(): number
		return if menu_state.state() ~= "none" then 1 else 0
	end, M.FADE_RATE)
	const brightness = kit.eased(function(): number
		return if menu_state.state() ~= "none" then menu_state.brightness() else 0
	end, M.FADE_RATE)

	-- DISABLED AT REST, both of them. A BlurEffect of size 0 and a
	-- ColorCorrectionEffect of brightness 0 still cost a full-screen pass every
	-- frame for a result identical to not being there. `eased` snaps to its
	-- target rather than approaching it forever, which is what lets these
	-- reach exactly 0 and switch off.
	const blur = vide.create "BlurEffect" {
		Name = "MenuBlur",
		Parent = camera,
		Size = function(): number
			return M.BLUR * amount()
		end,
		Enabled = function(): boolean
			return amount() > 0
		end,
	}
	const darken = vide.create "ColorCorrectionEffect" {
		Name = "MenuDarken",
		Parent = camera,
		Brightness = brightness,
		Enabled = function(): boolean
			return brightness() ~= 0
		end,
	}

	-- Explicit, because these are parented to the camera and not to the vide
	-- tree: nothing else would ever collect them.
	vide.cleanup(function()
		blur:Destroy()
		darken:Destroy()
	end)
end
