-- THE KEYBOARD AND GAMEPAD HALF OF A BUTTON.
--
-- Given the key a button wants, this makes the binding that fires it, the cap
-- that shows it (`input-label`), and the rules for when either is live. The
-- kit's buttons call it; a panel does not.
--
-- ITS OWN InputContext PER BUTTON, enabled only while that button is on screen
-- and eligible. Buttons come and go with panels, and the engine resolves a key
-- to the highest-priority ENABLED context -- so an E belonging to a closed
-- panel simply is not in the running, and two panels each claiming E never have
-- to know about each other.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const Players = game:GetService "Players"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)
const input = require(ReplicatedStorage.Util.input)
const px = require(ReplicatedStorage.Util.ui.hooks.px)
const controller_ui = require(script.Parent.Parent["controller-ui"])
const input_label = require(script.Parent["input-label"])
const input_state = require(ReplicatedStorage.Client.input["input-state"])
const PAD = require(ReplicatedStorage.Shared.settings).controls.GAMEPAD
const STYLE = require(ReplicatedStorage.Shared.settings).ui.BUTTON_HOTKEY

export type Hotkey = { label: InputActionLabel, width: () -> number, attach: (GuiButton) -> () }

return function(
	key: Enum.KeyCode?,
	enabled: () -> boolean,
	color: () -> Color3,
	pressed: () -> (),
	released: (() -> ())?,
	gamepad_key: Enum.KeyCode?
): Hotkey?
	-- A button with no key at all gets no badge and no binding, which is the
	-- common case: most buttons are clicked.
	if not key and not gamepad_key then
		return nil
	end
	const context = input.context("MenuButton", { enabled = false, sink = true, priority = STYLE.PRIORITY })
	-- The kit's two ROLES map onto the pad's two: a button whose key is the
	-- primary one is the pad's confirm, one whose key is cancel is the pad's
	-- back. Any other key gets the pad button it asked for, bound directly.
	const pad_key = gamepad_key or (if key == STYLE.CANCEL then PAD.CANCEL else PAD.CONFIRM)
	const action = context:action("Activate", { keys = if key then { key } else {} })
	-- Confirm and cancel are NOT bound here: while a pad is driving a panel
	-- those belong to `controller-ui`, which owns the focus and therefore knows
	-- which button A means. Binding them here as well would fire two buttons.
	if pad_key ~= PAD.CONFIRM and pad_key ~= PAD.CANCEL then
		action:bind_key(pad_key)
	end

	const shown = vide.source(false)
	-- The key must be seen to go UP before it counts. Otherwise a key already
	-- held when the panel opens fires the button it happened to land on -- and,
	-- worse, the key that closed one panel activates the next one.
	local armed = false
	local function release()
		if released then
			released()
		end
	end
	local function eligible(): boolean
		return shown()
			and enabled()
			and input_state.available()
			and (
				input_state.preferred() ~= Enum.PreferredInput.Gamepad
				or (pad_key ~= PAD.CONFIRM and pad_key ~= PAD.CANCEL)
			)
	end
	-- The InputContext is an instance, not a vide thing: without this every
	-- reopened panel would leave another live copy of the same binding behind.
	vide.cleanup(function()
		context:destroy()
	end)
	vide.effect(function()
		const active = eligible()
		armed = active and (key == nil or not UserInputService:IsKeyDown(key))
		context.instance.Enabled = active
		-- A button that goes ineligible mid-press owes its release: a held
		-- action would otherwise stay held forever.
		if not active then
			release()
		end
	end)
	vide.cleanup(action.instance.Pressed:Connect(function()
		if eligible() and armed then
			armed = false
			pressed()
		end
	end))
	vide.cleanup(action.instance.Released:Connect(function()
		armed = true
		release()
	end))
	-- Belt and braces on the release: the action reports nothing once its
	-- context has been disabled, and the key going up while disabled is exactly
	-- the case that leaves a button stuck down.
	vide.cleanup(UserInputService.InputEnded:Connect(function(event: InputObject)
		if event.KeyCode == key or event.KeyCode == pad_key then
			armed = true
			release()
		end
	end))

	const label = input_label(function(): InputAction
		-- While a pad is in charge, the cap draws the NAVIGATION context's
		-- confirm or cancel rather than this button's own action -- that is the
		-- action actually bound to the pad, so it is the one whose glyph is
		-- true.
		if input_state.preferred() == Enum.PreferredInput.Gamepad then
			if pad_key == PAD.CONFIRM then
				return controller_ui.confirm
			end
			if pad_key == PAD.CANCEL then
				return controller_ui.cancel
			end
		end
		return action.instance
	end, color)

	-- NO CAP ON TOUCH. There is no key to press on a phone, and a key cap next
	-- to a button the player is about to tap is noise.
	local function hint(): boolean
		return enabled() and input_state.preferred() ~= Enum.PreferredInput.Touch
	end
	-- How far the cap sticks out past the button's right edge, which is also
	-- what the button adds to its own width to make room -- zero when no cap is
	-- drawn, so a touch layout is not padded for a hint it never shows.
	local function width(): number
		return if hint() then px(STYLE.SIZE + STYLE.GAP)() else 0
	end
	vide.apply(label) {
		Position = function(): UDim2
			return UDim2.new(1, width(), 0.5, 0)
		end,
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = hint,
	}

	-- IS THE BUTTON ACTUALLY ON SCREEN. There is no signal for "my effective
	-- visibility changed", so the whole ancestor chain is watched and the
	-- answer recomputed -- and rewatched on every ancestry change, because the
	-- chain itself is what moves when a panel is reparented or mounted.
	local function attach(button: GuiButton)
		local connections: { RBXScriptConnection } = {}
		local function disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end
		local function refresh()
			local ancestor: Instance? = button
			while ancestor do
				if ancestor:IsA "GuiObject" and not ancestor.Visible then
					shown(false)
					return
				end
				if ancestor:IsA "LayerCollector" and not ancestor.Enabled then
					shown(false)
					return
				end
				if ancestor:IsA "PlayerGui" then
					shown(ancestor.Parent == Players.LocalPlayer)
					return
				end
				ancestor = ancestor.Parent
			end
			-- Ran out of ancestors: the button is not in a PlayerGui at all,
			-- so it is not on anyone's screen.
			shown(false)
		end
		local function watch()
			disconnect()
			local ancestor: Instance? = button
			while ancestor do
				if ancestor:IsA "GuiObject" then
					table.insert(connections, ancestor:GetPropertyChangedSignal("Visible"):Connect(refresh))
				elseif ancestor:IsA "LayerCollector" then
					table.insert(connections, ancestor:GetPropertyChangedSignal("Enabled"):Connect(refresh))
				end
				ancestor = ancestor.Parent
			end
			refresh()
		end
		vide.cleanup(disconnect)
		vide.cleanup(button.AncestryChanged:Connect(watch))
		watch()
	end

	return { label = label, width = width, attach = attach }
end
