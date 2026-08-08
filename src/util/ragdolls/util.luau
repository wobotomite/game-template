const collider_part_name = "ragdoll-collider-part"
const root_weld_name = "ragdoll-root-weld"
export type SocketMapValue = {
	parent: Motor6D,
	socket: BallSocketConstraint,
	a0: Attachment,
	a1: Attachment,
}

@native
function get_joint_map(rig: Model): { Motor6D }
	const joint_map = rig:QueryDescendants "Motor6D" :: { Motor6D }
	local n = {}

	for i, entry in joint_map do
		if entry.Part0 and entry.Part1 then
			if not entry.Part0.CanCollide and not entry.Part0.CanQuery then
				continue
			end

			if not entry.Part1.CanCollide and not entry.Part1.CanQuery then
				continue
			end

			table.insert(n, entry)
		end
	end

	return n
end

@native
function clear_colliders(colliders: { BasePart })
	for i, v in colliders do
		v:Destroy()
	end
	table.clear(colliders)
end

@native
function create_collider_part(part: BasePart): Part
	const p = Instance.new "Part"
	p.CollisionGroup = "RagdollColliders"
	p.Name = collider_part_name
	p.Size = part.Size / 1.7
	p.Massless = true
	p.Archivable = false
	p.CanCollide = true
	p.Transparency = 1

	const weld = Instance.new "Weld"
	weld.Part0 = p
	weld.Parent = p

	weld.Part1 = part
	p.Parent = part
	return p
end

@native
function create_colliders(socketMap: { SocketMapValue }): { BasePart }
	const colliderArr: { BasePart } = {}
	for i, v in socketMap do
		const p = v.a1.Parent
		if p == nil or p:FindFirstChild(collider_part_name) or not p:IsA "BasePart" then
			continue
		end
		table.insert(colliderArr, create_collider_part(p))
	end
	return colliderArr
end

@native
function ragdoll_weld_root(rig: Model)
	assert(rig.PrimaryPart, "no primary part found")
	assert(rig.PrimaryPart:FindFirstChild(root_weld_name) == nil, "already welded root")
	for i, joint in rig:QueryDescendants "Motor6D#RootJoint" do
		const Weld = Instance.new "Weld"
		Weld.Name = root_weld_name
		Weld.Enabled = false
		Weld.Part0 = joint.Part0
		Weld.Part1 = joint.Part1
		Weld.Parent = rig.PrimaryPart
		return Weld
	end
	error "could not find root joint!"
end

function build_sockets_from_joint_map(jointMap: { Motor6D })
	const socket_map: { SocketMapValue } = {}
	for i, v in jointMap do
		const a0 = Instance.new "Attachment"
		a0.Name = "ragdoll-attachment-0"
		a0.CFrame = v.C0
		a0.Parent = v.Part0

		const a1 = Instance.new "Attachment"
		a1.Name = "ragdoll-attachment-1"
		a1.CFrame = v.C1
		a1.Parent = v.Part1

		const socket = Instance.new "BallSocketConstraint"
		socket.Name = "ragdoll-ball-socket ->" .. v.Name
		socket.Enabled = false
		socket.LimitsEnabled = true
		socket.TwistLimitsEnabled = true
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.Parent = v

		table.insert(socket_map, { parent = v, socket = socket, a0 = a0, a1 = a1 })
	end

	return socket_map
end
return table.freeze {
	build_sockets_from_joint_map = build_sockets_from_joint_map,
	root_weld_name = root_weld_name,
	ragdoll_weld_root = ragdoll_weld_root,
	create_colliders = create_colliders,
	clear_colliders = clear_colliders,
	get_joint_map = get_joint_map,
}
