const Players = game:GetService "Players"
const RunService = game:GetService "RunService"
const attr = "__ntwrk_ownr"

function get(p: BasePart)
	if RunService:IsServer() then
		return p:GetNetworkOwner()
	end
	const uid = p:GetAttribute(attr)
	if not uid then
		return nil
	end
	return Players:GetPlayerByUserId(uid :: never)
end

-- The SetNetworkOwner call is guarded on the owner ACTUALLY DIFFERING, because
-- it is not a no-op in the engine: re-assigning the owner a part already has
-- still resets that part's ownership, which interrupts the simulation the
-- current owner is part-way through and reads client-side as a hitch or a
-- rubber-band. Any call site that re-asserts ownership on a step signal -- a
-- carried prop, a conveyor, anything refreshed per tick -- paid that on EVERY
-- tick. The attribute write above is left unconditional: it is cheap, and it
-- also repairs a part whose attribute was stripped (a clone, a rejoin).
function set(p: BasePart, plr: Player)
	assert(RunService:IsServer(), "set can only be called on the server")
	p:SetAttribute(attr, plr.UserId)

	if p:GetNetworkOwner() ~= plr then
		p:SetNetworkOwner(plr)
	end
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
function clear(p: BasePart)
	assert(RunService:IsServer(), "clear can only be called on the server")
	p:SetAttribute(attr, nil)

	if p:GetNetworkOwner() ~= nil then
		p:SetNetworkOwner(nil)
	end
end

return table.freeze {
	set = set,
	get = get,
	clear = clear,
}
