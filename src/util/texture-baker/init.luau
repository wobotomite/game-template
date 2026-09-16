--!strict
-- texture-baker: tinted, highlighted variants of a SurfaceAppearance, baked
-- into EditableImages at runtime.
--
--   local baker = require(ReplicatedStorage.Util["texture-baker"])
--
--   local factory = baker.create(
--       hull_appearance,                                   -- the source maps
--       { "rbxassetid://111", "rbxassetid://222" },        -- highlight masks
--       { "color_map", "emission_map" }                    -- what each mask paints
--   )
--   local variant = factory:generate(team_color, team_glow)
--   variant.surface_appearance.Parent = hull_mesh
--   ...
--   variant:destroy()
--
-- One factory reads its images ONCE -- the source colour map, the source
-- emissive mask if there is one, and every highlight mask -- and keeps them as
-- pixel buffers. Each `generate` then composes fresh canvases from those
-- buffers, writes them into new EditableImages, and hands back a new
-- SurfaceAppearance whose colour and emissive maps are those images and whose
-- every other map is the source's own. Reading is the expensive, yielding,
-- permission-gated part; composing is arithmetic.
--
-- ============================== the four colours ==========================
--
--   generate(c1, c2, c3, c4)
--
--   c1  highlight colour   tints the pixels that "color_map" masks cover
--   c2  highlight glow     tints the pixels that "emission_map" masks cover
--   c3  base tint          multiplied over the whole source colour map first
--   c4  glow tint          multiplied over the whole source emissive mask first
--
-- c1 and c2 default to HOT PINK so an unpainted highlight is impossible to
-- mistake for a finished one; c3 and c4 default to white, which leaves the
-- source maps as they are.
--
-- ============================== who wins a pixel ==========================
--
-- Masks are stamped LAST ENTRY FIRST, and a pixel one mask has claimed is
-- skipped by every mask after it. So the last mask in the array is the top
-- layer. A mask pixel counts when its alpha is above zero, and it is blended
-- by that alpha so soft edges stay soft (see ./compose for the ledger).
--
-- ============================== what this needs ===========================
--
-- AssetService:CreateEditableImageAsync only opens images the experience has
-- rights to: uploaded by the owner, or by the group, or Roblox-owned. Any
-- other id throws, and `create` re-throws it NAMING THE ID so the failure
-- points at the asset instead of at this file.
--
-- `create` and `generate` both yield (the image loads, and
-- CreateSurfaceAppearanceAsync). Call them from a thread that can.
--
-- EditableImages live in a per-client memory budget. A 1024x1024 canvas is
-- 4 MB, and every generate makes one or two. `Result:destroy()` gives them
-- back; a variant swapped out and forgotten does not.

local AssetService = game:GetService "AssetService"

local compose = require "@self/compose"
local tint = require "@self/tint"

export type MapKind = "color_map" | "emission_map"
export type Mode = tint.Mode

export type Options = {
	-- Blend mode for c3/c4 over the source maps. Default "multiply".
	tint_mode: Mode?,
	-- Blend mode for c1/c2 over a mask's own pixels. Default "multiply", so a
	-- white mask paints the highlight colour exactly and a grey one darkens it.
	highlight_mode: Mode?,
}

export type Result = {
	surface_appearance: SurfaceAppearance,
	color: EditableImage,
	-- Only when the factory has something emissive to paint: a source
	-- emissive mask, or at least one "emission_map" highlight.
	emission: EditableImage?,
	size: Vector2,
	destroy: (self: Result) -> (),
}

export type Factory = {
	size: Vector2,
	has_emission: boolean,
	generate: (self: Factory, c1: Color3?, c2: Color3?, c3: Color3?, c4: Color3?) -> Result,
}

local HOT_PINK = Color3.fromRGB(255, 105, 180) -- the "you forgot to pass a colour" colour
local WHITE = Color3.new(1, 1, 1)
local ORIGIN = Vector2.new(0, 0)

-- A source SurfaceAppearance with emission left at the engine default of 0
-- would make every emission highlight invisible, which reads as the baker
-- having done nothing. 1 is the engine's own "on" value.
local DEFAULT_EMISSIVE_STRENGTH = 1

local KINDS: { [string]: boolean } = { color_map = true, emission_map = true }

-- The map properties that are copied through from the source untouched.
local PASSTHROUGH_MAPS = { "NormalMap", "MetalnessMap", "RoughnessMap" }

local function is_white(color: Color3): boolean
	return color.R == 1 and color.G == 1 and color.B == 1
end

-- A SurfaceAppearance carries each map twice: as a ContentId string and as a
-- Content. The Content is the one that can point at an EditableImage (a
-- source that was itself baked), so it is preferred; the string is the
-- fallback for an appearance authored in Studio.
local function map_content(sa: SurfaceAppearance, name: string): Content?
	local content = (sa :: any)[name .. "Content"] :: Content?
	if content and (content.Uri ~= nil or content.Object ~= nil) then
		return content
	end
	local id = (sa :: any)[name] :: string?
	if id and id ~= "" then
		return Content.fromUri(id)
	end
	return nil
end

-- The pixels behind a Content, plus its size. A Content that already wraps an
-- EditableImage is read in place and left alone -- it belongs to whoever made
-- it. A uri is opened, read, and closed again immediately: the buffer is all
-- the factory keeps, and an open EditableImage would sit in the memory budget
-- for the factory's whole life.
local function read_pixels(content: Content, label: string): (buffer, number, number)
	local image = content.Object :: EditableImage?
	local owned = false
	if not image then
		local ok, opened = pcall(AssetService.CreateEditableImageAsync, AssetService, content)
		if not ok then
			error(
				`texture-baker: cannot read {label} "{tostring(content.Uri)}" -- {tostring(opened)}. `
					.. "Only images the experience owner has rights to can be opened as an EditableImage.",
				3
			)
		end
		image = opened
		owned = true
	end
	assert(image, "unreachable: no image after open")
	local size = image.Size
	local pixels = image:ReadPixelsBuffer(ORIGIN, size)
	if owned then
		image:Destroy()
	end
	return pixels, size.X, size.Y
end

local Factory = {}
Factory.__index = Factory

type FactoryState = {
	source: SurfaceAppearance,
	size: Vector2,
	width: number,
	height: number,
	has_emission: boolean,
	base_color: buffer,
	base_emission: buffer,
	color_maps: { buffer },
	emission_maps: { buffer },
	tint_mode: Mode,
	highlight_mode: Mode,
}

function Factory.generate(self: FactoryState, c1: Color3?, c2: Color3?, c3: Color3?, c4: Color3?): Result
	local highlight = c1 or HOT_PINK
	local glow = c2 or HOT_PINK
	local base_tint = c3 or WHITE
	local glow_tint = c4 or WHITE
	local width, height = self.width, self.height
	local size = self.size

	-- 1. the source maps, tinted
	local color = compose.clone(self.base_color)
	if not is_white(base_tint) then
		tint.apply(self.tint_mode, color, base_tint.R, base_tint.G, base_tint.B)
	end
	-- 2 + 3. a fresh ledger per canvas, highlights stamped last-first
	compose.highlights(
		color,
		compose.ledger(width, height),
		self.color_maps,
		highlight.R,
		highlight.G,
		highlight.B,
		self.highlight_mode
	)

	local emission: buffer? = nil
	if self.has_emission then
		local canvas = compose.clone(self.base_emission)
		if not is_white(glow_tint) then
			tint.apply(self.tint_mode, canvas, glow_tint.R, glow_tint.G, glow_tint.B)
		end
		compose.highlights(
			canvas,
			compose.ledger(width, height),
			self.emission_maps,
			glow.R,
			glow.G,
			glow.B,
			self.highlight_mode
		)
		emission = canvas
	end

	-- 4 + 5. into images, then into Content
	local color_image = AssetService:CreateEditableImage { Size = size }
	color_image:WritePixelsBuffer(ORIGIN, size, color)

	-- 6. the appearance: our colour map, the source's other maps
	local maps: { [string]: Content } = { ColorMap = Content.fromObject(color_image) }
	for _, name in PASSTHROUGH_MAPS do
		local content = map_content(self.source, name)
		if content then
			maps[name] = content
		end
	end
	local source = self.source
	local appearance = AssetService:CreateSurfaceAppearanceAsync(maps)
	appearance.AlphaMode = source.AlphaMode
	appearance.Color = source.Color

	-- The emissive mask is not one of CreateSurfaceAppearanceAsync's documented
	-- keys, so it goes on as a property afterwards, where the type is plain
	-- Content and an EditableImage-backed one is accepted like any other.
	local emission_image: EditableImage? = nil
	if emission then
		local image = AssetService:CreateEditableImage { Size = size }
		image:WritePixelsBuffer(ORIGIN, size, emission)
		appearance.EmissiveMaskContent = Content.fromObject(image)
		appearance.EmissiveTint = source.EmissiveTint
		appearance.EmissiveStrength = if source.EmissiveStrength > 0
			then source.EmissiveStrength
			else DEFAULT_EMISSIVE_STRENGTH
		emission_image = image
	end

	local result: Result = {
		surface_appearance = appearance,
		color = color_image,
		emission = emission_image,
		size = size,
		destroy = function(this: Result)
			this.surface_appearance:Destroy()
			this.color:Destroy()
			if this.emission then
				this.emission:Destroy()
			end
		end,
	}
	return result
end

local baker = {}

baker.tint = tint.apply
baker.compose = compose
baker.HOT_PINK = HOT_PINK

-- Reads every image now (yields), returns a factory that never reads again.
--
-- `ids` and `kinds` are parallel arrays: `ids[i]` is a highlight mask and
-- `kinds[i]` says which canvas it paints. Masks are resampled to the colour
-- map's size (nearest-neighbour) when they differ.
function baker.create(source: SurfaceAppearance, ids: { string }, kinds: { MapKind }, options: Options?): Factory
	if #ids ~= #kinds then
		error(`texture-baker: {#ids} map ids but {#kinds} map kinds -- the arrays are parallel`, 2)
	end
	for index, kind in kinds do
		if not KINDS[kind] then
			error(`texture-baker: unknown map kind "{tostring(kind)}" at index {index} (color_map | emission_map)`, 2)
		end
	end
	local opts: Options = options or {}

	local color_content = map_content(source, "ColorMap")
	if not color_content then
		error("texture-baker: the source SurfaceAppearance has no ColorMap to bake from", 2)
	end
	local base_color, width, height = read_pixels(color_content, "the ColorMap")

	local emissive_content = map_content(source, "EmissiveMask")
	local base_emission: buffer
	if emissive_content then
		local pixels, ew, eh = read_pixels(emissive_content, "the EmissiveMask")
		base_emission = compose.resample(pixels, ew, eh, width, height)
	else
		-- Opaque black: a mask that glows nowhere, ready for highlights.
		base_emission = compose.blank(width, height, 0, 0, 0, 255)
	end

	local color_maps: { buffer } = {}
	local emission_maps: { buffer } = {}
	for index, id in ids do
		local pixels, mw, mh = read_pixels(Content.fromUri(id), `highlight map {index}`)
		local fitted = compose.resample(pixels, mw, mh, width, height)
		table.insert(if kinds[index] == "color_map" then color_maps else emission_maps, fitted)
	end

	local state: FactoryState = {
		source = source,
		size = Vector2.new(width, height),
		width = width,
		height = height,
		has_emission = emissive_content ~= nil or #emission_maps > 0,
		base_color = base_color,
		base_emission = base_emission,
		color_maps = color_maps,
		emission_maps = emission_maps,
		tint_mode = opts.tint_mode or "multiply",
		highlight_mode = opts.highlight_mode or "multiply",
	}
	return setmetatable(state, Factory) :: any
end

return baker
