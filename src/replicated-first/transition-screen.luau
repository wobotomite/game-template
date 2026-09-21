const ReplicatedFirst = game:GetService "ReplicatedFirst"
const RunService = game:GetService "RunService"
const TweenService = game:GetService "TweenService"

-- A full-screen cover with a title and a progress bar, built from nothing.
--
--   const transition = require(ReplicatedFirst["transition-screen"])
--   const screen = transition.create("LoadingCover", "Loading")
--   screen.gui.Parent = player_gui
--   screen.set("Loading the world", 0.4)  -- or omit the fraction for a pulse
--   screen.fade(false)                    -- then screen.destroy()
--
-- NO PACKAGES, NO WIDGET KIT, NO VIDE. This runs in ReplicatedFirst, which is
-- replicated and started BEFORE ReplicatedStorage has arrived: at the moment
-- this draws, `ReplicatedStorage.Packages` may not exist and neither may the
-- widget kit. Every Instance here is made by hand for that reason. The cost is
-- that a restyle of the game does not restyle the cover, which is the right
-- trade for the one screen that has to work when nothing else has loaded.
--
-- WHY IT READS DATA THROUGH AN ALIAS. `default.project.json` mounts
-- `src/shared/settings.luau` and `src/shared/assets.luau` a SECOND time, into
-- ReplicatedFirst as `TransitionSettings` and `TransitionAssets`, so the cover
-- has its numbers without waiting on ReplicatedStorage.
--
-- THAT MAKES TWO MODULESCRIPTS OF THE SAME FILE, and they are not the same
-- object. Requiring `ReplicatedFirst.TransitionSettings` and requiring
-- `ReplicatedStorage.Shared.settings` gives two tables with equal values and
-- different identities. So:
--
--   * never compare a value from one against a value from the other by
--     identity -- `TRANSITION.GROUND == UI.GROUND` is false for two Color3s
--     only if they differ, but two TABLES read from the two copies are never
--     equal, so a `settings.transition == other.transition` test is always
--     false and an `if section == THE_SECTION` branch silently never runs;
--   * never write into one expecting the other to see it. Both are frozen, so
--     this raises rather than diverging quietly -- which is the point of
--     freezing them.
--
-- Nothing in this file does either. It reads numbers and strings out and
-- builds Instances with them, which is the only safe shape for a file that is
-- mounted twice.
const TRANSITION = require(ReplicatedFirst.TransitionSettings).transition
const FONTS = require(ReplicatedFirst.TransitionAssets).fonts

-- THE FONT IS OPTIONAL, ON PURPOSE. `assets.fonts` belongs to the widget kit
-- and is empty in a fresh template, so the cover asks for a heading face and
-- takes the engine default when there is not one. Checked by `typeof` rather
-- than by nil, because this is the first script in the game to run: if a game
-- puts an id string where a Font value goes, the cover must still come up. A
-- cover that throws is a black screen with no way to tell it from a hang.
const HEADING: Font? = if typeof(FONTS.HEADING) == "Font" then FONTS.HEADING else nil

export type Screen = {
	gui: ScreenGui,
	-- Set the title, and optionally a 0..1 progress fraction. Called with no
	-- fraction, the bar goes back to its indeterminate sweep.
	set: (title: string, fraction: number?) -> (),
	-- Fade the whole cover in or out. `seconds` overrides `FADE_SECONDS`; zero
	-- snaps.
	fade: (visible: boolean, seconds: number?) -> (),
	destroy: () -> (),
}

function create(name: string, heading: string): Screen
	const gui = Instance.new "ScreenGui"
	gui.Name = name
	-- RESPAWNING MUST NOT TAKE THE COVER DOWN. A ScreenGui in PlayerGui is
	-- destroyed and rebuilt on every spawn by default, and the boot is waiting
	-- for exactly that spawn -- so the cover would vanish at the one moment it
	-- is still needed.
	gui.ResetOnSpawn = false
	-- FOUR SEPARATE WAYS TO NOT COVER THE SCREEN, and all four have to be off.
	-- The topbar inset, the device safe area, the safe-area compatibility
	-- shim and safe-area clipping each carve a strip off a full-size GuiObject
	-- independently; leaving any one of them on leaves a band of the loading
	-- game visible at an edge, usually only on the hardware you do not have.
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ClipToDeviceSafeArea = false
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.DisplayOrder = TRANSITION.DISPLAY_ORDER
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- A CANVASGROUP, NOT A FRAME, so the whole cover fades as one image through
	-- `GroupTransparency`. Fading a Frame means tweening the transparency of
	-- every descendant separately, and they cross-fade against each other on
	-- the way out -- the text ghosts through the backdrop as both approach
	-- transparent, which reads as a rendering fault rather than a transition.
	const ground = Instance.new "CanvasGroup"
	ground.Name = "Ground"
	ground.Size = UDim2.fromScale(1, 1)
	ground.BackgroundColor3 = TRANSITION.GROUND
	ground.BorderSizePixel = 0
	-- SWALLOW INPUT while the cover is up. The player's character may already
	-- exist behind it and the default controls are already listening, so
	-- without this a click aimed at nothing moves a body nobody can see.
	ground.Active = true
	ground.InputSink = Enum.InputSink.All
	ground.Parent = gui

	const content = Instance.new "Frame"
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(TRANSITION.WIDTH, TRANSITION.HEIGHT)
	content.BackgroundTransparency = 1
	content.Parent = ground

	const scale = Instance.new "UIScale"
	scale.Parent = content

	-- Fit the authored block into the viewport: shrink to whichever axis is
	-- tighter, never grow past 1 (a 620px block blown up on a 4K monitor is a
	-- title card, not a loading screen), never shrink past MIN_SCALE.
	--
	-- Driven off AbsoluteSize rather than the camera, because this runs before
	-- there is reliably a camera and the ground is already the full screen.
	const function resize()
		const size = ground.AbsoluteSize
		scale.Scale = math.clamp(
			math.min(
				(size.X - TRANSITION.VIEW_MARGIN) / TRANSITION.WIDTH,
				(size.Y - TRANSITION.VIEW_MARGIN) / TRANSITION.HEIGHT
			),
			TRANSITION.MIN_SCALE,
			1
		)
	end
	const size_connection = ground:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()

	const title = Instance.new "TextLabel"
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, TRANSITION.TITLE_SIZE + TRANSITION.RULE_GAP)
	title.Position = UDim2.fromOffset(0, TRANSITION.TITLE_Y)
	title.BackgroundTransparency = 1
	title.Text = heading
	title.TextSize = TRANSITION.TITLE_SIZE
	title.TextColor3 = TRANSITION.INK
	title.TextWrapped = true
	title.Parent = content
	if HEADING then
		title.FontFace = HEADING
	end

	-- CLIPPING IS WHAT MAKES THE SWEEP WORK. The fill is positioned from
	-- -SIGNAL_WIDTH to 1, so it slides in from off the left edge and out past
	-- the right; without ClipsDescendants both overhangs are drawn and the bar
	-- looks like a block twitching at the ends.
	const track = Instance.new "Frame"
	track.Name = "Progress"
	track.Size = UDim2.new(1, 0, 0, TRANSITION.BAR_HEIGHT)
	track.Position = UDim2.fromOffset(0, TRANSITION.BAR_Y)
	track.BackgroundColor3 = TRANSITION.TRACK
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = content

	const fill = Instance.new "Frame"
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(TRANSITION.SIGNAL_WIDTH, 1)
	fill.Position = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = TRANSITION.ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = track

	local determinate = false
	local tween: Tween? = nil

	-- The sweep is driven from the clock rather than accumulated per frame, so
	-- it runs at the same speed through the frame drops that a loading screen
	-- exists to sit in front of. `% 1` makes it a loop with no wrap logic.
	const started = os.clock()
	const animate = RunService.RenderStepped:Connect(function()
		if determinate or not gui.Enabled then
			return
		end
		const phase = (os.clock() - started) / TRANSITION.PULSE_SECONDS % 1
		fill.Position = UDim2.fromScale(phase * (1 + TRANSITION.SIGNAL_WIDTH) - TRANSITION.SIGNAL_WIDTH, 0)
	end)

	-- CLEANED UP FROM `Destroying`, not from `destroy()`, because this gui is
	-- parented to PlayerGui and anything can destroy it -- a failsafe timer, a
	-- respawn, a game that clears PlayerGui on teleport. A RenderStepped
	-- connection that outlives its Instances runs every frame for the rest of
	-- the session, writing to a destroyed Frame.
	gui.Destroying:Once(function()
		animate:Disconnect()
		size_connection:Disconnect()
		if tween then
			tween:Cancel()
		end
	end)

	return {
		gui = gui,
		set = function(title_text: string, fraction: number?)
			title.Text = title_text
			determinate = fraction ~= nil
			if fraction then
				fill.Position = UDim2.fromScale(0, 0)
				fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			else
				fill.Size = UDim2.fromScale(TRANSITION.SIGNAL_WIDTH, 1)
			end
		end,
		fade = function(visible: boolean, seconds: number?)
			-- CANCEL THE ONE IN FLIGHT FIRST. Two overlapping tweens on the same
			-- property do not blend; the older one keeps writing until it ends,
			-- so a fade out started during a fade in finishes and is then
			-- overwritten back to visible.
			if tween then
				tween:Cancel()
			end
			const duration = seconds or TRANSITION.FADE_SECONDS
			if duration <= 0 then
				ground.GroupTransparency = if visible then 0 else 1
				return
			end
			const motion = TweenService:Create(ground, TweenInfo.new(duration), {
				GroupTransparency = if visible then 0 else 1,
			})
			tween = motion
			motion:Play()
		end,
		destroy = function()
			gui:Destroy()
		end,
	}
end

return table.freeze { create = create }
