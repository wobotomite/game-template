-- THE TOUCH LAYER: on-screen buttons, and the phone's answers to "which way is
-- the player pushing" and "are they holding something down".
--
-- Roblox gives a mobile player a movement stick and a jump button. Everything
-- else a game binds to a key has no equivalent, so the game has to draw it --
-- and then keep it out of the way of the two controls the engine drew, which
-- move with the device's size, orientation and safe area and announce nothing
-- when they do.
--
-- ANCHORED TO THE JUMP BUTTON, not to the screen corner. Jump is the one
-- control Roblox positions for us on every phone, notch and orientation, so a
-- grid counted back from it lands correctly everywhere -- where a corner offset
-- would be right on the device it was tuned on and wrong on the next one. The
-- cell each button sits in is `settings.controls.TOUCH.SLOTS`.
--
-- ONE SCREENGUI PER BUTTON, mounted where the button is declared. A button is
-- part of the feature that owns it, and a single shared touch panel would mean
-- every feature editing one file and every button's visibility rules living
-- somewhere other than the feature they belong to.
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"
const GuiService = game:GetService "GuiService"

const vide = require(ReplicatedStorage.Packages.vide)
const kit = require(ReplicatedStorage.Client.ui.kit)
const mouse_unlock = require(script.Parent["mouse-unlock"])
const hud_veil = require(ReplicatedStorage.Client.ui["hud-veil"])
const menu_state = require(ReplicatedStorage.Client.ui["menu-state"]).state
const render_step = require(ReplicatedStorage.Util.events["render-step"])
const settings = require(ReplicatedStorage.Shared.settings)
const strings = require(ReplicatedStorage.Shared.strings)
const assets = require(ReplicatedStorage.Shared.assets)
const gestures = require(script.Parent["touch-gestures"])
const M = settings.controls.TOUCH
const COLORS = settings.ui.COLORS

-- Optimistic at boot, like `input-state.focused`, and for the same reason: the
-- signal only fires on a change. Also set by any touch or click, because a
-- phone browser that never sent `WindowFocused` still sends the tap.
local focused = true

UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		focused = true
	end
end)
UserInputService.WindowFocused:Connect(function()
	focused = true
end)
UserInputService.WindowFocusReleased:Connect(function()
	focused = false
end)

-- Once per distinct problem, not once per poll. These are read inside a mounted
-- screen that ticks every frame, so an unset id would otherwise fill the output
-- for the life of the session.
const warned: { [string]: boolean } = {}
function warn_once(message: string)
	if warned[message] then
		return
	end
	warned[message] = true
	warn(message)
end

-- Should the touch layer be doing anything at all. `dead` inverts the character
-- test, for the buttons that exist precisely because the player is down -- a
-- respawn, a call for help -- and which must survive a UI that is otherwise
-- hiding the HUD.
function available(dead: boolean?): boolean
	if
		not UserInputService.TouchEnabled
		or GuiService.MenuIsOpen
		or menu_state() ~= "none"
		-- A cursor on screen means the player is working a UI with it. Not
		-- applied to the dead-state buttons, which are usually shown next to
		-- exactly such a UI.
		or (not dead and mouse_unlock.is_open())
	then
		return false
	end
	const player = Players.LocalPlayer
	const character = player and player.Character
	const humanoid = if character then character:FindFirstChildOfClass "Humanoid" else nil
	if dead then
		return humanoid == nil or humanoid.Health <= 0
	end
	return humanoid ~= nil and humanoid.Health > 0 and not hud_veil.veiled()
end

-- Declare a touch button. `id` names its caption in `strings.controls.TOUCH`
-- and its grid cell in `settings.controls.TOUCH.SLOTS`; `visible` is the
-- feature's own extra condition, on top of the layer-wide rules above.
function button(id: string, pressed: () -> (), released: (() -> ())?, visible: (() -> boolean)?, dead: boolean?)
	kit.mount(function(): ScreenGui
		const shown = vide.source(false)
		const held = vide.source(false)
		const position = vide.source(UDim2.new())
		-- A full-screen frame purely to measure from: the jump button's
		-- position is absolute, and the offset written below has to be relative
		-- to this screen's own origin.
		const space = vide.create "Frame" {
			Name = "TouchSpace",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}
		-- Cell (0, 0) is the jump button's own square. A button with no cell
		-- therefore lands ON jump, which is deliberate: a missing setting
		-- should be impossible to miss rather than quietly off-screen.
		local slot = M.SLOTS[id]
		if not slot then
			warn_once(`touch button "{id}" has no cell in settings, so it is drawn over the jump button`)
			slot = Vector2.zero
		end
		-- An id with no caption draws the id, for the same reason.
		const caption = strings.controls.TOUCH[id]
		if not caption then
			warn_once(`touch button "{id}" has no caption in strings, so it is labelled with its id`)
		end

		local jump: GuiObject? = nil
		local touch: InputObject? = nil
		local function release()
			touch = nil
			if held() then
				held(false)
				if released then
					released()
				end
			end
		end
		local function allowed(): boolean
			return available(dead) and (visible == nil or visible())
		end

		const poll = render_step(M.POLL)
		vide.cleanup(poll:connect(function()
			-- Re-found whenever it is missing or has been reparented: the touch
			-- controls are rebuilt when the player switches control schemes or
			-- the device rotates, and the old instance goes with them.
			if not jump or not jump:IsDescendantOf(Players.LocalPlayer.PlayerGui) then
				const touch_gui = Players.LocalPlayer.PlayerGui:FindFirstChild "TouchGui"
				const found = touch_gui and touch_gui:FindFirstChild("JumpButton", true)
				jump = if found and found:IsA "GuiObject" then found else nil
			end
			const anchor = jump
			-- Zero size means it exists but has not been laid out. Believing it
			-- would put the button in the top-left corner for a frame.
			const located = anchor ~= nil and anchor.AbsoluteSize.X > 0 and anchor.AbsoluteSize.Y > 0
			if anchor and located then
				const corner = anchor.AbsolutePosition - space.AbsolutePosition
				position(
					UDim2.fromOffset(
						corner.X - M.GAP - slot.X * (M.BUTTON + M.GAP),
						corner.Y + anchor.AbsoluteSize.Y - slot.Y * (M.BUTTON + M.GAP)
					)
				)
			end
			-- HIDDEN UNTIL LOCATED. A touch button floating at the corner
			-- because jump has not been found yet is worse than no button: the
			-- player presses it, and it is not where it will be next frame.
			const show = located and allowed()
			shown(show)
			if not show then
				release()
			end
		end))
		vide.cleanup(function()
			release()
			poll:destroy()
		end)
		-- The three ways a press ends without the button seeing it. Each leaves
		-- the action held down forever.
		vide.cleanup(UserInputService.InputEnded:Connect(function(input: InputObject)
			if input == touch then
				release()
			end
		end))
		vide.cleanup(UserInputService.WindowFocusReleased:Connect(release))
		vide.cleanup(GuiService.MenuOpened:Connect(release))

		return kit.screen {
			Name = `Touch_{id}`,
			layer = M.LAYER,
			-- Not HUD: these are the controls, and a veil that hid them would
			-- leave a mobile player unable to act.
			keep_veiled = true,

			vide.apply(space) {
				vide.create "TextButton" {
					Name = id,
					Size = UDim2.fromOffset(M.BUTTON, M.BUTTON),
					Position = position,
					-- Bottom-right, because the grid is counted back from the
					-- jump button's bottom-right corner.
					AnchorPoint = Vector2.one,
					Visible = shown,
					Text = caption or id,
					TextSize = M.TEXT,
					FontFace = assets.fonts.BODY,
					TextColor3 = COLORS.TEXT,
					-- Held state drawn by the kit's own colours rather than by
					-- AutoButtonColor, which tints and does not survive a theme
					-- where the button is already dark.
					BackgroundColor3 = function(): Color3
						return if held() then COLORS.OUTLINE else COLORS.BUTTON_BG
					end,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					-- InputBegan rather than Activated: a held button has to
					-- know the instant it goes down, and Activated only fires
					-- on a completed click.
					InputBegan = function(input: InputObject)
						if
							(
								input.UserInputType == Enum.UserInputType.Touch
								or input.UserInputType == Enum.UserInputType.MouseButton1
							)
							-- One finger owns the button. A second landing on
							-- it must not fire a second press that the first
							-- release then cancels.
							and touch == nil
							and allowed()
						then
							focused = true
							touch = input
							held(true)
							pressed()
						end
					end,

					kit.stroke(),
				},
			},
		}
	end)
end

-- THE MOVEMENT STICK, resolved into the game's own axes. `Humanoid.MoveDirection`
-- is a world vector, and what a game wants is "forward" and "sideways" relative
-- to the camera -- which is what the player's thumb actually meant.
function movement(humanoid: Humanoid, camera: Camera): (number, number, number)
	if not focused or not available() then
		return 0, 0, 0
	end
	const direction = humanoid.MoveDirection
	const view_right = camera.CFrame.RightVector
	-- FLATTENED. Looking straight up or down leaves almost no horizontal
	-- component, and normalising what is left turns a tiny numerical remainder
	-- into a confident and arbitrary direction.
	const flat_right = Vector3.new(view_right.X, 0, view_right.Z)
	if flat_right.Magnitude <= M.DEADZONE then
		return 0, 0, 0
	end
	const right = flat_right.Unit
	const forward = Vector3.yAxis:Cross(right)
	const ahead = direction:Dot(forward)
	const sideways = direction:Dot(right)
	-- Each axis dead-zoned on its own, so a thumb pushed straight forward does
	-- not also report a trickle of drift sideways.
	return if math.abs(ahead) > M.DEADZONE then ahead else 0,
		if math.abs(sideways) > M.DEADZONE then sideways else 0,
		if gestures.jumping() then 1 else 0
end

return table.freeze {
	button = button,
	movement = movement,
	-- The gesture recogniser's two feeds, gated by this layer's rules so a
	-- feature listening for a tap does not also hear the ones aimed at a menu.
	on_hold = function(changed: (boolean) -> ())
		gestures.listen_hold(available, changed)
	end,
	on_tap = function(tap: (Vector2) -> (), reset: (() -> ())?)
		gestures.listen(available, tap, reset)
	end,
}
