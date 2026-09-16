--!strict
-- Pixel-buffer compositing for the baker: the pure half, no engine in it.
--
-- Everything here works on RGBA8 buffers of `width * height * 4` bytes, the
-- layout EditableImage:ReadPixelsBuffer hands back and WritePixelsBuffer
-- expects. Row-major, top-left first, four bytes per pixel. The engine layer
-- in ./init reads and writes those buffers; this file never sees an Instance,
-- which is what lets it run under plain Lune.

local tint = require "./tint"

local compose = {}

-- A canvas of one solid RGBA, default transparent black.
function compose.blank(width: number, height: number, r: number?, g: number?, b: number?, a: number?): buffer
	local pixels = buffer.create(width * height * 4)
	local fr, fg, fb, fa = r or 0, g or 0, b or 0, a or 0
	if fr ~= 0 or fg ~= 0 or fb ~= 0 or fa ~= 0 then
		-- One u32 write per pixel: the four channels packed little-endian,
		-- which is the byte order a per-channel writeu8 would produce.
		local packed = fr + fg * 256 + fb * 65536 + fa * 16777216
		for i = 0, width * height - 1 do
			buffer.writeu32(pixels, i * 4, packed)
		end
	end
	return pixels
end

function compose.clone(pixels: buffer): buffer
	local copy = buffer.create(buffer.len(pixels))
	buffer.copy(copy, 0, pixels)
	return copy
end

-- One byte per pixel, all zero: the "already written" ledger a highlight pass
-- consults. Kept apart from the canvas so a second pass over a DIFFERENT
-- canvas of the same size can start its own ledger.
function compose.ledger(width: number, height: number): buffer
	return buffer.create(width * height)
end

-- Nearest-neighbour resize. Returns the SAME buffer when the sizes already
-- match, so callers can resample unconditionally without paying for a copy.
--
-- Nearest rather than bilinear on purpose: a highlight mask is usually hard
-- edged, and bilinear would invent half-covered pixels along every edge that
-- the ledger then treats as written. A mask authored at half the colour map's
-- resolution comes out blocky, which is the honest result.
@native
function compose.resample(src: buffer, sw: number, sh: number, dw: number, dh: number): buffer
	if sw == dw and sh == dh then
		return src
	end
	local dst = buffer.create(dw * dh * 4)
	for y = 0, dh - 1 do
		local sy = (y * sh) // dh
		local src_row = sy * sw
		local dst_row = y * dw
		for x = 0, dw - 1 do
			local sx = (x * sw) // dw
			buffer.writeu32(dst, (dst_row + x) * 4, buffer.readu32(src, (src_row + sx) * 4))
		end
	end
	return dst
end

-- Stamp one highlight map onto `dst`.
--
-- A source pixel counts as part of the highlight when its alpha is above
-- zero. It is tinted through `mode` with the colour, then blended onto the
-- canvas BY ITS ALPHA -- so an anti-aliased mask edge stays soft -- and the
-- pixel is marked in the ledger either way. Pixels already in the ledger are
-- skipped, which is the whole rule behind the backwards iteration in
-- `highlights`: whoever wrote first keeps the pixel.
--
-- Returns how many pixels it wrote, which a spec can pin exactly.
@native
function compose.stamp(
	dst: buffer,
	ledger: buffer,
	src: buffer,
	r: number,
	g: number,
	b: number,
	mode: tint.Mode?
): number
	local lr, lg, lb = tint.luts(mode or "multiply", r, g, b)
	local count = buffer.len(ledger)
	local wrote = 0
	for i = 0, count - 1 do
		if buffer.readu8(ledger, i) ~= 0 then
			continue
		end
		local o = i * 4
		local a = buffer.readu8(src, o + 3)
		if a == 0 then
			continue
		end
		local sr = buffer.readu8(lr, buffer.readu8(src, o))
		local sg = buffer.readu8(lg, buffer.readu8(src, o + 1))
		local sb = buffer.readu8(lb, buffer.readu8(src, o + 2))
		if a == 255 then
			buffer.writeu8(dst, o, sr)
			buffer.writeu8(dst, o + 1, sg)
			buffer.writeu8(dst, o + 2, sb)
			buffer.writeu8(dst, o + 3, 255)
		else
			local t = a / 255
			local dr = buffer.readu8(dst, o)
			local dg = buffer.readu8(dst, o + 1)
			local db = buffer.readu8(dst, o + 2)
			local da = buffer.readu8(dst, o + 3)
			buffer.writeu8(dst, o, math.floor(dr + (sr - dr) * t + 0.5))
			buffer.writeu8(dst, o + 1, math.floor(dg + (sg - dg) * t + 0.5))
			buffer.writeu8(dst, o + 2, math.floor(db + (sb - db) * t + 0.5))
			buffer.writeu8(dst, o + 3, math.max(da, a))
		end
		buffer.writeu8(ledger, i, 1)
		wrote += 1
	end
	return wrote
end

-- Stamp every map in `maps` onto `dst`, LAST ENTRY FIRST. Combined with the
-- ledger that makes the last map in the array the top layer: it claims its
-- pixels before any earlier map gets a look at them. Returns the total pixel
-- count written across all maps.
function compose.highlights(
	dst: buffer,
	ledger: buffer,
	maps: { buffer },
	r: number,
	g: number,
	b: number,
	mode: tint.Mode?
): number
	local wrote = 0
	for index = #maps, 1, -1 do
		wrote += compose.stamp(dst, ledger, maps[index], r, g, b, mode)
	end
	return wrote
end

return compose
