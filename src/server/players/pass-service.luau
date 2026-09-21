const MarketplaceService = game:GetService "MarketplaceService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const passes = require(ReplicatedStorage.Shared.assets).passes
const commerce = require(ReplicatedStorage.Shared.settings).commerce
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- Game pass ownership: asked once per player per pass, cached, and republished
-- as a Player attribute so the client can gate UI without a round trip.
--
-- THE ONE RULE. `UserOwnsGamePassAsync` is a web call, and a web call that
-- fails is NOT the answer "does not own". Treating a failure as false takes a
-- paid feature away from somebody who paid for it -- the worst thing this file
-- could do -- so `check` returns THREE states: true, false, and nil for "could
-- not find out". Only true and false are cached; nil is asked again.
--
-- EVERY YIELD IS A HOLE. Between the call going out and the answer coming back
-- the player can leave, and writing an attribute onto a Player that has left
-- both errors and keeps the instance alive. Hence the `player.Parent == nil`
-- check after each yield rather than only at the top.

-- Cached answers, per player. Cleared when they leave, and cleared for one pass
-- when a purchase makes the cached "false" stale.
const owned: { [Player]: { [string]: boolean } } = {}
const listeners: { (Player, string) -> () } = {}

-- Asks (and caches) whether `player` owns the pass named `key` in
-- `assets.passes`. nil means the question could not be answered.
function check(player: Player, key: string): boolean?
	const known = owned[player]
	if known then
		const cached = known[key]
		if cached ~= nil then
			return cached
		end
	end

	const id = passes[key]
	if id == nil or id <= 0 then
		-- A pass key with no id yet is not owned by anyone, and there is nothing
		-- transient about that: answer false rather than nil so callers do not
		-- retry a question with no answer.
		return false
	end

	const ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
	if not ok then
		warn(`[passes] could not read {key} for {player.Name}: {tostring(result)}`)
		return nil
	end
	if player.Parent == nil then
		return nil
	end

	local record = owned[player]
	if not record then
		record = {}
		owned[player] = record
	end
	const had = record[key]
	record[key] = result == true

	-- The attribute is OPTIONAL: a pass with no `PASS_ATTRIBUTES` entry simply
	-- is not published to the client, which is right for a pass only the server
	-- acts on. `SetAttribute` with a nil name errors, so this is a guard, not a
	-- style choice.
	const attribute = commerce.PASS_ATTRIBUTES[key]
	if attribute then
		player:SetAttribute(attribute, result == true)
	end

	-- Fire on the TRANSITION into owned, so a listener runs once per player per
	-- pass whether ownership was there at join or bought mid-session, and a
	-- repeated `check` does not re-grant.
	if result == true and had ~= true then
		for _, listener in listeners do
			task.spawn(listener, player, key)
		end
	end
	return result == true
end

-- The plain question, for a caller that cannot act on "do not know". Unknown
-- reads as false HERE and only here: a feature gate has to decide something.
function owns(player: Player, key: string): boolean
	return check(player, key) == true
end

-- Runs `callback(player, key)` the first time a player is seen to own a pass.
-- This is where a pass's effect goes -- an unlock written into the save, a tool
-- handed out -- instead of inside this file, which knows nothing about the game.
function on_owned(callback: (Player, string) -> ())
	table.insert(listeners, callback)
end

-- Re-asks every pass, retrying while any answer came back unknown. Used at join
-- and after a purchase; also the thing to call from a "restore my purchases"
-- button if a game grows one.
function refresh(player: Player)
	for attempt = 1, commerce.PASS_CHECK_ATTEMPTS do
		local unknown = false
		for key in passes do
			if check(player, key) == nil then
				unknown = true
			end
		end
		if not unknown or player.Parent == nil then
			break
		end
		-- Backs off: a Roblox web service that just failed is usually still
		-- failing a second later, and the player is not waiting on this.
		task.wait(commerce.PASS_CHECK_RETRY_SECONDS * attempt)
	end
end

local started = false
function start()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player): () -> ()
		local disposed = false
		task.spawn(function()
			if disposed then
				return
			end
			refresh(player)
		end)
		return function()
			disposed = true
			-- Dropping the cache with the player is what keeps this table from
			-- being a leak, and also means a rejoin re-asks rather than trusting
			-- an answer from a session that may have ended hours ago.
			owned[player] = nil
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, purchased: boolean)
		if not purchased then
			return
		end
		for key, pass_id in passes do
			if pass_id > 0 and pass_id == id then
				-- INVALIDATE, do not assume. The cached answer is a stale
				-- `false`; clearing it makes the next `check` ask Roblox, which
				-- is also what fires `on_owned` exactly once.
				const known = owned[player]
				if known then
					known[key] = nil
				end
				task.spawn(check, player, key)
				return
			end
		end
	end)
end

return table.freeze {
	start = start,
	check = check,
	owns = owns,
	on_owned = on_owned,
	refresh = refresh,
}
