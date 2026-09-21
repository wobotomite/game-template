-- THE KEY CAP: a small square showing which key or pad button works here.
--
-- Built on `InputActionLabel`, which is the engine's own answer: given an
-- InputAction, it draws whatever that action is CURRENTLY bound to, on the
-- device the player is CURRENTLY using, including the platform's real glyphs
-- for a pad. A game that drew the letter itself would be wrong the moment a
-- player rebound a key, picked up a controller, or joined on a layout where the
-- key is somewhere else.
--
-- THE FALLBACK IS MOST OF THIS FILE. `InputActionLabel` renders nothing at all
-- when it cannot resolve the binding -- a device with no glyph for the key, a
-- binding that arrives a frame later -- and a blank square where a hint should
-- be is worse than a plain letter. So a hand-drawn cap sits underneath and
-- shows itself exactly when the engine's own rendering came out empty.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)
const base = require(script.Parent["__base"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)
const STYLE = require(ReplicatedStorage.Shared.settings).ui.BUTTON_HOTKEY

-- `action` is a Usable so a caller can swap the whole action as the input
-- device changes -- the same badge showing a keyboard key one moment and the
-- pad's confirm button the next.
return function(action: base.Usable<InputAction>, color: base.Usable<Color3>?): InputActionLabel
	-- Nothing this label reads is a vide source: bindings are instances, the
	-- preferred device is an engine property, and the resolved text is written
	-- by the engine. One counter stands in for all of them, and every signal
	-- below simply bumps it.
	const revision = vide.source(0)
	const bindings = vide.source({} :: { Instance })
	local function refresh()
		revision(revision() + 1)
	end
	vide.effect(function()
		const current = base.peek(action) :: InputAction
		local function rebuild()
			bindings(current:GetChildren())
		end
		vide.cleanup(current.ChildAdded:Connect(rebuild))
		vide.cleanup(current.ChildRemoved:Connect(rebuild))
		rebuild()
	end)
	vide.cleanup(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh))
	-- As well as PreferredInput, because a keyboard player who nudges a stick
	-- should see pad glyphs before the engine has decided they have switched.
	vide.cleanup(UserInputService.LastInputTypeChanged:Connect(refresh))
	vide.effect(function()
		for _, binding in bindings() do
			if binding:IsA "InputBinding" then
				vide.cleanup(binding.Changed:Connect(refresh))
			end
		end
	end)

	-- Which binding to draw, and how. An action usually carries several -- a
	-- key AND a pad button -- and the one to show is the one for the device in
	-- the player's hands. `GetImageForKeyCode` returning something is the test
	-- for "this is a pad button": there is no glyph for a letter.
	local function binding_hint(): (string, string)
		revision()
		const gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
		for _, binding in bindings() do
			if not binding:IsA "InputBinding" or binding.KeyCode == Enum.KeyCode.None then
				continue
			end
			const key = binding.KeyCode
			const image = UserInputService:GetImageForKeyCode(key)
			if gamepad ~= (image ~= "") then
				continue
			end
			-- `DisplayName` is what the binding was given to call itself; the
			-- engine's own name for the key is the fallback, and it is the one
			-- that respects the player's keyboard layout.
			return if binding.DisplayName ~= "" then binding.DisplayName else UserInputService:GetStringForKeyCode(key),
				image
		end
		return "", ""
	end

	const label = vide.create "InputActionLabel" {
		Name = "Hotkey",
		InputAction = action,
		-- Sinks whatever lands on the cap itself, so a click on the hint is
		-- not also a click on the world behind the panel.
		InputSink = Enum.InputSink.All,
		Size = px.offset(STYLE.SIZE, STYLE.SIZE),
		BackgroundColor3 = base.COLORS.PANEL_BG,
		BackgroundTransparency = STYLE.BACKGROUND_ALPHA,
		BorderSizePixel = 0,
		FontFace = base.FONTS.HEADING,
		TextSize = px(STYLE.TEXT_SIZE),
		TextColor3 = color or base.COLORS.TEXT,
		ImageColor3 = color or base.COLORS.TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		-- Above the button it is pinned to, which draws its own background and
		-- border.
		ZIndex = 3,

		base.stroke(nil, nil, color),
	}
	vide.cleanup(label:GetPropertyChangedSignal("ResolvedText"):Connect(refresh))
	vide.cleanup(label:GetPropertyChangedSignal("ResolvedImageContent"):Connect(refresh))

	-- Parented directly rather than passed as a child, because the label is
	-- returned to the caller to position and this frame must travel with it.
	vide.create "Frame" {
		Name = "Fallback",
		Parent = label,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = base.COLORS.PANEL_BG,
		BackgroundTransparency = STYLE.BACKGROUND_ALPHA,
		BorderSizePixel = 0,
		-- BOTH have to be empty. Text alone is not the test: a pad glyph is an
		-- image, and an action bound only to a stick resolves to neither.
		Visible = function(): boolean
			revision()
			return label.ResolvedText == "" and label.ResolvedImageContent.SourceType == Enum.ContentSourceType.None
		end,

		base.stroke(nil, nil, color),

		vide.create "TextLabel" {
			Name = "Key",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = base.FONTS.HEADING,
			TextColor3 = color or base.COLORS.TEXT,
			TextSize = px(STYLE.TEXT_SIZE),
			-- One of the two draws and the other is blank, rather than one
			-- element switching between a glyph and a letter: an ImageLabel
			-- cannot draw text and a TextLabel cannot draw the pad glyph.
			Text = function(): string
				const text, image = binding_hint()
				return if image == "" then text else ""
			end,
		},
		vide.create "ImageLabel" {
			Name = "Gamepad",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageColor3 = color or base.COLORS.TEXT,
			Image = function(): string
				const _, image = binding_hint()
				return image
			end,
		},
	}
	return label
end
