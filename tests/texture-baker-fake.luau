--!nocheck
-- The slice of the engine the baker touches, as plain tables backed by real
-- buffers: AssetService, EditableImage, Content, and a SurfaceAppearance.
--
-- This is not an emulator. It records what the baker asked for so a spec can
-- pin it -- which images were opened, which were destroyed, what dictionary
-- went into CreateSurfaceAppearanceAsync -- and it answers pixel reads from
-- the buffers a spec registered under each uri.

local fs = require "@lune/fs"
local luau = require "@lune/luau"
local roblox = require "@lune/roblox"

local compose = require "../src/util/texture-baker/compose"
local tint = require "../src/util/texture-baker/tint"

local fake = {}

-- A new, independent engine. `registered[uri] = { width, height, pixels }`.
function fake.new()
	local engine = {
		registered = {},
		opened = {}, -- uris opened via CreateEditableImageAsync, in order
		images = {}, -- every EditableImage created, in order
		appearances = {}, -- every CreateSurfaceAppearanceAsync result
	}

	local function new_image(width: number, height: number, pixels: buffer?)
		local image = {
			Size = roblox.Vector2.new(width, height),
			pixels = pixels or buffer.create(width * height * 4),
			destroyed = false,
		}
		function image.ReadPixelsBuffer(self, position, size)
			assert(position.X == 0 and position.Y == 0, "fake reads whole images only")
			assert(size.X == width and size.Y == height, "fake reads whole images only")
			return compose.clone(self.pixels)
		end
		function image.WritePixelsBuffer(self, position, size, data)
			assert(position.X == 0 and position.Y == 0, "fake writes whole images only")
			assert(size.X == width and size.Y == height, "fake writes whole images only")
			assert(buffer.len(data) == width * height * 4, "buffer size does not match the image")
			self.pixels = compose.clone(data)
		end
		function image.Destroy(self)
			self.destroyed = true
		end
		table.insert(engine.images, image)
		return image
	end
	engine.new_image = new_image

	engine.AssetService = {
		CreateEditableImageAsync = function(_, content)
			local entry = engine.registered[content.Uri]
			if not entry then
				error(`Asset {content.Uri} is not permitted`)
			end
			table.insert(engine.opened, content.Uri)
			return new_image(entry.width, entry.height, compose.clone(entry.pixels))
		end,
		CreateEditableImage = function(_, options)
			return new_image(options.Size.X, options.Size.Y)
		end,
		CreateSurfaceAppearanceAsync = function(_, maps)
			local appearance = fake.surface_appearance {}
			appearance.maps = maps
			table.insert(engine.appearances, appearance)
			return appearance
		end,
	}

	engine.game = {
		GetService = function(_, name)
			assert(name == "AssetService", `fake engine has no {name}`)
			return engine.AssetService
		end,
	}

	engine.Content = {
		none = {},
		fromUri = function(uri)
			return { Uri = uri }
		end,
		fromObject = function(object)
			return { Object = object }
		end,
	}

	function engine.register(uri: string, width: number, height: number, pixels: buffer)
		engine.registered[uri] = { width = width, height = height, pixels = pixels }
	end

	return engine
end

-- A SurfaceAppearance as the baker sees it: map ids, their Content twins,
-- and the scalar properties it copies across.
function fake.surface_appearance(props)
	local sa = {
		ColorMap = "",
		NormalMap = "",
		MetalnessMap = "",
		RoughnessMap = "",
		AlphaMode = "Overlay",
		Color = roblox.Color3.new(1, 1, 1),
		EmissiveStrength = 0,
		EmissiveTint = roblox.Color3.new(1, 1, 1),
		EmissiveMaskContent = {},
		destroyed = false,
	}
	for key, value in props do
		sa[key] = value
	end
	for _, name in { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" } do
		sa[name .. "Content"] = if sa[name] ~= "" then { Uri = sa[name] } else {}
	end
	function sa.Destroy(self)
		self.destroyed = true
	end
	return sa
end

-- util/texture-baker's entry module, loaded against a fake engine. Run from
-- the repo root.
function fake.load_baker(engine)
	local source = fs.readFile "src/util/texture-baker/init.luau"
	local chunk = luau.load(luau.compile(source), {
		debugName = "src/util/texture-baker/init.luau",
		injectGlobals = true,
		environment = {
			game = engine.game,
			Content = engine.Content,
			Vector2 = roblox.Vector2,
			Color3 = roblox.Color3,
			require = function(path)
				if path == "@self/compose" then
					return compose
				elseif path == "@self/tint" then
					return tint
				end
				error(`unexpected require "{path}"`)
			end,
		},
	})
	return chunk()
end

-- A width x height RGBA8 buffer from a painter `(x, y) -> r, g, b, a`.
function fake.paint(width: number, height: number, painter)
	local pixels = buffer.create(width * height * 4)
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local r, g, b, a = painter(x, y)
			local o = (y * width + x) * 4
			buffer.writeu8(pixels, o, r)
			buffer.writeu8(pixels, o + 1, g)
			buffer.writeu8(pixels, o + 2, b)
			buffer.writeu8(pixels, o + 3, a)
		end
	end
	return pixels
end

function fake.pixel(pixels: buffer, width: number, x: number, y: number): (number, number, number, number)
	local o = (y * width + x) * 4
	return buffer.readu8(pixels, o),
		buffer.readu8(pixels, o + 1),
		buffer.readu8(pixels, o + 2),
		buffer.readu8(pixels, o + 3)
end

return fake
