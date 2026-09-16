--!strict
-- Colour blend modes over an RGBA8 pixel buffer, in place.
--
--   tint.apply("multiply", pixels, 1, 0.41, 0.71)   -- hot pink, the classic tint
--   tint.apply("darken", pixels, 0.2, 0.2, 0.2)
--   tint.apply("overlay", pixels, 0.9, 0.6, 0.1)
--
-- Every mode is a function of ONE input channel value and ONE colour channel
-- value, so for a fixed mode and colour the whole operation is three 256-entry
-- lookup tables. `lut` builds them; `apply` and the compositor in ./compose
-- both run their per-pixel loops as table reads. That is what keeps a
-- 1024x1024 bake at a few million buffer reads instead of a few million
-- function calls, and it means an exotic mode costs exactly what multiply
-- costs.
--
-- Alpha is never touched by a tint. Coverage is the compositor's business.

export type Mode = "multiply" | "darken" | "lighten" | "screen" | "overlay" | "add"

local tint = {}

-- One channel. `p` is the pixel's value 0-255, `c` the tint colour's channel
-- 0-1. Returns 0-255, rounded.
local function channel(mode: Mode, p: number, c: number): number
	local out: number
	if mode == "multiply" then
		out = p * c
	elseif mode == "darken" then
		out = math.min(p, c * 255)
	elseif mode == "lighten" then
		out = math.max(p, c * 255)
	elseif mode == "screen" then
		out = 255 - (255 - p) * (1 - c)
	elseif mode == "overlay" then
		-- Photoshop's overlay: multiply in the shadows, screen in the
		-- highlights, with the PIXEL deciding which half applies.
		if p < 128 then
			out = 2 * p * c
		else
			out = 255 - 2 * (255 - p) * (1 - c)
		end
	elseif mode == "add" then
		out = p + c * 255
	else
		error(`tint: unknown mode "{tostring(mode)}"`, 3)
	end
	return math.clamp(math.floor(out + 0.5), 0, 255)
end

-- A 256-byte buffer: entry `p` is the tinted value of channel value `p`.
function tint.lut(mode: Mode, c: number): buffer
	local lut = buffer.create(256)
	for p = 0, 255 do
		buffer.writeu8(lut, p, channel(mode, p, c))
	end
	return lut
end

-- The three tables for a colour, in one call, because every caller wants all
-- three at once.
function tint.luts(mode: Mode, r: number, g: number, b: number): (buffer, buffer, buffer)
	return tint.lut(mode, r), tint.lut(mode, g), tint.lut(mode, b)
end

-- Tint every pixel of `pixels` (RGBA8, `#pixels / 4` of them) in place.
@native
function tint.apply(mode: Mode, pixels: buffer, r: number, g: number, b: number)
	local lr, lg, lb = tint.luts(mode, r, g, b)
	local count = buffer.len(pixels) // 4
	for i = 0, count - 1 do
		local o = i * 4
		buffer.writeu8(pixels, o, buffer.readu8(lr, buffer.readu8(pixels, o)))
		buffer.writeu8(pixels, o + 1, buffer.readu8(lg, buffer.readu8(pixels, o + 1)))
		buffer.writeu8(pixels, o + 2, buffer.readu8(lb, buffer.readu8(pixels, o + 2)))
	end
end

tint.channel = channel

return tint
