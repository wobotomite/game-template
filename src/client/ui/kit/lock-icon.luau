-- A PADLOCK, drawn out of frames.
--
-- The kit's one icon that needs no upload. "Locked" is the state a template
-- shows before a game has any art at all -- an item not yet bought, a mode not
-- yet unlocked -- and an empty box there tells the player nothing. Every other
-- icon in the kit is an image id from `assets.icons` and ships unset.
--
-- WHY THE SHAPE IS IN THIS FILE and not in settings: it is a DRAWING, not a
-- tunable. Nobody adjusts a pixel of a padlock to taste, and a 25-row table of
-- rectangles in a data file is noise in the one place the game's real numbers
-- have to stay findable.
--
-- Each row is { x, y, width, height, shade } on a 32x32 grid, where shade is
-- 0 for the dark ink and 1 for the light. Two shades, so the lock reads as a
-- lock at 24 pixels rather than as a grey blob.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const vide = require(ReplicatedStorage.Packages.vide)
const ICON_SIZE = require(ReplicatedStorage.Shared.settings).ui.METRICS.ICON_NATIVE_SIZE

const SHAPE = {
	{ 11, 3, 10, 2, 0 },
	{ 9, 5, 2, 2, 0 },
	{ 11, 5, 10, 2, 1 },
	{ 21, 5, 2, 2, 0 },
	{ 7, 7, 2, 6, 0 },
	{ 9, 7, 4, 2, 1 },
	{ 13, 7, 6, 2, 0 },
	{ 19, 7, 4, 2, 1 },
	{ 23, 7, 2, 6, 0 },
	{ 9, 9, 2, 4, 1 },
	{ 11, 9, 2, 4, 0 },
	{ 19, 9, 2, 4, 0 },
	{ 21, 9, 2, 4, 1 },
	{ 5, 13, 22, 2, 0 },
	{ 5, 15, 2, 12, 0 },
	{ 7, 15, 18, 2, 1 },
	{ 25, 15, 2, 12, 0 },
	{ 7, 17, 6, 4, 1 },
	{ 13, 17, 6, 4, 0 },
	{ 19, 17, 6, 4, 1 },
	{ 7, 21, 8, 4, 1 },
	{ 15, 21, 2, 4, 0 },
	{ 17, 21, 8, 4, 1 },
	{ 7, 25, 18, 2, 1 },
	{ 7, 27, 18, 2, 0 },
}

-- `fill` stretches the lock to whatever box it is in; without it the lock snaps
-- to a whole multiple of the grid and centres itself in the space left over.
function lock_icon(props: { [any]: any }?, transparency: (() -> number)?, fill: boolean?): Frame
	const canvas = vide.create "Frame" {
		Name = "Pixels",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}
	for _, rect in SHAPE do
		vide.create "Frame" {
			Name = "Ink",
			Parent = canvas,
			-- Greyscale from the shade column, so the lock takes the colour of
			-- whatever it is drawn over rather than carrying its own.
			BackgroundColor3 = Color3.new(rect[5], rect[5], rect[5]),
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(rect[1] / ICON_SIZE, rect[2] / ICON_SIZE),
			Size = UDim2.fromScale(rect[3] / ICON_SIZE, rect[4] / ICON_SIZE),
		}
	end
	const frame = vide.create "Frame" {
		Name = "Lock",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		canvas,
	}
	-- SNAPPED TO A WHOLE MULTIPLE of the 32-pixel grid. A pixel drawing scaled
	-- by 2.5 puts half its rectangles on half-pixels, and the engine rounds
	-- each one independently -- so the padlock comes out with a two-pixel edge
	-- on one side and a one-pixel edge on the other. Rounding down to 2x and
	-- centring the result loses a little size and keeps the drawing.
	local function resize()
		const size = frame.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- Floor, never zero: on a box smaller than the grid the lock is drawn
		-- at 1:1 and overflows rather than vanishing.
		const unit = math.max(1, math.floor(math.min(size.X, size.Y) / ICON_SIZE))
		const extent = ICON_SIZE * unit
		const left = math.round((size.X - extent) / 2)
		const top = math.round((size.Y - extent) / 2)
		canvas.Position = UDim2.fromScale(left / size.X, top / size.Y)
		canvas.Size = UDim2.fromScale(extent / size.X, extent / size.Y)
	end
	if not fill then
		vide.cleanup(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	end
	if props then
		vide.apply(frame)(props)
	end
	-- After `apply`, because the caller's props are what give the frame its
	-- size: snapping before them would measure a frame that has not been sized
	-- yet.
	if not fill then
		resize()
	end
	return frame
end

return lock_icon
