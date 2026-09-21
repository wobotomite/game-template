-- A LABEL. The kit's only text primitive: every word a widget draws goes
-- through here, so the font, the colour and the outline are decided once.
--
-- Takes the TextLabel properties you would expect, plus two shorthands:
--   `body` picks the monospace face instead of the heading face
--   `dim`  picks the secondary text colour
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)

const base = require(script.Parent["__base"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = base.COLORS
const METRICS = base.METRICS
const LINE_LEAD = require(ReplicatedStorage.Shared.settings).ui.TEXT.LINE_LEAD

type Usable<T> = base.Usable<T>

export type TextProps = {
	Text: Usable<string>,
	Size: Usable<UDim2>?,
	AutomaticSize: Enum.AutomaticSize?,
	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	TextSize: Usable<number>?,
	TextColor3: Usable<Color3>?,

	body: boolean?,
	dim: boolean?,

	TextXAlignment: Usable<Enum.TextXAlignment>?,
	TextYAlignment: Usable<Enum.TextYAlignment>?,
	TextWrapped: boolean?,
	TextScaled: boolean?,
	RichText: boolean?,
	TextTransparency: Usable<number>?,
	Transparency: Usable<number>?,
	StrokeColor3: Usable<Color3>?,
	StrokeThickness: Usable<number>?,
	Visible: Usable<boolean>?,
	ZIndex: number?,
	LayoutOrder: number?,

	[number]: any,
}

function text(props: TextProps): TextLabel
	const size: Usable<number> = props.TextSize or px(METRICS.TEXT)

	-- DEFAULT HEIGHT IS THE LINE BOX, not the text size. A label exactly as
	-- tall as its own text clips descenders as soon as `px` scaling lands the
	-- size on a fraction, so every label gets `LINE_LEAD` of leading. Full
	-- width, because a label in a list layout is a row.
	--
	-- Two branches because a scaled size is a function and a fixed one is a
	-- number: binding a constant as a function would make vide re-evaluate it.
	const line_height = if type(size) == "function"
		then function(): UDim2
			return UDim2.new(1, 0, 0, (size :: () -> number)() + px(LINE_LEAD)())
		end
		else UDim2.new(1, 0, 0, (size :: number) + LINE_LEAD)

	-- `Transparency` fades the text AND its outline together, which is what a
	-- caller fading a whole label means. Derived so that both properties read
	-- one cached value per frame instead of calling the caller's function
	-- twice.
	const fade: Usable<number>? = if type(props.Transparency) == "function"
		then vide.derive(function(): number
			return (props.Transparency :: () -> number)()
		end)
		else props.Transparency

	-- An explicit `TextTransparency` wins: it fades the glyphs and leaves the
	-- outline, which is how a label is greyed out without losing its edge.
	const transparency = props.TextTransparency or fade

	const label = vide.create "TextLabel" {
		Name = "Text",
		Size = props.Size or line_height,
		AutomaticSize = props.AutomaticSize,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,

		FontFace = if props.body then base.FONTS.BODY else base.FONTS.HEADING,
		TextColor3 = props.TextColor3 or (if props.dim then COLORS.TEXT_DIM else COLORS.TEXT),
		TextSize = size,
		-- Left unless asked otherwise: a column of left-aligned labels lines
		-- up, and centring is the exception (a dialog line, a badge).
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment,
		TextWrapped = props.TextWrapped,
		TextScaled = props.TextScaled,
		RichText = props.RichText,
		Text = props.Text,
		TextTransparency = transparency,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,

		base.text_outline(props.StrokeColor3, props.StrokeThickness, transparency),
	}

	-- Children passed in the array part (a UIPadding, a gradient, an icon).
	-- Copied out first: `vide.apply` over the whole props table would try to
	-- write `body` and `dim` as properties.
	const children = table.move(props, 1, #props, 1, {} :: { any })
	if children[1] ~= nil then
		vide.apply(label)(children)
	end
	return label
end

return text
