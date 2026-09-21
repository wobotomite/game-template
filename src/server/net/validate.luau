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

-- Non-negative whole number with a ceiling. For a COUNT off the wire -- how
-- many of a thing to buy, which slot to use -- where a fractional or negative
-- value reaches arithmetic that was written assuming neither.
--
-- `n ~= n` is the NaN test, and it is deliberately REDUNDANT today: `NaN % 1`
-- is NaN, so the whole-number test right after it already rejects NaN. It is
-- spelled out because that redundancy is an accident of how NaN propagates
-- through `%`, and it ends the moment somebody relaxes the whole-number
-- requirement -- at which point the bounds alone would pass NaN, which
-- compares false against every bound, including the ones meant to exclude it.
function count(value: unknown, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	const n = value :: number
	if n ~= n or n % 1 ~= 0 or n < 0 or n > max then
		return nil
	end
	return n
end

-- Non-empty string under a length ceiling. The ceiling is the point: a string
-- field in a buffer schema is bounded by the schema, but a string that reaches
-- a DataStore, a chat line or an instance Name is bounded by whatever the
-- caller thought to check, and nobody thinks to check.
--
-- Empty is rejected as well as over-long, because every caller so far wanted a
-- value it could show or store, and "" is neither -- it is a field the sender
-- left out, arriving as if it were filled in.
function text(value: unknown, max_len: number): string?
	if typeof(value) ~= "string" then
		return nil
	end
	const s = value :: string
	if #s == 0 or #s > max_len then
		return nil
	end
	return s
end

-- 2^53 is the largest integer a double represents exactly. Past it, `id` and
-- `id + 1` are the same number, so an id compared or used as a table key stops
-- meaning one account.
const USER_ID_MAX = 2 ^ 53

-- A user id off the wire, for anything that looks a player up by id rather
-- than by Player instance. Zero is rejected because it is what an unset field
-- decodes to, and `GetPlayerByUserId(0)` is a lookup that can only ever miss.
function user_id(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	const id = value :: number
	if id ~= id or id % 1 ~= 0 or id == 0 or math.abs(id) > USER_ID_MAX then
		return nil
	end
	return id
end

export type Limiter = (player: Player) -> boolean

-- A per-player ring of the last `max_count` accept times. `head` counts
-- accepts forever and is taken modulo the ring size, so the slot it points at
-- always holds the OLDEST of the remembered accepts.
type Ring = { at: { number }, head: number }

-- TRUE SLIDING-window limiter: at most `max_count` accepts in any `window`
-- seconds, measured against real timestamps rather than a window that resets.
--
-- The earlier version here counted calls into a window that was thrown away
-- wholesale once it aged out, and that has two failure modes, both of which
-- this ring closes:
--
--   * a caller could land `max_count` at the very end of one window and
--     `max_count` again at the start of the next, so the real worst case was
--     TWICE the cap in a short span -- and a limit exists to bound the worst
--     case, not the typical one;
--   * from the other side, a legitimate client sending at exactly the cap LOST
--     sends, because its own rate and the window edge drift against each other.
--
-- The ring is O(1) in time and `max_count` numbers in space, and it is exact:
-- an accept is allowed precisely when the `max_count`-th most recent accept is
-- further back than `window`. A REJECTED call does not consume a slot, so a
-- client hammering a limiter cannot push its own legitimate sends out of the
-- ring.
--
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
const all_windows: { { [Player]: Ring } } = {}

observe_players(function(player: Player): () -> ()
	return function()
		-- Departure clears that player's entry in every limiter at once.
		for _, windows in all_windows do
			windows[player] = nil
		end
	end
end)

function limiter(max_count: number, window: number): Limiter
	const windows: { [Player]: Ring } = {}
	table.insert(all_windows, windows)
	return function(player: Player): boolean
		local entry = windows[player]
		if not entry then
			-- -math.huge, not 0 and not `now`: a fresh ring must read as "those
			-- accepts happened infinitely long ago" so the first `max_count`
			-- calls are all allowed. Seeding with the current time instead would
			-- make a player's first burst after joining the one burst that gets
			-- throttled.
			entry = { at = table.create(max_count, -math.huge), head = 0 }
			windows[player] = entry
		end
		const now = os.clock()
		const slot = entry.head % max_count + 1
		if now - entry.at[slot] <= window then
			return false
		end
		entry.at[slot] = now
		entry.head += 1
		return true
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

-- "This player has no living body to act with." The negation of `alive_root`
-- as its own name, because the guard reads as a condition at every call site
-- (`if validate.downed(player) then return end`) and spelling it as a nil
-- check on a part nobody goes on to use is the kind of line that gets
-- "simplified" away by someone who cannot see what it was for.
function downed(player: Player): boolean
	return alive_root(player) == nil
end

return table.freeze {
	finite = finite,
	finite_vector = finite_vector,
	sane_direction = sane_direction,
	count = count,
	text = text,
	user_id = user_id,
	limiter = limiter,
	alive_root = alive_root,
	downed = downed,
}
