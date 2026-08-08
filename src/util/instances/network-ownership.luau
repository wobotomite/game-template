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

function set(p: BasePart, plr: Player)
	assert(RunService:IsServer(), "set can only be called on the server")
	p:SetAttribute(attr, plr.UserId)
	p:SetNetworkOwner(plr)
end

return table.freeze {
	set = set,
	get = get,
}
