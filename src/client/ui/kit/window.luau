-- THE WINDOW: a titled panel with a body and a row of buttons under it.
--
-- Nearly every screen in a game is one of these, so it is the widget that has
-- to get the fiddly parts right once: the title plate straddling the top
-- border, the footer that reserves its own height, the wipe that opens and
-- shuts it, the menu-state claim that blurs the world behind it, and the
-- gamepad focus that makes it navigable without a mouse.
--
-- A WINDOW IS A CENTRED PANEL FITTED TO ITS CONTENT, never a frame stretched to
-- the viewport. "Full screen" in this kit means this window over a blurred,
-- dimmed backdrop -- the world stays visible around it. A panel stretched to
-- the screen edges has been tried and was called weird: it loses the sense of
-- the game still being there, and on a wide monitor it turns one column of text
-- into a billboard.
--
-- THE CALLER GIVES A WIDTH, NOT A HEIGHT. Height is measured from the content
-- unless `height` is passed, because the thing a panel author actually knows is
-- how wide a column of text should be.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const controller_ui = require(script.Parent.Parent["controller-ui"])
const menu_state = require(script.Parent.Parent["menu-state"])

const base = require(script.Parent["__base"])
const button = require(script.Parent.button)
const hold_button = require(script.Parent["hold-button"])
const fit = require(script.Parent["window-fit"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = base.COLORS
const STYLE = base.STYLE
const METRICS = base.METRICS
const peek = base.peek

type Usable<T> = base.Usable<T>

-- A footer button. The bare function is the common case -- a caption and
-- something to do -- and the table form is for a button that also has a state.
export type ButtonSpec = (() -> ()) | {
	on_click: () -> (),
	-- Defaults to the button's KEY in the `buttons` table, so the usual
	-- declaration needs no caption at all.
	text: Usable<string>?,
	visible: Usable<boolean>?,
	enabled: Usable<boolean>?,
	accent: boolean?,
	-- Seconds: present means the button must be held rather than clicked.
	hold: number?,
	-- Drawn in the danger colour. Not the same as `accent`: this one is the
	-- action the player should think twice about, not the one they came for.
	danger: boolean?,
	hotkey: Enum.KeyCode?,
	gamepad_key: Enum.KeyCode?,
}

export type WindowProps = {
	title: Usable<string>,
	title_color: Usable<Color3>?,
	-- Design pixels, scaled by `util/ui/hooks/px`.
	width: Usable<number>,
	-- Omitted means "as tall as the content".
	height: Usable<number>?,
	-- Overrides the headroom reserved for the title plate, for a window whose
	-- first row is art rather than text.
	top_padding: number?,
	open: Usable<boolean>?,

	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	ZIndex: number?,

	-- Keyed by caption. A dictionary rather than an array because a panel
	-- usually wants to name its buttons ("Confirm", "Cancel") and `order` or
	-- `rows` is what decides where they go.
	buttons: { [string]: any }?,
	order: { string }?,
	rows: { { string } }?,

	-- Anything in the array part becomes a body row, in declaration order.
	[number]: any,
}

const TITLE_HALF = METRICS.TITLE_HEIGHT / 2
const STROKE = METRICS.WINDOW_STROKE

-- Far past any body row's order, so the footer is last whatever the body did.
const FOOTER_ORDER = 1000000

type Entry = { name: string, spec: ButtonSpec }

-- Resolve `buttons` + `rows`/`order` into the rows actually to be drawn.
--
-- EVERY BUTTON APPEARS EXACTLY ONCE. A name listed twice is drawn once, and a
-- button the layout forgot is appended to the last row rather than silently
-- dropped -- a declared button that never appears is a bug the author cannot
-- see, where one in the wrong place is obvious.
function button_rows(buttons: { [string]: any }, rows: { { string } }?, order: { string }?): { { Entry } }
	const out: { { Entry } } = {}
	const seen: { [string]: true } = {}
	const layout: { { string } } = if rows then rows else { if order then order else {} }
	for _, names in layout do
		const row: { Entry } = {}
		for _, name in names do
			const spec = buttons[name]
			if spec ~= nil and not seen[name] then
				seen[name] = true
				table.insert(row, { name = name, spec = spec })
			end
		end
		table.insert(out, row)
	end
	const rest: { string } = {}
	for name in buttons do
		if not seen[name] then
			table.insert(rest, name)
		end
	end
	-- Sorted, because iteration order over a dictionary is not stable: without
	-- this the leftovers would move between sessions.
	table.sort(rest)
	if #rest > 0 then
		if #out == 0 then
			table.insert(out, {})
		end
		const last = out[#out]
		for _, name in rest do
			table.insert(last, { name = name, spec = buttons[name] })
		end
	end
	return out
end

function build_button(entry: Entry, index: number): TextButton
	const spec: ButtonSpec = entry.spec
	-- The bare-function form expanded into the table form, so everything below
	-- has one shape to read.
	const detail = if type(spec) == "function" then { on_click = spec :: () -> () } else spec
	const text: Usable<string> = detail.text or entry.name
	const color: Color3? = if detail.danger then COLORS.DANGER else nil
	if detail.hold then
		return hold_button {
			Text = text,
			Hotkey = detail.hotkey,
			GamepadKey = detail.gamepad_key,
			Activated = detail.on_click,
			Visible = detail.visible,
			Enabled = detail.enabled,
			accent = detail.accent,
			-- Both, because `danger` colours the caption AND opts the button
			-- out of the kit's hover inversion: a red plate lighting up on
			-- hover reads as "selected", which is the wrong idea for the one
			-- button in the row the player might regret.
			TextColor3 = color,
			AccentColor = color,
			LayoutOrder = index,
			hold = detail.hold,
		}
	end
	return button {
		Text = text,
		Hotkey = detail.hotkey,
		GamepadKey = detail.gamepad_key,
		Activated = detail.on_click,
		Visible = detail.visible,
		Enabled = detail.enabled,
		accent = detail.accent,
		TextColor3 = color,
		AccentColor = color,
		LayoutOrder = index,
	}
end

function build_row(entries: { Entry }, index: number): Frame
	const children: { Instance } = {}
	for position, entry in entries do
		table.insert(children, build_button(entry, position))
	end
	return vide.create "Frame" {
		Name = `Row{index}`,
		Size = px.udim2(1, 0, 0, METRICS.ACTION_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		-- A row of entirely hidden buttons hides itself, so the footer does not
		-- keep a row's worth of empty space for buttons nobody can see.
		Visible = function(): boolean
			for _, entry in entries do
				const spec = entry.spec
				const visible = if type(spec) == "function" then nil else peek(spec.visible)
				if visible ~= false then
					return true
				end
			end
			return false
		end,

		vide.create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = px.udim(0, METRICS.GAP),
		},

		children,
	}
end

-- Returns the footer frame and the height it needs, because the body has to
-- know that number before either of them is parented.
function footer(props: WindowProps): (Frame?, number)
	const buttons = props.buttons
	if buttons == nil or next(buttons) == nil then
		return nil, 0
	end
	const rows = button_rows(buttons, props.rows, props.order)
	const children: { Instance } = {}
	for index, entries in rows do
		table.insert(children, build_row(entries, index))
	end

	return vide.create "Frame" {
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = FOOTER_ORDER,

		vide.create "UIListLayout" {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = px.udim(0, METRICS.GAP),
		},

		-- Not `base.rule`: this divider is the one the window RESERVES height
		-- for, so it is drawn at exactly `STYLE.WINDOW_RULE` rather than at the
		-- rule primitive's own thickness.
		vide.create "Frame" {
			Name = "ButtonDivider",
			Size = px.udim2(1, 0, 0, STYLE.WINDOW_RULE),
			BackgroundColor3 = COLORS.OUTLINE,
			BackgroundTransparency = STYLE.STROKE_SOFT,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		},
		children,
	},
		fit.body_offset(#rows)
end

function window(props: WindowProps): Frame
	-- The holder identity `menu-state` refcounts by. A fresh table per window,
	-- so two windows of the same kind never share a claim.
	const menu = {}
	vide.effect(function()
		menu_state.set(menu, peek(props.open) ~= false)
	end)
	-- A window destroyed while open would otherwise leave the world blurred
	-- forever: nothing else knows this holder existed.
	vide.cleanup(function()
		menu_state.set(menu, false)
	end)
	-- Open and shut by wiping the window's height, which is why the outer frame
	-- clips: the sheet inside keeps its full size and is revealed, so nothing
	-- inside it reflows during the animation.
	const wipe = base.eased(function(): number
		return if peek(props.open) == false then 0 else 1
	end, METRICS.WIPE_RATE)

	const buttons, body_offset = footer(props)
	const fixed = props.height ~= nil

	const body = vide.create "Frame" {
		Name = "Body",
		-- A fixed-height window gives the body what is left after the footer; a
		-- hugging one lets the body decide and grows to match.
		Size = if fixed then px.udim2(1, 0, 1, -body_offset) else UDim2.new(1, 0, 0, 0),
		AutomaticSize = if fixed then nil else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,

		vide.create "UIListLayout" {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = px.udim(0, METRICS.GAP),
		},

		-- The caller's array part: everything declared positionally in the
		-- window's own table becomes a body row.
		table.move(props, 1, #props, 1, {} :: { any }),
	}
	-- DECLARATION ORDER IS THE LAYOUT ORDER. A list layout sorts on
	-- LayoutOrder and ties break arbitrarily, so rows a panel did not number
	-- would come out in whatever order the engine felt like. Only untouched
	-- ones are numbered, so a row that set its own order keeps it.
	for index, child in body:GetChildren() do
		if child:IsA "GuiObject" and child.LayoutOrder == 0 then
			child.LayoutOrder = index
		end
	end

	const sheet = vide.create "Frame" {
		Name = "Sheet",
		-- Sinks, so a click that misses a control inside the window is not also
		-- a click on the world behind it.
		InputSink = Enum.InputSink.All,
		-- Inset by its own border on each side, and pushed down by the half of
		-- the title plate that sits above the window's top edge.
		Position = function(): UDim2
			return UDim2.fromOffset(base.hairline(STROKE)(), px(TITLE_HALF)())
		end,
		Size = function(): UDim2
			return UDim2.new(
				1,
				-base.hairline(STROKE)() * 2,
				0,
				if fixed then px(peek(props.height) :: number)() else 0
			)
		end,
		AutomaticSize = if fixed then nil else Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		BackgroundColor3 = COLORS.PANEL_BG,
		-- OPAQUE, unlike the kit's other surfaces: a window is the thing being
		-- read, and the backdrop behind it is already doing the job of keeping
		-- the world present.
		BackgroundTransparency = 0,

		base.stroke(0, base.hairline(STROKE)),

		vide.create "UIPadding" {
			-- The extra TITLE_HALF is the headroom under the plate, so the
			-- first body row does not start behind it.
			PaddingTop = px.udim(0, props.top_padding or METRICS.INSET + TITLE_HALF),
			PaddingBottom = px.udim(0, METRICS.INSET),
			PaddingLeft = px.udim(0, METRICS.INSET),
			PaddingRight = px.udim(0, METRICS.INSET),
		},
		vide.create "UIListLayout" {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = px.udim(0, METRICS.GAP),
		},

		body,
		buttons,
	}

	-- The sheet's own height, watched rather than computed: a hugging window's
	-- height is whatever its content came out as, and only the engine knows
	-- that after it has laid the content out.
	const measured = vide.source(0)
	vide.cleanup(sheet:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		measured(sheet.AbsoluteSize.Y)
	end))

	const result = vide.create "Frame" {
		Name = "Window",
		Size = function(): UDim2
			return UDim2.fromOffset(
				px(peek(props.width) :: number)(),
				fit.outer(px(TITLE_HALF)(), measured(), base.hairline(STROKE)(), wipe())
			)
		end,
		-- Centred by default. See the note at the top of this file: this is
		-- what "full screen" means here.
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = props.ZIndex,
		-- Hidden rather than zero-height when shut: a zero-height frame still
		-- takes input on its border and still costs a layout pass.
		Visible = function(): boolean
			return wipe() > 0
		end,

		sheet,

		vide.create "TextLabel" {
			Name = "Title",
			-- A plate STRADDLING the top border -- half above, half below --
			-- which is what makes the window read as a labelled object rather
			-- than as a box with a heading inside it.
			Size = px.offset(0, METRICS.TITLE_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			Position = px.udim2(0.5, 0, 0, TITLE_HALF),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			BackgroundColor3 = props.title_color or COLORS.OUTLINE,
			BackgroundTransparency = 0,
			ZIndex = 2,
			FontFace = base.FONTS.HEADING,
			-- The plate is the outline colour, so its text has to be the panel
			-- colour: the title is knocked out of the plate rather than drawn
			-- on it.
			TextColor3 = COLORS.PANEL_BG,
			TextSize = px(METRICS.TITLE_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = props.title,

			vide.create "UIPadding" {
				PaddingLeft = px.udim(0, METRICS.GAP),
				PaddingRight = px.udim(0, METRICS.GAP),
			},
		},
	}
	controller_ui.window(result, function(): boolean
		return peek(props.open) ~= false
	end)
	return result
end

return window
