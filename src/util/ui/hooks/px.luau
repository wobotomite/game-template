const ReplicatedStorage = game:GetService "ReplicatedStorage"

const Vide = require(ReplicatedStorage.Packages.vide)

local cleanup = Vide.cleanup
local source = Vide.source

local BASE_RESOLUTION = Vector2.new(1280, 832)
local DOMINANT_AXIS = 0.2
local MIN_SCALE = 0.4
local SCALE_POINTS = { 0.3, 0.5, 0.6, 0.625, 0.65, 0.75, 1, 1.25, 1.5, 1.75, 2, 3 }

local currentScale = source(1)

--[[
	Apply additional modifications to the scale factor here if desired.
]]
local function modifyScale(scale: number): number
	if math.isnan(scale) then
		return MIN_SCALE
	end

	-- Downscale slower than upscale
	-- scale ^= 0.6

	-- -- Snap to predefined scale points
	-- for i, point in SCALE_POINTS do
	-- 	if scale <= point then
	-- 		return point
	-- 	end
	-- end

	-- return SCALE_POINTS[#SCALE_POINTS]
	return math.max(math.round(scale * 10) / 10, MIN_SCALE)
end

-- Computed outside the vide graph: setting `currentScale` inside a vide
-- effect is a recursive source update (vide 0.4 has no deferred effects).
local function recomputeScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local constrainedAspectRatio = math.min(viewport.X / viewport.Y, 16 / 9)
	local constrained = Vector2.new(viewport.Y * constrainedAspectRatio, viewport.Y)

	local scaleX = math.log(constrained.X / BASE_RESOLUTION.X, 2)
	local scaleY = math.log(constrained.Y / BASE_RESOLUTION.Y, 2)
	const centered = scaleX + (scaleY - scaleX) * DOMINANT_AXIS

	currentScale(modifyScale(math.max(2 ^ centered, MIN_SCALE)))
end

local function usePx()
	-- CurrentCamera is replaced on death/respawn; re-hook so viewport
	-- listening survives the swap instead of dying with the old camera.
	local viewportConnection: RBXScriptConnection? = nil
	local function hookCamera()
		if viewportConnection then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end
		const camera = workspace.CurrentCamera
		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(recomputeScale)
		end
		recomputeScale()
	end
	cleanup(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera))
	cleanup(function()
		if viewportConnection then
			viewportConnection:Disconnect()
		end
	end)
	task.defer(hookCamera)
end

-- MIN_SCALE is a floor on how small the UI is allowed to get, and the right
-- floor is not a property of the module -- it is a property of the LAYOUT. A
-- HUD of icons stays legible far further down than a panel of body text does,
-- so a place whose densest screen is text wants a higher floor and one that is
-- all icons wants a lower one. Exported rather than hard-coded so the game sets
-- it once at boot instead of this file being edited per project.
--
-- `recomputeScale` runs immediately because MIN_SCALE is read in two places
-- (the clamp in `recomputeScale` and the NaN fallback in `modifyScale`) and
-- neither is inside the vide graph: without this call the new floor would only
-- take effect on the next viewport change, which on a desktop session may be
-- never.
local function setMinimumScale(scale: number)
	MIN_SCALE = scale
	recomputeScale()
end

local function setScale(scale: number)
	currentScale(scale)
end

local function px(x: number): () -> number
	return function()
		return math.round(x * currentScale())
	end
end

local function raw(scaled: number): number
	return math.round(scaled / currentScale())
end

local function scale(x: number): () -> number
	return function()
		return x * currentScale()
	end
end

local function offset(x: number, y: number): () -> UDim2
	return function()
		return UDim2.fromOffset(px(x)(), px(y)())
	end
end

local function udim2(xScale: number, xOffset: number, yScale: number, yOffset: number): () -> UDim2
	return function()
		return UDim2.new(xScale, px(xOffset)(), yScale, px(yOffset)())
	end
end

local function udim(scale: number, offset: number): () -> UDim
	return function()
		return UDim.new(scale, px(offset)())
	end
end

return setmetatable({
	usePx = usePx,
	setScale = setScale,
	setMinimumScale = setMinimumScale,
	raw = raw,
	scale = scale,
	offset = offset,
	udim2 = udim2,
	udim = udim,
}, {
	__call = function(_, value: number): () -> number
		return px(value)
	end,
})
