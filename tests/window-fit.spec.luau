--!nocheck
-- `ui/kit/window-fit` is the arithmetic a window sizes itself by.
-- Run with:
--   lune run tests/window-fit.spec.luau
--
-- WHY THIS ONE MODULE HAS A SPEC and no other widget in the kit does. Every
-- other file under `ui/kit` builds instances: what it gets wrong, a Play
-- session shows in a second. These three sums get it wrong INVISIBLY -- a
-- footer that reserves one gap too few clips the bottom row of buttons by six
-- pixels, on the window with the most buttons, at the scale where the window is
-- tallest. Nobody finds that by looking.
--
-- The derived relationships are checked against the live `settings.ui`, so a
-- retheme does not break them. The two ABSOLUTE magnitudes at the bottom are
-- checked against numbers written out here on purpose: they go red when
-- somebody tunes ACTION_HEIGHT or GAP, which is a conversation worth having
-- rather than a test worth re-pointing.

local h = require "./harness"
local env = require "./roblox-env"

h.title "window fit:"

local fit = env.load "ReplicatedStorage.Client.ui.kit.window-fit"
local ui = env.load("ReplicatedStorage.Shared.settings").ui
local METRICS = ui.METRICS
local STYLE = ui.STYLE

-- No buttons means no divider either, so there is nothing to reserve. Not the
-- bare rule height: a window with no footer must give its body the whole sheet.
do
	h.equals("no rows reserve nothing", fit.footer_height(0), 0)
	h.equals("no rows cost the body nothing", fit.body_offset(0), 0)
	h.equals("a negative row count is still nothing", fit.footer_height(-1), 0)
end

-- ONE GAP PER ROW, not one BETWEEN rows. The footer's list layout pads every
-- child after the first and the DIVIDER is the first child, so N rows means N
-- gaps. Off by one here and the last row hangs over the window's bottom edge.
do
	local one = fit.footer_height(1)
	h.equals("one row is a row, a gap and the divider", one, METRICS.ACTION_HEIGHT + METRICS.GAP + STYLE.WINDOW_RULE)
	local three = fit.footer_height(3)
	h.equals(
		"three rows are three rows and three gaps",
		three,
		3 * (METRICS.ACTION_HEIGHT + METRICS.GAP) + STYLE.WINDOW_RULE
	)
	-- The step between row counts is exactly one row plus one gap: the divider
	-- is paid for once, not once per row.
	h.equals("each extra row costs a row and a gap", three - fit.footer_height(2), METRICS.ACTION_HEIGHT + METRICS.GAP)
end

-- The body gives up the footer plus the ONE further gap the sheet's own layout
-- puts between the two. A body sized without it overlaps the divider.
do
	h.equals("a footer costs the body one gap more than itself", fit.body_offset(2) - fit.footer_height(2), METRICS.GAP)
	h.equals("and the same at four rows", fit.body_offset(4) - fit.footer_height(4), METRICS.GAP)
end

-- The wipe. A shut window is its title-plate headroom and nothing else -- the
-- plate does NOT wipe, because a title growing with the sheet reads as the
-- window inflating rather than opening.
do
	h.equals("shut is the title headroom alone", fit.outer(16, 400, 2, 0), 16)
	h.equals("open is the headroom, the sheet and its border", fit.outer(16, 400, 2, 1), 418)
	h.equals("half open is half the sheet", fit.outer(16, 400, 2, 0.5), 16 + 201)
end

-- ROUNDED, always. The window frame clips its contents, and a fractional height
-- makes the bottom border shimmer for the length of the wipe.
do
	local height = fit.outer(16, 101, 1, 0.37)
	h.check("a partial wipe is a whole number of pixels", height % 1 == 0, `got {height}`)
	h.equals("and it is the rounded value", height, 16 + math.round(102 * 0.37))
end

-- THE FELT MAGNITUDES, at the settings this template ships with. A window 400
-- design pixels tall with one row of buttons gives its body 343 of them; add a
-- second row and the body is down to 293. These are the numbers a panel author
-- is laying text out inside.
do
	h.equals("one button row costs the body 57px", fit.body_offset(1), 57)
	h.equals("two button rows cost the body 107px", fit.body_offset(2), 107)
	h.equals("a 400px window keeps 343px of body under one row", 400 - fit.body_offset(1), 343)
end

h.done()
