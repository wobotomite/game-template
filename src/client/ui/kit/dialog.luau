-- A DIALOG: one question, a few centred lines, and the buttons that answer it.
--
-- A thin wrapper over `window` rather than a widget of its own, because that is
-- all a dialog is -- a narrow window whose body is prose. It exists so the
-- twenty callers that ask "are you sure?" do not each pick their own width,
-- their own alignment and their own text size.
--
-- LINES, NOT A BLOCK OF TEXT. A dialog's body is an array, so a caller can make
-- one line reactive, colour a second and leave the third alone, without
-- building any of them itself.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const base = require(script.Parent["__base"])
const text = require(script.Parent.text)
const window = require(script.Parent.window)
const DIALOG = require(ReplicatedStorage.Shared.settings).ui.DIALOG

type Usable<T> = base.Usable<T>

-- A bare string (or a function returning one) for the common case; the full
-- text props for a line that needs a colour or a size.
export type Line = Usable<string> | text.TextProps

export type DialogProps = {
	title: Usable<string>,
	title_color: Usable<Color3>?,
	-- Design pixels. Defaults to `settings.ui.DIALOG.WIDTH`.
	width: number?,
	open: Usable<boolean>?,

	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	ZIndex: number?,

	lines: { Line }?,
	buttons: { [string]: any }?,
	order: { string }?,
	rows: { { string } }?,

	-- Anything positional is appended after the lines, for a dialog that needs
	-- a widget as well as prose.
	[number]: any,
}

function dialog(props: DialogProps): Frame
	const body: { any } = {}
	const lines: { Line } = props.lines or {}
	for _, line in lines do
		-- CLONED, never written through: the caller's table may be a shared
		-- constant, and defaulting two fields on it would quietly restyle every
		-- other dialog built from the same table.
		const line_props: text.TextProps = if type(line) == "table" then table.clone(line :: any) else { Text = line }
		-- Body text and centred unless the line says otherwise. Centred because
		-- a dialog is a handful of short lines under a title, where left
		-- alignment leaves the block hanging off one side of a narrow window.
		if line_props.body == nil then
			line_props.body = true
		end
		line_props.TextXAlignment = line_props.TextXAlignment or Enum.TextXAlignment.Center
		table.insert(body, text(line_props))
	end
	for index = 1, #props do
		table.insert(body, props[index])
	end
	const window_props: window.WindowProps = {
		title = props.title,
		title_color = props.title_color,
		width = props.width or DIALOG.WIDTH,
		open = props.open,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex,
		buttons = props.buttons,
		order = props.order,
		rows = props.rows,
	}
	-- ONE body row holding the whole list, so the lines stay together as a
	-- block and the window's own list layout spaces the block, not the lines.
	table.insert(window_props, body)
	return window(window_props)
end

return dialog
