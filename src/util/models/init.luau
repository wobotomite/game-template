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

@native
function recursive_weld(i: Model)
	const primary = i.PrimaryPart
	assert(primary, `NO PRIMARY PART FOUND FOR {i.Name}`)

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
		local parent: BasePart
		const __parent_impl = part.Parent
		if not __parent_impl or not __parent_impl:IsA "BasePart" then
			parent = primary
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
