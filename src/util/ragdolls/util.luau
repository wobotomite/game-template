const collider_part_name = "ragdoll-collider-part"
const root_weld_name = "ragdoll-root-weld"
-- Read back out by the parent module, which owns the collidable matrix.
const ragdoll_group = "RagdollColliders"
export type SocketMapValue = {
	parent: Motor6D,
	socket: BallSocketConstraint,
	a0: Attachment,
	a1: Attachment,
}

-- ANIMATIONCONSTRAINT IS QUERIED ALONGSIDE MOTOR6D because a modern rig can
-- have ZERO Motor6Ds. Roblox's newer character rigs drive their joints with
-- AnimationConstraint, and a Motor6D-only query over one of those comes back
-- EMPTY -- so the ragdoll built no sockets, created no colliders, and `set`
-- flipped a flag over nothing. The character just stayed standing, with nothing
-- thrown and nothing logged, because an empty joint map is indistinguishable
-- from a rig that genuinely has no joints.
--
-- WHAT THIS DOES AND DOES NOT FIX. It widens what is FOUND. The filter below
-- still requires Part0 and Part1, which an AnimationConstraint does not carry
-- -- it relates two Attachments -- so such a joint is found here and then
-- dropped, and the socket build has no path for it yet. That is deliberate:
-- an empty map is now distinguishable from an unsupported one when this is
-- stepped through, which is the part that was costing the time. A rig that is
-- PURELY AnimationConstraint-driven still does not ragdoll; wiring the socket
-- build to attachments is the follow-up, and it is not done here.
@native
function get_joint_map(rig: Model): { Motor6D }
	const joint_map = rig:QueryDescendants "Motor6D,AnimationConstraint" :: { Motor6D }
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
		-- Parent can be NIL, not just a non-BasePart: a collider whose host
		-- part was destroyed (character despawned mid-ragdoll, a limb removed)
		-- is still in this list, and indexing nil threw out of the teardown --
		-- which left every remaining collider in place and the ragdoll stuck.
		const host = v.Parent
		if host and host:IsA "BasePart" then
			host.CanCollide = true
		end
		v:Destroy()
	end
	table.clear(colliders)
end

@native
function create_collider_part(part: BasePart): Part
	const p = Instance.new "Part"
	p.CollisionGroup = ragdoll_group
	p.Name = collider_part_name
	p.Size = part.Size * 0.6
	-- `part.Name`, not `p.Name`: p was renamed to collider_part_name two lines
	-- up, so this test could never be true and heads never got their override.
	if part.Name == "Head" then
		p.Size = Vector3.one
	end
	p.Massless = true
	p.Archivable = false
	p.CanCollide = true
	p.Transparency = 1

	const weld = Instance.new "Weld"
	weld.Part0 = p
	weld.Parent = p

	weld.Part1 = part
	p.Parent = part
	part.CanCollide = false
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

-- RETURNS NIL RATHER THAN THROWING, on all three of its old failure paths.
--
-- Every caller is a ragdoll being set up or REPAIRED, and the three cases this
-- used to `assert` on are all things that happen normally rather than bugs:
--
--   * no PrimaryPart -- the character was destroyed, or is still streaming in;
--   * already welded -- the repair path in `init` calls this precisely because
--     it cannot tell whether the weld survived, so "it is already there" is the
--     expected answer, not an error. It now hands back the EXISTING weld, which
--     is what the caller wanted either way;
--   * no root joint -- see `get_joint_map`: a rig can legitimately have none
--     this query recognises.
--
-- Throwing out of any of them unwound the caller mid-setup and left the rig
-- half-built with no ragdoll and no way back. A nil return makes the outcome
-- something the caller can hold, and every caller in this module now does.
@native
function ragdoll_weld_root(rig: Model): Weld?
	const primary = rig.PrimaryPart
	if not primary then
		return nil
	end

	const existing = primary:FindFirstChild(root_weld_name)
	if existing and existing:IsA "Weld" then
		return existing
	end

	for i, joint in rig:QueryDescendants "Motor6D#RootJoint,Motor6D#Root,AnimationConstraint#Root" do
		const Weld = Instance.new "Weld"
		Weld.Name = root_weld_name
		Weld.Enabled = false
		Weld.Part0 = joint.Part0
		Weld.Part1 = joint.Part1
		Weld.Parent = primary
		return Weld
	end
	return nil
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
		--socket.LimitsEnabled = true
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
	ragdoll_group = ragdoll_group,
	ragdoll_weld_root = ragdoll_weld_root,
	create_colliders = create_colliders,
	clear_colliders = clear_colliders,
	get_joint_map = get_joint_map,
}
