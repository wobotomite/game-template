-- KEEPING HUD OUT FROM UNDER THE TOUCH CONTROLS.
--
-- On a phone the bottom of the screen belongs to Roblox: the movement
-- thumbstick and the jump button are drawn into CoreGui, they move with the
-- device's size, orientation and safe area, and the game is not told when they
-- do. Anything the game anchors to the bottom edge -- a hotbar, a prompt, a
-- meter -- ends up under a thumb.
--
-- There is no API for where they are, and no signal when they move, so the only
-- way to follow them is to measure them and keep looking. That is what this
-- module is: a poll, and a registry for features that want to stack above each
-- other.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const Players = game:GetService "Players"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)
const render_step = require(ReplicatedStorage.Util.events["render-step"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)
const M = require(ReplicatedStorage.Shared.settings).controls.TOUCH

-- The second, unrelated job: how much room the game's OWN bottom-anchored HUD
-- is taking, so a feature can sit above whatever else is down there. Keyed by
-- holder and taking the MAXIMUM, for the same reason `menu-state` refcounts --
-- several features claim the bottom edge and the one that stops claiming it
-- first must not shrink the clearance for the others.
const holders: { [{}]: number } = {}
const bottom = vide.source(0)

function recompute()
	local target = 0
	for _, value in holders do
		target = math.max(target, value)
	end
	bottom(target)
end

-- A control that is not laid out yet measures zero, and treating that as a
-- real position would snap the HUD to the top-left corner for a frame.
function layout_control(control: Instance?): GuiObject?
	if not control or not control:IsA "GuiObject" or control.AbsoluteSize.X <= 0 or control.AbsoluteSize.Y <= 0 then
		return nil
	end
	return control
end

return table.freeze {
	-- A position, bottom-anchored, lifted clear of the touch controls. `x` and
	-- `y` are design pixels from the bottom-left (y negative, going up);
	-- `screen_name` is the ScreenGui this will live in, needed because the
	-- clearance is measured in that screen's own coordinates -- two screens
	-- with different insets do not share an answer.
	above_touch_controls = function(x: number, y: number, screen_name: string): () -> UDim2
		const clearance = vide.source(0)
		const poll = render_step(M.POLL)
		vide.cleanup(poll:connect(function()
			-- Not a touch device: no controls, no clearance. Checked every poll
			-- rather than once, because a player can pick up a phone or put
			-- down a controller mid-session.
			if not UserInputService.TouchEnabled then
				clearance(0)
				return
			end
			const gui = Players.LocalPlayer:FindFirstChildOfClass "PlayerGui"
			const screen = gui and gui:FindFirstChild(screen_name)
			const touch_gui = gui and gui:FindFirstChild "TouchGui"
			if not screen or not screen:IsA "ScreenGui" or not touch_gui then
				clearance(0)
				return
			end

			-- TWO THUMBSTICK KINDS, and which one is live is a player setting.
			-- The classic one is a fixed frame; the dynamic one appears where
			-- the thumb lands. Both exist in the tree, so the visible one wins
			-- -- and the fixed one is only believed when it is actually shown,
			-- unless the dynamic one is missing entirely.
			const fixed = layout_control(touch_gui:FindFirstChild("ThumbstickFrame", true))
			const dynamic = layout_control(touch_gui:FindFirstChild("DynamicThumbstickFrame", true))
			const control = if fixed and (fixed.Visible or not dynamic) then fixed else dynamic
			if not control then
				clearance(0)
				return
			end

			-- The OVERLAP between the control and this screen, not the
			-- control's height: a screen that already ends above the controls
			-- (one respecting the device's safe area, say) needs no clearance,
			-- and subtracting the full height would push its contents into the
			-- middle of the display.
			const screen_top = screen.AbsolutePosition.Y
			const screen_bottom = screen_top + screen.AbsoluteSize.Y
			const control_top = math.max(screen_top, control.AbsolutePosition.Y)
			const control_bottom = math.min(screen_bottom, control.AbsolutePosition.Y + control.AbsoluteSize.Y)
			clearance(math.max(0, control_bottom - control_top) + M.GAP)
		end))
		vide.cleanup(function()
			poll:destroy()
		end)
		-- Clearance is already in real pixels (it was measured); only the
		-- caller's design-pixel offsets are scaled.
		return function(): UDim2
			return UDim2.new(0, px(x)(), 1, px(y)() - clearance())
		end
	end,
	bottom = function(): number
		return bottom()
	end,
	set_bottom = function(holder: {}, value: number)
		-- Zero releases the claim rather than recording a zero, so an empty
		-- holder does not keep the table (and the max) alive.
		if value > 0 then
			holders[holder] = value
		else
			holders[holder] = nil
		end
		recompute()
	end,
}
