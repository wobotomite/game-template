-- A BUTTON THAT HAS TO BE HELD DOWN, with the fill that shows how far along the
-- hold is.
--
-- For anything a misclick would be expensive on -- wiping a save, leaving a run,
-- spending the last of something. A confirmation dialog asks the same question
-- with a second click, which players learn to click through; a hold cannot be
-- answered by reflex.
--
-- SAME PROPS AS `button`, plus `hold` in seconds, so a panel can promote a
-- button to a held one by adding one field.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"
const GuiService = game:GetService "GuiService"

const vide = require(ReplicatedStorage.Packages.vide)
const ui_sounds = require(ReplicatedStorage.Client.audio["ui-sounds"])
const render_step = require(ReplicatedStorage.Util.events["render-step"])

const base = require(script.Parent["__base"])
const controller_ui = require(script.Parent.Parent["controller-ui"])
const button_hotkey = require(script.Parent["button-hotkey"])
const button = require(script.Parent.button)
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = base.COLORS
const STYLE = base.STYLE
const METRICS = base.METRICS
const HOLD = require(ReplicatedStorage.Shared.settings).ui.HOLD_BUTTON
const peek = base.peek

export type HoldButtonProps = button.ButtonProps & {
	-- Seconds of continuous hold before the button fires.
	hold: number,
}

-- ONE per-frame connection for every hold button on screen, like the kit's
-- eased values. A button's own fill loop would be a connection per button, and
-- a hotbar is ten of them.
const fill_step = render_step()

function hold_button(props: HoldButtonProps): TextButton
	-- Floored, because the fill divides by it: a zero hold is a divide by zero
	-- and fires on the frame it is pressed.
	const hold = math.max(props.hold, HOLD.MIN_HOLD)
	const progress = vide.source(0)
	const holding = vide.source(false)
	-- The keyboard/pad hold is tracked SEPARATELY from the pointer one, because
	-- both can be down at once and either going up must not cancel the other.
	const key_held = vide.source(false)
	const hovering = vide.source(false)
	local touch: InputObject? = nil
	local function release()
		touch = nil
		holding(false)
	end
	-- A mouse released ANYWHERE counts: a press that starts on the button and
	-- ends off it never reaches MouseButton1Up, and the fill would keep running
	-- with nothing held down.
	vide.cleanup(UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			release()
		end
	end))
	local function cancel()
		release()
		key_held(false)
	end
	-- The two ways a hold ends with no input event at all: the window loses
	-- focus, or Roblox's own menu takes over.
	vide.cleanup(UserInputService.WindowFocusReleased:Connect(cancel))
	vide.cleanup(GuiService.MenuOpened:Connect(cancel))

	local function enabled(): boolean
		return base.is_enabled(props.Enabled)
	end
	local function hover()
		if not hovering() and enabled() then
			ui_sounds.hover()
		end
		hovering(true)
	end

	vide.cleanup(fill_step:connect(function(dt: number)
		-- A button that goes disabled or hidden mid-hold empties immediately
		-- rather than keeping its progress for when it comes back: a fill the
		-- player did not earn firing on their next touch is the exact accident
		-- a hold button exists to prevent.
		if not enabled() or peek(props.Visible) == false then
			cancel()
			progress(0)
		end
		if (holding() or key_held()) and enabled() then
			const filled = math.min(progress() + dt / hold, 1)
			progress(filled)
			if filled >= 1 then
				-- Reset BEFORE firing: the handler may close the panel, and a
				-- button left full would fire again the instant it reopened.
				cancel()
				progress(0)
				ui_sounds.click()
				props.Activated()
			end
			return
		end
		-- Drains rather than snapping to zero, so letting go early reads as a
		-- cancellation the player can see rather than as a button that did
		-- nothing.
		if progress() > 0 then
			progress(math.max(progress() - dt * HOLD.DRAIN_RATE / hold, 0))
		end
	end))

	const shortcut = button_hotkey(props.Hotkey, enabled, function(): Color3
		return peek(props.TextColor3) or peek(props.AccentColor) or COLORS.TEXT
	end, function()
		key_held(true)
	end, function()
		key_held(false)
	end, props.GamepadKey)
	const hug = props.Size == nil
	-- The padding the fill has to cover. A hugging button pads its caption, and
	-- a fill that stopped at the padding would leave a visible margin at 100%.
	const inset: () -> number = if hug or shortcut
		then px(METRICS.BUTTON_PAD)
		else function(): number
			return 0
		end

	const result = vide.create "TextButton" {
		Name = "HoldButton",
		InputSink = Enum.InputSink.All,
		Size = props.Size or px.offset(0, METRICS.ACTION_HEIGHT),
		AutomaticSize = if hug then Enum.AutomaticSize.X else nil,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = function(): Color3
			return peek(props.BackgroundColor3) or COLORS.BUTTON_BG
		end,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		-- The fill is a child wider than the button while it grows; without
		-- clipping it would spill out over the layout.
		ClipsDescendants = true,
		Interactable = function(): boolean
			return enabled()
		end,
		-- Blank, because the caption is a separate label drawn ABOVE the fill.
		-- A TextButton's own text renders under its children.
		Text = "",
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,

		-- Down and up rather than Activated: a hold has to know the instant the
		-- press starts, and Activated only fires on a completed click.
		InputBegan = function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch and enabled() and touch == nil then
				touch = input
				holding(true)
			end
		end,
		MouseButton1Down = function()
			if enabled() then
				holding(true)
			end
		end,
		MouseButton1Up = function()
			holding(false)
		end,
		SelectionGained = hover,
		SelectionLost = function()
			hovering(false)
			-- The pad moving off the button ends the hold: there is no "held
			-- while not selected" state for A to be in.
			cancel()
		end,
		MouseEnter = hover,
		MouseLeave = function()
			hovering(false)
			holding(false)
		end,

		if hug or shortcut
			then vide.create "UIPadding" {
				PaddingLeft = px.udim(0, METRICS.BUTTON_PAD),
				PaddingRight = function(): UDim
					return UDim.new(0, inset() + (if shortcut then shortcut.width() else 0))
				end,
			}
			else nil,

		if shortcut then shortcut.label else nil,

		base.stroke(function(): number
			if not enabled() then
				return STYLE.STROKE_DIM
			end
			return if hovering() then 0 else STYLE.STROKE_SOFT
		end, nil, props.AccentColor),

		vide.create "Frame" {
			Name = "Fill",
			-- Starts at the padding's left edge rather than the caption's, and
			-- ends past its right: the fill is the whole PLATE filling up, so it
			-- has to cover the padding the layout added on both sides plus the
			-- key cap's reserved width.
			Position = function(): UDim2
				return UDim2.fromOffset(-inset(), 0)
			end,
			Size = function(): UDim2
				const filled = progress()
				return UDim2.new(
					filled,
					math.round(filled * (inset() * 2 + (if shortcut then shortcut.width() else 0))),
					1,
					0
				)
			end,
			BackgroundColor3 = props.AccentColor or COLORS.OUTLINE,
			BackgroundTransparency = HOLD.FILL_TRANSPARENCY,
			BorderSizePixel = 0,
			ZIndex = 1,
		},

		vide.create "TextLabel" {
			Name = "Caption",
			Size = UDim2.fromScale(1, 1),
			AutomaticSize = if hug then Enum.AutomaticSize.X else nil,
			BackgroundTransparency = 1,
			-- Above the fill, which is ZIndex 1.
			ZIndex = 2,
			FontFace = base.FONTS.HEADING,
			TextColor3 = function(): Color3
				return peek(props.TextColor3) or peek(props.AccentColor) or COLORS.TEXT
			end,
			TextSize = props.TextSize or px(METRICS.TEXT),
			Text = props.Text,

			-- Outlined, because the caption is read against a moving fill: the
			-- contrast under it changes as the hold progresses.
			base.text_outline(),
		},
	}
	if shortcut then
		shortcut.attach(result)
	end
	controller_ui.register(result, enabled, function()
		key_held(true)
	end, function()
		key_held(false)
	end, props.Hotkey, nil, nil, props.GamepadKey)
	return result
end

return hold_button
