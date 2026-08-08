const generate_id = require(script.Parent["generate-id"])
const ID_ATTRIBUTE = "__instance_unique_id"

@native
function get_instance_id(m: Instance)
	if m:IsA "Player" then
		return `?plr@{m.UserId}`
	end
	const res = m:GetAttribute(ID_ATTRIBUTE)
	if not res then
		const id = generate_id(12)
		m:SetAttribute(ID_ATTRIBUTE, id)
		return id
	end
	return res :: never
end

return get_instance_id
