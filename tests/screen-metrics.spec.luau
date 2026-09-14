--!nocheck
-- `ui/screen-metrics` folds the gui inset and the touch clearance into one
-- padding table.
-- Run with:
--   lune run tests/screen-metrics.spec.luau
--
-- Only `compose` is pinned: everything else in the module reads the engine, and
-- under Lune the engine is a stub. What `compose` gets wrong it gets wrong
-- PLAUSIBLY -- a sum instead of a max still returns a padding that looks like
-- one, and the phone it is wrong on is not the phone anyone tests on.

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"
local Vector2 = roblox.Vector2

h.title "screen metrics:"

local metrics = env.load "ReplicatedStorage.Util.ui.screen-metrics"
local compose = metrics.compose

-- Desktop: a topbar and nothing else. The padding IS the gui inset.
do
	local pad = compose(Vector2.new(0, 58), Vector2.zero, 0)
	h.equals("desktop top is the topbar", pad.top, 58)
	h.equals("desktop bottom is zero", pad.bottom, 0)
	h.equals("desktop sides are zero", pad.left + pad.right, 0)
end

-- Notched phone: the engine folds the notch into the top-left corner and the
-- home indicator into the bottom-right, so the inset comes through as-is.
do
	local pad = compose(Vector2.new(44, 58), Vector2.new(44, 34), 0)
	h.equals("a side notch pads the sides", pad.left + pad.right, 88)
	h.equals("the home indicator pads the bottom", pad.bottom, 34)
end

-- Touch: the thumbstick is the only thing at the bottom on most phones, and it
-- reaches higher than the home indicator; the larger wins.
do
	local pad = compose(Vector2.zero, Vector2.new(0, 34), 120)
	h.equals("thumbstick above the home indicator sets the bottom", pad.bottom, 120)
	local low = compose(Vector2.zero, Vector2.new(0, 34), 10)
	h.equals("home indicator above a low thumbstick sets the bottom", low.bottom, 34)
end

-- A negative reading (a control measured off the bottom of the screen) is a
-- measurement error, not a request to pull content OUT past the edge.
do
	local pad = compose(Vector2.zero, Vector2.zero, -20)
	h.equals("a negative clearance clamps to zero", pad.bottom, 0)
end

h.done()
