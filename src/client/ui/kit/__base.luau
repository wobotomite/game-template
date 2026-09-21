-- THE KIT'S PRIVATE FOUNDATION: the theme, read once, and the handful of
-- primitives every widget in this folder is built out of.
--
-- Not part of the kit's public surface -- the double underscore is the marker,
-- and `init.luau` re-exports only the parts a panel outside this folder has any
-- business with. Widgets here require it directly.
--
-- WHY A BASE MODULE AT ALL. Without it, each widget reaches into `settings.ui`
-- for itself and each one gets to disagree about what a border looks like. The
-- theme is read here, once, and a widget that wants a border calls `stroke()`.
-- That is what makes a reskin a settings edit rather than a sweep.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const ui = require(ReplicatedStorage.Shared.settings).ui
const assets = require(ReplicatedStorage.Shared.assets)
const render_step = require(ReplicatedStorage.Util.events["render-step"])
const approach = require(ReplicatedStorage.Util.numbers.approach)
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = ui.COLORS
const FONTS = assets.fonts
const STYLE = ui.STYLE
const METRICS = ui.METRICS

-- A prop is either the value or a function returning it. vide reads the
-- function every time its sources change, so `Usable` is how a widget accepts
-- "this colour" and "this colour, which moves" through the same argument.
export type Usable<T> = T | () -> T

-- Read a Usable ONCE, outside any reactive scope. For the cases where a widget
-- needs the value to build something with -- a size to measure, a key to
-- compare -- rather than to bind to a property.
function peek<T>(value: Usable<T>?): T?
	return if type(value) == "function" then (value :: () -> T)() else value :: T?
end

-- Absent means enabled. Every `enabled`/`visible` prop in the kit is optional,
-- and a widget with no opinion should be usable, not dead.
function is_enabled(value: Usable<boolean>?): boolean
	const resolved = peek(value)
	return resolved == nil or resolved == true
end

-- A line that stays a line. `px` scales design pixels for the viewport, and on
-- a small screen a 1px rule scales to 0.6 and the engine rounds it away
-- entirely -- so borders and dividers vanish on exactly the devices where the
-- layout is hardest to read. Clamped at one real pixel.
function hairline(units: number): () -> number
	return function(): number
		return math.max(px(units)(), 1)
	end
end

-- The kit's border. Applied as a CHILD of the frame it borders (vide parents
-- instance children passed in the array part), so a caller writes
-- `base.stroke()` inside the frame's prop table.
function stroke(transparency: Usable<number>?, thickness: Usable<number>?, color: Usable<Color3>?): UIStroke
	return vide.create "UIStroke" {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or COLORS.OUTLINE,
		Thickness = thickness or hairline(STYLE.STROKE),
		Transparency = transparency or STYLE.STROKE_SOFT,
	}
end

-- The outline behind text. Contextual, not Border: on a TextLabel that draws
-- around the GLYPHS, which is the point -- panels are semi-transparent and HUD
-- text sits straight on the world, so without it light text disappears over
-- anything light.
function text_outline(color: Usable<Color3>?, thickness: Usable<number>?, transparency: Usable<number>?): UIStroke
	return vide.create "UIStroke" {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		-- Miter, so the outline keeps the letterform's corners instead of
		-- rounding them into a blob at small sizes.
		LineJoinMode = Enum.LineJoinMode.Miter,
		Color = color or STYLE.TEXT_OUTLINE,
		Thickness = thickness or hairline(STYLE.TEXT_OUTLINE_PX),
		Transparency = transparency or STYLE.TEXT_OUTLINE_SOFT,
	}
end

export type SlabProps = {
	Size: Usable<UDim2>,
	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	BackgroundColor3: Usable<Color3>?,
	BackgroundTransparency: Usable<number>?,
	Visible: Usable<boolean>?,
	ZIndex: number?,
	LayoutOrder: number?,
	ClipsDescendants: boolean?,
	[number]: any,
}

-- A panel-coloured, bordered rectangle: the kit's generic surface, and what
-- every widget that needs to look like part of a window is made of.
--
-- Built and then applied rather than declared in one table so the caller's
-- props OVERRIDE the defaults above -- vide's `apply` writes over what
-- `create` set.
function slab(props: SlabProps): Frame
	const frame = vide.create "Frame" {
		Name = "Slab",
		BorderSizePixel = 0,
		BackgroundColor3 = COLORS.PANEL_BG,
		BackgroundTransparency = STYLE.BG_TRANSPARENCY,

		stroke(),
	}
	vide.apply(frame)(props)
	return frame
end

export type RuleProps = {
	Size: Usable<UDim2>?,
	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	Visible: Usable<boolean>?,
	ZIndex: number?,
	LayoutOrder: number?,
}

-- A horizontal divider, one hairline tall by default. Fainter than a border
-- (`STYLE.RULE_SOFT`) so a divider inside a panel reads as structure within the
-- panel rather than as the edge of another one.
function rule(props: RuleProps?): Frame
	const p = props or {}
	return vide.create "Frame" {
		Name = "Rule",
		Size = p.Size or function(): UDim2
			return UDim2.new(1, 0, 0, hairline(STYLE.WINDOW_RULE)())
		end,
		Position = p.Position,
		AnchorPoint = p.AnchorPoint,
		BorderSizePixel = 0,
		BackgroundColor3 = COLORS.OUTLINE,
		BackgroundTransparency = STYLE.RULE_SOFT,
		Visible = p.Visible,
		ZIndex = p.ZIndex,
		LayoutOrder = p.LayoutOrder,
	}
end

-- ONE RenderStepped connection for every eased value in the kit, and one slow
-- one for the blink. Per-widget connections are the usual shape and they are
-- what turns a busy screen into a few hundred engine callbacks a frame.
const motion_step = render_step()
const blink_step = render_step(STYLE.BLINK_PERIOD)
const blink_value = vide.source(true)
local blink_users = 0
local stop_blink: (() -> ())? = nil

-- Follow `target` smoothly instead of jumping to it: frame-rate independent
-- exponential approach (see `util/numbers/approach`), where `rate` is how
-- sharply it converges.
--
-- THE SETTLE IS LOAD-BEARING. Exponential approach never actually arrives, so
-- without `STYLE.SETTLED` every eased value in the kit would hold its
-- per-frame connection for the lifetime of the screen -- a closed panel would
-- go on costing a callback a frame forever. Reaching the threshold snaps to
-- the target and DISCONNECTS; the next change of `target` starts a new one.
function eased(target: () -> number, rate: number): () -> number
	const value = vide.source(target())
	vide.effect(function()
		const goal = target()
		-- Untracked: this effect WRITES `value`, and reading it normally would
		-- make the effect depend on its own output and re-run forever.
		const current = vide.untrack(value)
		if math.abs(goal - current) <= STYLE.SETTLED then
			value(goal)
			return
		end
		local stop: (() -> ())? = nil
		stop = motion_step:connect(function(dt: number)
			const next_value = approach.number(value(), goal, rate, dt)
			if math.abs(goal - next_value) <= STYLE.SETTLED then
				value(goal)
				if stop then
					stop()
					stop = nil
				end
			else
				value(next_value)
			end
		end)
		-- Runs when `target` changes as well as when the scope is destroyed, so
		-- a new goal never leaves the previous frame loop running.
		vide.cleanup(function()
			if stop then
				stop()
				stop = nil
			end
		end)
	end)
	return value
end

-- A cursor blink shared by every caller, refcounted so the timer only ticks
-- while something is drawing it. Shared rather than per-widget so that two
-- blinking cursors on screen blink TOGETHER: independent timers started at
-- different moments read as a glitch.
function blink(): () -> boolean
	blink_users += 1
	if stop_blink == nil then
		stop_blink = blink_step:connect(function()
			blink_value(not blink_value())
		end)
	end
	vide.cleanup(function()
		blink_users -= 1
		if blink_users == 0 and stop_blink then
			stop_blink()
			stop_blink = nil
		end
	end)
	return blink_value
end

return table.freeze {
	COLORS = COLORS,
	FONTS = FONTS,
	STYLE = STYLE,
	METRICS = METRICS,

	peek = peek,
	is_enabled = is_enabled,
	hairline = hairline,
	stroke = stroke,
	text_outline = text_outline,
	slab = slab,
	rule = rule,
	eased = eased,
	blink = blink,
}
