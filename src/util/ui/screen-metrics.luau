const GuiService = game:GetService "GuiService"
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)
const render_step = require(ReplicatedStorage.Util.events["render-step"])

-- The insets and measurements of the screen the UI is drawn on: the gui inset
-- (the topbar, and on a phone the device safe zone: notch, rounded corners,
-- home indicator), the viewport, the mobile touch controls, and the
-- accessibility preferences that change how UI should draw.
--
--   const metrics = require(ReplicatedStorage.Util.ui["screen-metrics"])
--   print(metrics.measure())                 -- Command Bar: one table, all numbers
--   metrics.topbar_height()                  -- inside vide: re-runs when it changes
--   vide.create "Frame" { metrics.ui_padding() }   -- pad a full-screen frame clear of all of it
--
-- WHY THIS EXISTS. The template's screens set `IgnoreGuiInset = true`, so the
-- engine stops offsetting them below the topbar and stops keeping them out of
-- a notch; that is the point (a backdrop that reaches the real top of the
-- screen) but it means every element that must NOT sit under the topbar has to
-- be moved by hand. The number it has to move by is not a constant. The topbar
-- has changed height twice in the engine's life, it is a different height on
-- phones, the safe zone is zero on desktop and 40-odd pixels on a notched
-- phone, and the thumbstick on touch covers a region the engine reports
-- nowhere. Every one of those has been hard-coded in a game at some point and
-- every one of those hard-codes was wrong within a year.
--
-- SO: READ THE ENGINE, EVERY TIME. The readers below call the engine
-- SYNCHRONOUSLY rather than caching into a source. That is what makes
-- `measure()` work from the Command Bar with no reactive scope, and it removes
-- a whole class of bug: a cached value is only as fresh as the signal that
-- refreshes it, and the first read after boot would return the cache's default
-- for a frame. The one reactive piece is `version`, a source bumped by the
-- change signals; a reader inside a vide scope touches it and so re-runs when
-- anything here changes. Connecting the signals is deferred to the first read
-- (`ensure`) so that requiring this module in a Lune spec costs nothing and
-- touches no engine API.
--
-- The exception is the touch-control clearance, which has no change signal to
-- listen to: the thumbstick moves when the dynamic thumbstick re-anchors, and
-- the only way to know is to look. It is polled, at TOUCH_POLL, and only once
-- something has asked for it.

export type Sides = { top: number, bottom: number, left: number, right: number }

export type Snapshot = {
	viewport: Vector2,
	gui_inset_top_left: Vector2,
	gui_inset_bottom_right: Vector2,
	topbar_height: number,
	touch_controls: number,
	padding: Sides,
	preferred_transparency: number,
	reduced_motion: boolean,
	touch_enabled: boolean,
}

-- Seconds between looks at the touch controls. The thumbstick only moves when
-- a finger goes down or the screen rotates, so ten looks a second is plenty
-- and a HUD that follows it never visibly lags; every frame would be sixty
-- FindFirstChild walks a second for a number that changes twice a session.
const TOUCH_POLL = 0.1

-- The CoreGui names of the touch controls, in the order the engine has used
-- them. `DynamicThumbstickFrame` is the current default; `ThumbstickFrame` is
-- the classic stick a place can still opt into; the jump button is separate
-- and can sit higher than either. Any that exist count.
const TOUCH_CONTROL_NAMES = { "DynamicThumbstickFrame", "ThumbstickFrame", "JumpButton" }

-- Bumped by every change signal. Reading it inside a vide scope is what
-- subscribes the scope; the value itself means nothing.
const version = vide.source(0)
local hooked = false

-- Written from the poll, outside the graph. Pixels from the BOTTOM of the
-- viewport up to the highest touch control, so a HUD element anchored at the
-- bottom knows how far up it has to start.
const touch_clearance = vide.source(0)
local touch_polling = false

local function bump()
	version(version() + 1)
end

local function ensure()
	if hooked then
		return
	end
	hooked = true
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(bump)
	GuiService:GetPropertyChangedSignal("PreferredTransparency"):Connect(bump)
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(bump)
	-- CurrentCamera is replaced on respawn, so the viewport listener has to
	-- follow it (the same shape as `hooks/px`).
	local viewport_connection: RBXScriptConnection? = nil
	local function hook_camera()
		if viewport_connection then
			viewport_connection:Disconnect()
			viewport_connection = nil
		end
		const camera = workspace.CurrentCamera
		if camera then
			viewport_connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(bump)
		end
		bump()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook_camera)
	hook_camera()
end

local function viewport(): Vector2
	ensure()
	version()
	const camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.zero
end

-- Both corners of the inset the engine applies to a ScreenGui that does NOT
-- ignore it. This IS the device safe zone as well as the topbar: on a notched
-- phone the engine folds the notch and the rounded corners into the top-left
-- corner and the home indicator into the bottom-right, so there is nothing
-- separate to ask for (the call that used to report the safe zone on its own,
-- `GetSafeZoneOffsets`, is deprecated, and this is its replacement).
local function gui_inset(): (Vector2, Vector2)
	ensure()
	version()
	return GuiService:GetGuiInset()
end

local function topbar_height(): number
	const top_left = gui_inset()
	return top_left.Y
end

local function measure_touch_controls(): number
	if not UserInputService.TouchEnabled then
		return 0
	end
	const camera = workspace.CurrentCamera
	const gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass "PlayerGui"
	const touch_gui = gui and gui:FindFirstChild "TouchGui"
	if not camera or not touch_gui then
		return 0
	end
	const bottom = camera.ViewportSize.Y
	local highest = bottom
	for _, name in TOUCH_CONTROL_NAMES do
		const control = touch_gui:FindFirstChild(name, true)
		if control and control:IsA "GuiObject" and control.Visible and control.AbsoluteSize.Y > 0 then
			highest = math.min(highest, control.AbsolutePosition.Y)
		end
	end
	return math.max(0, bottom - highest)
end

local function ensure_touch_poll()
	if touch_polling then
		return
	end
	touch_polling = true
	if not UserInputService.TouchEnabled then
		-- A desktop session never grows a thumbstick, so there is nothing to
		-- poll for. The source stays at its zero default.
		return
	end
	render_step(TOUCH_POLL):connect(function()
		const clearance = measure_touch_controls()
		if clearance ~= touch_clearance() then
			touch_clearance(clearance)
		end
	end)
end

local function touch_controls(): number
	ensure_touch_poll()
	return touch_clearance()
end

-- The one number a full-screen, inset-ignoring frame actually wants per side:
-- how far in from that edge content has to start to be clear of the topbar,
-- the notch, the home indicator and the thumbstick.
--
-- MAX, NOT SUM. The gui inset's bottom already holds the home indicator on a
-- phone, and the thumbstick is an independent claim on the same edge: the
-- thumbstick is usually the higher of the two, but adding them would push
-- content up by both on a phone that only needs the larger. Every side is
-- also clamped at zero, because a control measured off the bottom of the
-- screen is a measurement error, not a request to pull content past the edge.
--
-- Pure, and exported, so a spec can pin it without an engine.
local function compose(gui_top_left: Vector2, gui_bottom_right: Vector2, touch: number): Sides
	return {
		top = math.max(gui_top_left.Y, 0),
		left = math.max(gui_top_left.X, 0),
		right = math.max(gui_bottom_right.X, 0),
		bottom = math.max(gui_bottom_right.Y, touch, 0),
	}
end

local function padding(): Sides
	const top_left, bottom_right = gui_inset()
	return compose(top_left, bottom_right, touch_controls())
end

-- A UIPadding that tracks `padding`. Drop it into a full-screen frame's
-- children and the frame's content stays clear of everything above.
local function ui_padding(extra: number?)
	const pad = extra or 0
	return vide.create "UIPadding" {
		PaddingTop = function()
			return UDim.new(0, padding().top + pad)
		end,
		PaddingBottom = function()
			return UDim.new(0, padding().bottom + pad)
		end,
		PaddingLeft = function()
			return UDim.new(0, padding().left + pad)
		end,
		PaddingRight = function()
			return UDim.new(0, padding().right + pad)
		end,
	}
end

-- 0 is the default; a player who has asked the OS or Roblox for less
-- transparency reports up to 1, and a UI that draws a translucent panel should
-- blend its BackgroundTransparency toward 0 by this amount.
local function preferred_transparency(): number
	ensure()
	version()
	return GuiService.PreferredTransparency
end

-- True when the player has asked for reduced motion. Tweens and springs that
-- are purely decorative should skip to their end state.
local function reduced_motion(): boolean
	ensure()
	version()
	return GuiService.ReducedMotionEnabled
end

-- Everything above, once, as a plain table: for `print` in the Command Bar and
-- for code that wants a number now rather than a reactive one. The touch
-- clearance is measured directly here rather than read from the poll, so the
-- first call reports the truth instead of the source's default.
local function measure(): Snapshot
	const top_left, bottom_right = gui_inset()
	const touch = measure_touch_controls()
	return {
		viewport = viewport(),
		gui_inset_top_left = top_left,
		gui_inset_bottom_right = bottom_right,
		topbar_height = top_left.Y,
		touch_controls = touch,
		padding = compose(top_left, bottom_right, touch),
		preferred_transparency = preferred_transparency(),
		reduced_motion = reduced_motion(),
		touch_enabled = UserInputService.TouchEnabled,
	}
end

return table.freeze {
	viewport = viewport,
	gui_inset = gui_inset,
	topbar_height = topbar_height,
	touch_controls = touch_controls,
	padding = padding,
	ui_padding = ui_padding,
	preferred_transparency = preferred_transparency,
	reduced_motion = reduced_motion,
	measure = measure,
	compose = compose,
}
