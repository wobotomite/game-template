-- A BUTTON, and the three devices that can press it.
--
-- A caption, a click handler, and -- if it is given a key -- the binding, the
-- key cap and the gamepad registration that come with one. A panel writes
-- `button { Text = ..., Activated = ..., Hotkey = Enum.KeyCode.E }` and the
-- mouse, the keyboard, the pad and a touchscreen all work.
--
-- HUGS ITS TEXT BY DEFAULT. Omitting `Size` gives a button as wide as its
-- caption plus padding, which is what a row of footer buttons wants; passing
-- one turns that off, for a button that has to fill a cell.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const ui_sounds = require(ReplicatedStorage.Client.audio["ui-sounds"])

const controller_ui = require(script.Parent.Parent["controller-ui"])
const button_hotkey = require(script.Parent["button-hotkey"])
const base = require(script.Parent["__base"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = base.COLORS
const STYLE = base.STYLE
const METRICS = base.METRICS
const peek = base.peek

type Usable<T> = base.Usable<T>

export type ButtonProps = {
	Text: Usable<string>,
	Activated: () -> (),

	Size: Usable<UDim2>?,
	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	TextSize: Usable<number>?,
	TextColor3: Usable<Color3>?,
	-- A colour for the border, the caption and the hold fill, INSTEAD of the
	-- kit's inversion: a button given one is always drawn in that colour rather
	-- than flipping to a filled plate on hover. That is what the danger button
	-- uses, where a hovered red button reading as "selected" is the wrong idea.
	AccentColor: Usable<Color3>?,
	BackgroundColor3: Usable<Color3>?,

	-- Drawn filled at rest and hollow on hover -- the inverse of a normal
	-- button. For the one action in a panel that the player is expected to
	-- take.
	accent: boolean?,
	Hotkey: Enum.KeyCode?,
	GamepadKey: Enum.KeyCode?,

	Enabled: Usable<boolean>?,
	Visible: Usable<boolean>?,
	ZIndex: number?,
	LayoutOrder: number?,
}

function button(props: ButtonProps): TextButton
	const hovering = vide.source(false)

	local function enabled(): boolean
		return base.is_enabled(props.Enabled)
	end
	-- Checked here as well as by `Interactable`, because the keyboard and pad
	-- paths reach `activate` without passing through the engine's own gate.
	local function activate()
		if not enabled() then
			return
		end
		ui_sounds.click()
		props.Activated()
	end
	-- Only on the EDGE, and only when there is something to press: sweeping the
	-- cursor across a row of buttons should tick once per button, and a dead
	-- button should not answer at all.
	local function hover()
		if not hovering() and enabled() then
			ui_sounds.hover()
		end
		hovering(true)
	end

	-- The fill/hollow flip. An accent button starts filled and hollows out on
	-- hover; a normal one does the opposite. Either way the hovered state is
	-- the one that differs from the row around it.
	local function inverted(): boolean
		if props.AccentColor then
			return false
		end
		const hot = hovering() and enabled()
		return if props.accent then not hot else hot
	end

	local function text_color(): Color3
		-- Inverted means the background is the outline colour, so the caption
		-- has to become the PANEL colour to stay legible.
		if inverted() then
			return COLORS.PANEL_BG
		end
		return peek(props.TextColor3) or peek(props.AccentColor) or COLORS.TEXT
	end

	const shortcut = button_hotkey(props.Hotkey, enabled, function(): Color3
		return peek(props.TextColor3) or peek(props.AccentColor) or COLORS.TEXT
	end, activate, nil, props.GamepadKey)
	const hug = props.Size == nil

	const result = vide.create "TextButton" {
		Name = "Button",
		-- Sinks, so a click on a button is not also a click on the world behind
		-- the panel.
		InputSink = Enum.InputSink.All,
		Size = props.Size or px.offset(0, METRICS.ACTION_HEIGHT),
		AutomaticSize = if hug then Enum.AutomaticSize.X else nil,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = function(): Color3
			if inverted() then
				return COLORS.OUTLINE
			end
			return peek(props.BackgroundColor3) or COLORS.BUTTON_BG
		end,
		BorderSizePixel = 0,
		-- The kit draws its own states. AutoButtonColor tints the background by
		-- a fixed amount, which fights every theme and does nothing useful on a
		-- button that is already dark.
		AutoButtonColor = false,
		Interactable = function(): boolean
			return enabled()
		end,
		FontFace = base.FONTS.HEADING,
		TextColor3 = text_color,
		TextSize = props.TextSize or px(METRICS.TEXT),
		Text = props.Text,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		Activated = function(event: InputObject)
			-- A pad press arrives BOTH here and through `controller-ui`, which
			-- is the path that knows about focus. Ignored here so the button
			-- does not fire twice.
			if event.UserInputType.Name:match "^Gamepad" then
				return
			end
			activate()
		end,

		-- Selection is the pad's version of hover, so it makes the same sound
		-- and draws the same state.
		MouseEnter = hover,
		MouseLeave = function()
			hovering(false)
		end,
		SelectionGained = hover,
		SelectionLost = function()
			hovering(false)
		end,

		-- Padding only when there is something to pad: a fixed-size button with
		-- no key cap centres its own caption. The RIGHT side also reserves the
		-- cap's width, so the caption stays centred with the cap beside it
		-- rather than under it.
		if hug or shortcut
			then vide.create "UIPadding" {
				PaddingLeft = px.udim(0, METRICS.BUTTON_PAD),
				PaddingRight = function(): UDim
					return UDim.new(0, px(METRICS.BUTTON_PAD)() + (if shortcut then shortcut.width() else 0))
				end,
			}
			else nil,

		if shortcut then shortcut.label else nil,

		base.stroke(function(): number
			if not enabled() then
				return STYLE.STROKE_DIM
			end
			-- Fully opaque on hover: the border sharpening is what says the
			-- button is live, and it works in greyscale.
			return if hovering() then 0 else STYLE.STROKE_SOFT
		end, nil, props.AccentColor),
	}
	if shortcut then
		shortcut.attach(result)
	end
	controller_ui.register(result, enabled, activate, nil, props.Hotkey, nil, nil, props.GamepadKey)
	return result
end

return button
