local RunService = game:GetService "RunService"

-- Client-side, additive "ghosting" for a whole model: add(model, 1) fades it out,
-- add(model, -1) fades it back in. Stacks (e.g. two effects each adding 0.5).
--
-- Perf notes vs. a naive per-tick GetDescendants/GetConnectedParts implementation:
-- - the descendant list is collected once per model and only re-collected when the
--   model's hierarchy actually changes (DescendantAdded/Removing), not every frame
-- - only models still fading (current ~= target) do any work per frame; settled
--   models are a single attribute read + number compare
-- - a model is dropped from tracking entirely once it fades back to fully opaque,
--   so the tracked set can't grow unboundedly over a play session
-- - writes LocalTransparencyModifier, which is client-only and doesn't fight
--   whatever the server has `.Transparency` set to

local OMIT_TAG = "__transparency_omit"
local TARGET_ATTR = "__transparency_target"

local FADE_RATE = 5 -- transparency units per second
local SETTLE_EPSILON = 0.01

type Cache = {
	parts: { BasePart },
	decals: { Instance },
	effects: { Instance },
	current: number,
	dirty: boolean,
	release: () -> (),
}

local caches: { [Model]: Cache } = {}

local EFFECT_CLASSES = { "Beam", "Trail", "ParticleEmitter", "Fire", "Sparkles", "Smoke", "Explosion" }

local function is_effect(inst: Instance): boolean
	for _, class_name in EFFECT_CLASSES do
		if inst:IsA(class_name) then
			return true
		end
	end
	return false
end

local function collect(model: Model): ({ BasePart }, { Instance }, { Instance })
	local parts: { BasePart } = {}
	local decals: { Instance } = {}
	local effects: { Instance } = {}

	for _, inst in model:GetDescendants() do
		if inst:IsA "BasePart" then
			if not inst:HasTag(OMIT_TAG) then
				table.insert(parts, inst)
			end
		elseif inst:IsA "Decal" or inst:IsA "Texture" then
			table.insert(decals, inst)
		elseif is_effect(inst) then
			table.insert(effects, inst)
		end
	end

	return parts, decals, effects
end

local function get_cache(model: Model): Cache
	local cache = caches[model]
	if cache then
		return cache
	end

	local parts, decals, effects = collect(model)

	local mark_dirty = function()
		local c = caches[model]
		if c then
			c.dirty = true
		end
	end

	local descendant_added = model.DescendantAdded:Connect(mark_dirty)
	local descendant_removing = model.DescendantRemoving:Connect(mark_dirty)
	local destroying = model.Destroying:Connect(function()
		caches[model] = nil
	end)

	cache = {
		parts = parts,
		decals = decals,
		effects = effects,
		current = 0,
		dirty = false,
		release = function()
			descendant_added:Disconnect()
			descendant_removing:Disconnect()
			destroying:Disconnect()
			caches[model] = nil
		end,
	}
	caches[model] = cache
	return cache
end

local function move_towards(current: number, target: number, max_delta: number): number
	if math.abs(target - current) <= max_delta then
		return target
	end
	return current + max_delta * (if target > current then 1 else -1)
end

RunService.Heartbeat:Connect(function(dt: number)
	for model, cache in caches do
		local target = math.clamp(model:GetAttribute(TARGET_ATTR) :: number? or 0, 0, 0.999)

		if math.abs(cache.current - target) <= SETTLE_EPSILON then
			if target <= 0 then
				cache.release()
				continue
			end
			cache.current = target
			continue
		end

		if cache.dirty then
			cache.parts, cache.decals, cache.effects = collect(model)
			cache.dirty = false
		end

		cache.current = move_towards(cache.current, target, FADE_RATE * dt)

		for _, part in cache.parts do
			if part.LocalTransparencyModifier ~= cache.current then
				part.LocalTransparencyModifier = cache.current
			end
		end

		for _, decal in cache.decals do
			if (decal :: any).LocalTransparencyModifier ~= cache.current then
				(decal :: any).LocalTransparencyModifier = cache.current
			end
		end

		local effect_hidden = cache.current > 0
		for _, effect in cache.effects do
			local modifier = if effect_hidden then 1 else 0
			if (effect :: any).LocalTransparencyModifier ~= modifier then
				(effect :: any).LocalTransparencyModifier = modifier
			end
		end
	end
end)

return table.freeze {
	omit = function(part: BasePart)
		part:AddTag(OMIT_TAG)
	end,
	add = function(model: Model, delta: number)
		get_cache(model)
		local current_target = model:GetAttribute(TARGET_ATTR) :: number? or 0
		model:SetAttribute(TARGET_ATTR, current_target + delta)
	end,
}
