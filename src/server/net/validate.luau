const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- Payload sanity and per-player rate limiting for remote handlers.
--
-- sendbufs already guarantees payload SHAPE -- a buffer schema cannot decode
-- into the wrong types. What it does not check is VALUES (NaN, infinity, a
-- direction vector of length 900) or RATES, and both are what a modified client
-- sends.
--
-- ALL REJECTIONS ARE SILENT. Not `assert`, not `warn`: an assert on a remote
-- handler is a client-triggerable server error -- free log spam, and an
-- exception thrown out of a shared dispatch costs whatever was scheduled after
-- it on that frame. Drop the message and move on.

function finite(n: number): boolean
	return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function finite_vector(v: Vector3): boolean
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

function sane_direction(v: Vector3): Vector3?
	if not finite_vector(v) then
		return nil
	end
	const magnitude = v.Magnitude
	if magnitude < 0.5 or magnitude > 2 then
		return nil
	end
	return v.Unit
end

export type Limiter = (player: Player) -> boolean

-- TUMBLING-window limiter: allows `max_count` calls per `window` seconds, with
-- the window RESETTING WHOLESALE rather than tracking timestamps.
--
-- SIZE YOUR LIMITS AGAINST 2x max_count. This was labelled "sliding" for a
-- while, which promises a stricter guarantee than it gives, and the difference
-- is load-bearing: a caller can land `max_count` at the very end of one window
-- and `max_count` again at the start of the next, so the real worst case is
-- twice the cap in a short span.
--
-- The same boundary bites from the other side, which is the part that surprises
-- people: a legitimate client sending at exactly the cap LOSES sends to it,
-- because its own rate and the window edge drift against each other. A sender
-- that must not be throttled needs headroom under the cap, not equality with
-- it.
--
-- A true sliding window (a timestamp ring per player) is stricter and costs
-- more; this is the cheap one, and it is honest about which it is.
-- ONE subscription for every limiter, not one EACH.
--
-- `limiter` is a factory, so the obvious shape -- an `observe_players` inside
-- it, closing over that limiter's own window table -- takes a fresh permanent
-- subscription per call and hands back no way to release it. Every limiter a
-- process ever creates keeps one alive. Today's callers all build theirs once
-- at module scope, so the count is small and fixed and nothing misbehaves; the
-- shape is still wrong, and it is wrong in the direction that only shows up
-- once somebody builds one per room or per run.
--
-- Registering the window tables here instead costs one subscription for the
-- process. Holding them forever is not a leak in the way the subscription was:
-- a limiter exists to be called, so anything that created one is keeping it.
const all_windows: { { [Player]: { at: number, count: number } } } = {}

observe_players(function(player: Player): () -> ()
	return function()
		-- Departure clears that player's entry in every limiter at once.
		for _, windows in all_windows do
			windows[player] = nil
		end
	end
end)

function limiter(max_count: number, window: number): Limiter
	const windows: { [Player]: { at: number, count: number } } = {}
	table.insert(all_windows, windows)
	return function(player: Player): boolean
		local entry = windows[player]
		const now = os.clock()
		if not entry or now - entry.at > window then
			entry = { at = now, count = 0 }
			windows[player] = entry
		end
		entry.count += 1
		return entry.count <= max_count
	end
end

function alive_root(player: Player): BasePart?
	const character = player.Character
	if not character then
		return nil
	end
	const humanoid = character:FindFirstChildOfClass "Humanoid"
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild "HumanoidRootPart" :: BasePart?
end

return table.freeze {
	finite = finite,
	finite_vector = finite_vector,
	sane_direction = sane_direction,
	limiter = limiter,
	alive_root = alive_root,
}
