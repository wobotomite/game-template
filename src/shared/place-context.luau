const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const place_ids = require(ReplicatedStorage.Shared.records["place-ids"])

-- Which place am I in?
--
-- The same build is published to every place in the universe, so nothing in a
-- script's own contents can answer this — `game.PlaceId` is the only runtime
-- truth. This resolves it once, at require time, and every consumer reads the
-- answer instead of re-deriving it.
--
--   if place_context.is "lobby" then ... end
--   place_context.role  -- "lobby"
--
-- FALLBACK, NOT FAILURE. A place id that matches nothing in records/place-ids
-- resolves to `main`. That is what makes an unpublished place, a fresh .rbxlx,
-- and a single-place game all work with no configuration: a half-filled
-- universe behaves like the default experience rather than like a bug. It
-- warns once outside Studio when there was something to match and nothing did,
-- because in a real multi-place game that IS a misconfiguration -- just not one
-- worth crashing a live server over.

const FALLBACK_ROLE = "main"

local resolved = FALLBACK_ROLE
local matched = false

for role, id in (place_ids :: any) :: { [string]: number } do
	if id ~= 0 and game.PlaceId == id then
		resolved = role
		matched = true
		break
	end
end

-- Studio override, for dev files whose PlaceId is 0: a `PlaceTag` StringValue
-- in ReplicatedStorage naming a role forces the answer. Ignored outside Studio
-- so a tag accidentally baked into a published file can never lie about which
-- place a live server is.
if RunService:IsStudio() then
	const tag = ReplicatedStorage:FindFirstChild "PlaceTag"
	if tag and tag:IsA "StringValue" and tag.Value ~= "" then
		resolved = tag.Value
		matched = true
	end
end

if not matched and not RunService:IsStudio() then
	local configured = 0
	for _, id in (place_ids :: any) :: { [string]: number } do
		if id ~= 0 then
			configured += 1
		end
	end
	if configured > 0 then
		warn(
			`[place-context] PlaceId {game.PlaceId} matches no role in records/place-ids; `
				.. `falling back to "{FALLBACK_ROLE}". Fill in the id for this place.`
		)
	end
end

const role = resolved

function is(name: string): boolean
	return role == name
end

return table.freeze {
	role = role,

	is = is,

	-- Was the role decided by a real match (or a Studio tag), or is this the
	-- fallback? Anything that must not run in the wrong place -- a teleport
	-- home, a data migration -- should check this rather than trusting `role`.
	is_resolved = matched,

	-- True in a reserved server (one created by TeleportToPrivateServer /
	-- ReserveServer) rather than a public or VIP one.
	--
	-- SERVER-ONLY TRUTH. A client reading PrivateServerId gets "" and a
	-- warning, so this is always false on the client. Gate on it server-side
	-- and replicate the answer if the client needs it.
	is_reserved = RunService:IsServer() and game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0,
}
