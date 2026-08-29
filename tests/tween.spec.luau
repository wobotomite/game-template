--!nocheck
-- util/tween: what happens when the same instance is tweened twice.
-- Run with:
--   lune run tests/tween.spec.luau
--
-- WHY THIS EXISTS. `tween` keys its running tweens BY INSTANCE, so starting a
-- second one on the same instance has to do something with the first. It used
-- to call `previous:cancel()`, and cancel calls the outgoing `tween_fn` with
-- alpha 0 — repainting the property to the OLD tween's START value, one frame
-- before the replacement's first frame runs.
--
-- So every re-tween of one instance flashed backwards, and the flash was
-- INVISIBLE OR OBVIOUS PURELY BY COINCIDENCE OF THE CALLER'S CONSTANTS:
--
--   * fixed endpoints (fade 0.6 -> 1, re-fired on every hit) repainted exactly
--     what the replacement was about to paint anyway. Silent — and it would
--     have become visible the moment somebody refactored it to "fade from
--     wherever it is now".
--   * a CAPTURED start value (`scale_from = fill.Size.X.Scale`, re-tweened on
--     every damage tick) repainted the previous call's captured scale, which
--     during damage is strictly fuller. A progress bar that jumped back up on
--     most damage ticks of every fight.
--
-- The fix is one word — replace, do not cancel — and nothing in the type system
-- or the analyzer has an opinion about it. This spec is the opinion.
--
-- NOTE ON WHAT IS DRIVEN: the per-frame loop runs on a render-step signal that
-- never fires under a stubbed RunService, so these cases exercise the
-- REPLACEMENT and CANCEL paths, which are synchronous, and not interpolation.
-- That is the half where the bug was.

local h = require "./harness"
local env = require "./roblox-env"
-- The spec itself is a plain Lune script, so Roblox datatypes are not globals
-- here the way they are inside a module loaded through roblox-env.
local roblox = require "@lune/roblox"

h.title "tween:"

-- Client realm: `new` asserts on it, since a tween is a visual thing.
local tween = env.load("ReplicatedStorage.Util.tween", { realm = "client" })

local function subject()
	-- A real Lune Instance, because `tween` keys its table by Instance.
	return roblox.Instance.new "Part"
end

-- ======================= replacement does not repaint =====================

do
	local part = subject()
	local painted: { number } = {}

	tween(part, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function(value)
		table.insert(painted, value)
	end, 0.25, 1)

	local before = #painted
	-- Re-tween the SAME instance. This is the routine case, not an edge: any
	-- property driven by a stream of events (health, hover state, a meter) gets
	-- re-tweened while the previous one is still running.
	tween(part, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function() end, 0.9, 1)

	h.equals("replacing a tween does not repaint the outgoing start value", #painted, before)
	h.check("nothing was painted at all by the replacement", #painted == 0)
end

-- ==================== explicit cancel still reverts ========================

do
	local part = subject()
	local painted: { number } = {}

	local running = tween(part, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function(value)
		table.insert(painted, value)
	end, 0.25, 1)

	-- Asked for BY NAME. A caller that wants the property put back — a cutscene
	-- track cleaning up, a UI element resetting on close — still gets it. That
	-- is why the fix was to stop calling cancel on replacement, rather than to
	-- change what cancel does.
	running:cancel()

	h.equals("cancel repaints exactly once", #painted, 1)
	h.equals("and repaints the START value", painted[1], 0.25)
end

-- ================== a replaced tween is inert afterwards ===================

do
	local part = subject()
	local painted = 0

	local first = tween(part, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function()
		painted += 1
	end, 0.25, 1)

	tween(part, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function() end, 0.9, 1)

	-- Holding a handle to a tween that has since been replaced and cancelling
	-- it must do nothing. Otherwise a caller that keeps its handle around --
	-- which is the normal reason to keep one -- can repaint a property that
	-- now belongs to somebody else's tween.
	first:cancel()
	h.equals("cancelling an already-replaced tween is a no-op", painted, 0)
end

-- ========================= independent instances ===========================

do
	local a, b = subject(), subject()
	local a_painted, b_painted = 0, 0

	local a_tween = tween(a, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function()
		a_painted += 1
	end, 0, 1)
	tween(b, 1, roblox.Enum.EasingStyle.Linear, roblox.Enum.EasingDirection.Out, function()
		b_painted += 1
	end, 0, 1)

	a_tween:cancel()
	h.equals("cancelling one instance's tween repaints only that one", a_painted, 1)
	h.equals("the other instance is untouched", b_painted, 0)
end

h.done()
