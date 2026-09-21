-- AN ICON, by name, from `assets.icons`.
--
-- A name with no entry there resolves to the empty content string and draws
-- nothing, keeping its frame, its size and its place in the layout -- so the
-- kit renders and stays usable before any art has been uploaded.
--
-- PIXEL SNAPPING IS THE POINT OF THIS MODULE. The icons are small sprites, so
-- they are drawn `Pixelated` and at an INTEGER multiple of their native size,
-- centred in whatever box the layout gave them. A 32px sprite in an 80px box
-- draws at 64px with 8px of air on each side, rather than being resampled to
-- 2.5x and turning to mush. That is also why the size is computed from
-- `AbsoluteSize` rather than expressed as a scale: only the final pixels know
-- what multiple fits.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const assets = require(ReplicatedStorage.Shared.assets)
const ICON_SIZE = require(ReplicatedStorage.Shared.settings).ui.METRICS.ICON_NATIVE_SIZE

-- `fill` opts out of the snapping and lets the image stretch to the frame, for
-- art that is not on the sprite grid -- a photo, a gradient, a full-bleed
-- background.
function icon(
	name: string,
	props: { [any]: any }?,
	transparency: (() -> number)?,
	color: (Color3 | () -> Color3)?,
	fill: boolean?
): Frame
	const image = vide.create "ImageLabel" {
		Name = "Image",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Image = assets.icons[name] or "",
		-- White is NO TINT, not a theme colour: it multiplies, so it leaves a
		-- coloured sprite exactly as drawn. Callers that want a monochrome
		-- glyph in the palette pass a colour.
		ImageColor3 = color or Color3.new(1, 1, 1),
		ImageTransparency = transparency or 0,
		ResampleMode = Enum.ResamplerMode.Pixelated,
	}
	-- The outer frame is what the layout sizes and what the caller's props are
	-- applied to; the image inside it is what gets snapped.
	const frame = vide.create "Frame" {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		image,
	}
	const function resize()
		const size = frame.AbsoluteSize
		-- A frame that has not been laid out yet measures zero, and the floor
		-- below would give it a negative offset. It will be called again when
		-- the size arrives.
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- At least 1: a box SMALLER than the sprite still shows the whole
		-- sprite, overflowing a little, rather than disappearing.
		const unit = math.max(1, math.floor(math.min(size.X, size.Y) / ICON_SIZE))
		const extent = ICON_SIZE * unit
		const left = math.round((size.X - extent) / 2)
		const top = math.round((size.Y - extent) / 2)
		-- Written as scale because the parent's size is what these were
		-- measured from: an offset would fight the layout on the next resize.
		image.Position = UDim2.fromScale(left / size.X, top / size.Y)
		image.Size = UDim2.fromScale(extent / size.X, extent / size.Y)
	end
	if not fill then
		vide.cleanup(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize))
	end
	if props then
		vide.apply(frame)(props)
	end
	-- After `apply`, so a caller-supplied Size is already on the frame.
	if not fill then
		resize()
	end
	return frame
end

return icon
