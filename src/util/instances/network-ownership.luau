const Players = game:GetService "Players"
const RunService = game:GetService "RunService"
const attr = "__ntwrk_ownr"

-- EVERY OWNERSHIP CALL IN THE ENGINE THROWS ON A PART IT CANNOT SIMULATE:
-- "Network Ownership API cannot be called on Anchored parts", and the same for
-- a part that is not in the Workspace. Both states are ordinary here -- a prop
-- anchored while it is being placed, a tool parented to ReplicatedStorage
-- between owners, a part destroyed on the frame a step signal re-asserts its
-- owner -- and an error out of `set` killed the caller's whole tick. So the two
-- states are tested for, the calls are `pcall`ed for whatever else the engine
-- adds to that list, and `set` / `clear` say whether the owner actually took.
function simulated(p: BasePart): boolean
	return not p.Anchored and p:IsDescendantOf(workspace)
end

function get(p: BasePart)
	if RunService:IsServer() then
		if not simulated(p) then
			return nil
		end
		const ok, owner = pcall(p.GetNetworkOwner, p)
		return if ok then owner else nil
	end
	const uid = p:GetAttribute(attr)
	if not uid then
		return nil
	end
	return Players:GetPlayerByUserId(uid :: never)
end

-- True when `plr` owns the part AND the engine has been told to leave it that
-- way. The second half matters for the server (`plr == nil`): an unowned part
-- on automatic ownership also reports a nil owner, and treating that as
-- "already cleared" left dropped props on auto, handed straight to whichever
-- player stood nearest.
function pinned_to(p: BasePart, plr: Player?): boolean
	const ok, owner = pcall(p.GetNetworkOwner, p)
	if not ok or owner ~= plr then
		return false
	end
	const auto_ok, auto = pcall(p.GetNetworkOwnershipAuto, p)
	return auto_ok and auto == false
end

-- The SetNetworkOwner call is guarded on the owner ACTUALLY DIFFERING, because
-- it is not a no-op in the engine: re-assigning the owner a part already has
-- still resets that part's ownership, which interrupts the simulation the
-- current owner is part-way through and reads client-side as a hitch or a
-- rubber-band. Any call site that re-asserts ownership on a step signal -- a
-- carried prop, a conveyor, anything refreshed per tick -- paid that on EVERY
-- tick. The attribute write above is left unconditional: it is cheap, and it
-- also repairs a part whose attribute was stripped (a clone, a rejoin).
--
-- Returns whether the part is now owned by `plr`. False is not an error: it is
-- the anchored / not-in-Workspace case, and the attribute is still written so
-- a client reading `get` sees the intended owner once the part is released.
function set(p: BasePart, plr: Player): boolean
	assert(RunService:IsServer(), "set can only be called on the server")
	p:SetAttribute(attr, plr.UserId)

	if not simulated(p) then
		return false
	end
	if pinned_to(p, plr) then
		return true
	end
	return (pcall(p.SetNetworkOwner, p, plr))
end

-- Hand the part back to the SERVER, and clear the mirror attribute with it.
--
-- Not the same as `SetNetworkOwnershipAuto`: nil PINS ownership to the server,
-- which is what releasing a part from a player's control wants -- a dropped
-- tool, a prop leaving a player's hands -- rather than letting the engine hand
-- it straight back to whoever is standing nearest.
--
-- CLEARING THE ATTRIBUTE IS THE HALF THAT MATTERS. `GetNetworkOwner` is
-- server-only, so `get` on a CLIENT reads the attribute instead. Leave it set
-- and every client keeps reporting the old player indefinitely -- a wrong
-- answer on the one side that has no way to check it against the truth.
function clear(p: BasePart): boolean
	assert(RunService:IsServer(), "clear can only be called on the server")
	p:SetAttribute(attr, nil)

	if not simulated(p) then
		return false
	end
	if pinned_to(p, nil) then
		return true
	end
	return (pcall(p.SetNetworkOwner, p, nil))
end

return table.freeze {
	set = set,
	get = get,
	clear = clear,
}
