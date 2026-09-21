--!nocheck
-- server/net/validate: the rate limiter, and the value checks whose ORDER is
-- load-bearing.
-- Run with:
--   lune run tests/validate.spec.luau
--
-- WHY THIS SPEC EXISTS. The limiter is the one piece of the module with state,
-- and the property it promises -- never more than `max_count` accepts inside
-- any `window` -- is invisible in the code and easy to lose. The version this
-- replaced counted calls into a window that reset wholesale, which let a caller
-- land a full quota just before the reset and another just after; the two
-- implementations agree on every simple case and disagree only at that edge.
-- So the edge is what is measured here.
--
-- The rest pins the value checks, NaN included. NaN is rejected twice over in
-- the module as it stands (the whole-number test catches it as well as the
-- explicit one), so these cases do not discriminate between the two -- they
-- are here so that REMOVING either one fails, because a value that is NaN at
-- the top of a handler is NaN in whatever arithmetic the handler does next.

local h = require "./harness"
local env = require "./roblox-env"
local task = require "@lune/task"

h.title "validate:"

local validate = env.load("ServerScriptService.Server.net.validate", { realm = "server" })

-- Any table works as a limiter key: the limiter only ever uses the player as a
-- table index, and nothing here leaves, so the stubbed Players service never
-- has to clear an entry.
local function player(name: string): any
	return { Name = name }
end

do
	-- A FRESH ring is seeded with -math.huge, which is what makes the first
	-- `max_count` calls all land. Seeded with the current time instead, a
	-- player's opening burst would be the one burst that gets throttled.
	local allow = validate.limiter(3, 10)
	local p = player "fresh"
	h.check("the first call is allowed", allow(p))
	h.check("and the second", allow(p))
	h.check("and the third", allow(p))
	h.check("the fourth inside the window is refused", not allow(p))
end

do
	-- Limiters are independent, and so are players within one. A shared counter
	-- here would mean one player's flood throttles everybody.
	local allow = validate.limiter(1, 10)
	local other = validate.limiter(1, 10)
	local a, b = player "a", player "b"
	h.check("player a gets its quota", allow(a))
	h.check("player a is then refused", not allow(a))
	h.check("player b is unaffected", allow(b))
	h.check("a second limiter is unaffected", other(a))
end

do
	-- A REFUSED call must not consume a slot. If it did, a client hammering a
	-- limiter would push its own accepted sends out of the ring and be
	-- throttled for longer the harder it tried -- and, worse, the limit would
	-- depend on the attacker's rate instead of bounding it.
	local window = 0.3
	local allow = validate.limiter(2, window)
	local p = player "hammer"
	allow(p)
	allow(p)
	for _ = 1, 8 do
		allow(p)
	end
	task.wait(window + 0.1)
	local granted = 0
	for _ = 1, 3 do
		if allow(p) then
			granted += 1
		end
	end
	h.equals("the full quota comes back after the window, and no more", granted, 2)
end

do
	-- THE WINDOW EDGE. This is the case the old tumbling window got wrong, and
	-- the only one where the two implementations differ.
	--
	-- One send early, two late, so the ring holds three accepts spread across
	-- the window. Then wait just long enough for the FIRST to age out and no
	-- longer: exactly one slot has come free, so exactly one more send may be
	-- accepted. A window that resets wholesale would hand back all three here,
	-- putting five accepts inside a fifth of a window on a limiter of three.
	local window = 0.4
	local allow = validate.limiter(3, window)
	local p = player "edge"

	h.check("the early send is accepted", allow(p))
	task.wait(0.36)
	h.check("and the two late ones", allow(p) and allow(p))

	task.wait(0.08)
	local granted = 0
	for _ = 1, 3 do
		if allow(p) then
			granted += 1
		end
	end
	h.equals("only the slot that aged out is reissued", granted, 1)
end

do
	h.equals("count accepts a whole number", validate.count(3, 10), 3)
	h.equals("count accepts zero", validate.count(0, 10), 0)
	h.equals("count rejects a fraction", validate.count(1.5, 10), nil)
	h.equals("count rejects a negative", validate.count(-1, 10), nil)
	h.equals("count rejects above the ceiling", validate.count(11, 10), nil)
	h.equals("count rejects a non-number", validate.count("3", 10), nil)
	-- `0/0 < 0` and `0/0 > max` are BOTH false, so bounds alone never exclude
	-- NaN: it is rejected here only because two other tests happen to.
	h.equals("count rejects NaN", validate.count(0 / 0, 10), nil)
end

do
	h.equals("text accepts a string under the ceiling", validate.text("hi", 8), "hi")
	h.equals("text rejects the empty string", validate.text("", 8), nil)
	h.equals("text rejects an over-long string", validate.text("123456789", 8), nil)
	h.equals("text rejects a non-string", validate.text(5, 8), nil)
end

do
	h.equals("user_id accepts a real id", validate.user_id(1234567), 1234567)
	-- Zero is what an unset field decodes to, and it can only ever miss.
	h.equals("user_id rejects zero", validate.user_id(0), nil)
	h.equals("user_id rejects a fraction", validate.user_id(1.5), nil)
	h.equals("user_id rejects NaN", validate.user_id(0 / 0), nil)
	-- Past 2^53 a double stops distinguishing consecutive integers, so an id
	-- beyond it no longer names one account.
	h.equals("user_id rejects past the exact-integer range", validate.user_id(2 ^ 54), nil)
end

h.done()
