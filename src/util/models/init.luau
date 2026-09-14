@native
function set_color(i: Instance, clr: Color3)
	for i, v in i:QueryDescendants "SurfaceAppearance,BasePart,PointLight" do
		v.Color = clr
	end
	for i, v in i:QueryDescendants "ParticleEmitter,Beam,Trail" do
		v.Color = ColorSequence.new(clr)
	end
end

@native
function get_unrotated_extents_size(mdl: Model)
	const arr: { Vector3 } = {}
	for _, basePart in mdl:QueryDescendants "BasePart[Transparency<.99]" do
		if basePart.Transparency > 0.99 then
			continue
		end
		table.insert(arr, basePart.Size)
	end
	return Vector3.zero.Max(unpack(arr))
end

@native
function remove_physics(i: Instance)
	for i, v in i:QueryDescendants "BasePart" do
		v.CanCollide = false
		v.Massless = true
		v.CanTouch = false
		v.CanQuery = false
		v.Anchored = false
	end
end

-- Weld every BasePart under `i` to its nearest BasePart ancestor, and anything
-- with no such ancestor to the root.
--
-- `anchor` NAMES THE ROOT EXPLICITLY, and taking an `Instance` rather than a
-- `Model` is what that buys: a Folder of loose parts, or an accessory, has no
-- PrimaryPart to fall back on and could not be welded at all before. It also
-- covers the case where a Model HAS a PrimaryPart and it is the wrong choice --
-- welding a rig to its HumanoidRootPart instead of to whatever the artist
-- happened to set. Omit it and the old behaviour is unchanged: the Model's
-- PrimaryPart, asserted.
@native
function recursive_weld(i: Instance, anchor: BasePart?)
	local primary: BasePart? = anchor
	if not primary and i:IsA "Model" then
		primary = i.PrimaryPart
	end
	assert(primary, `NO PRIMARY PART FOUND FOR {i.Name}`)
	-- Re-asserted after the assert so the closures below see a non-optional
	-- BasePart rather than each re-proving it.
	const root = primary :: BasePart

	local function weld(main: BasePart, target: BasePart)
		const connected = main:GetConnectedParts()
		if table.find(connected, target) then
			return
		end
		const c0 = main.CFrame:ToObjectSpace(target.CFrame)
		const weld = Instance.new "Weld"

		weld.Name = `__autoweld > {target.Name}`
		weld.Part0 = main
		weld.Part1 = target
		weld.C0 = c0

		weld.Parent = main
	end

	for _, part in i:QueryDescendants "BasePart" do
		-- The root is in its own descendant list, and its own parent is
		-- usually the Model rather than a BasePart -- so the fallback below
		-- used to weld the root TO ITSELF, producing a Weld with Part0 ==
		-- Part1. The engine accepts it silently and it constrains nothing, so
		-- it never surfaced as an error; it just left a junk instance inside
		-- the root of every welded model. Skip it at the source.
		if part == root then
			continue
		end
		local parent: BasePart
		const __parent_impl = part.Parent
		if not __parent_impl or not __parent_impl:IsA "BasePart" then
			parent = root
		else
			parent = __parent_impl
		end
		weld(parent, part)
	end
end

return table.freeze {
	recursive_weld = recursive_weld,
	remove_physics = remove_physics,
	set_color = set_color,
	get_unrotated_extents_size = get_unrotated_extents_size,
}
