-- HOW TALL A WINDOW IS: the three sums `kit/window` would otherwise do inline.
--
-- Separated because they are the one part of the window that is arithmetic
-- rather than instances, and arithmetic buried in a vide tree is arithmetic no
-- spec can reach. Every number here is in DESIGN pixels except `outer`, which
-- is handed values already scaled by `util/ui/hooks/px`.
--
-- WHY ANY OF THIS IS COMPUTED AT ALL. A window with a fixed `height` sizes its
-- body by subtraction: the sheet is the height the caller asked for, the footer
-- takes what it needs, and the body gets the rest. Getting the subtraction
-- wrong does not error -- it clips the last row of buttons off the bottom of a
-- panel, on the screens where the panel is tallest.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const ui = require(ReplicatedStorage.Shared.settings).ui
const METRICS = ui.METRICS
const STYLE = ui.STYLE

-- The footer block: a divider, then one row of buttons per entry in `rows`.
--
-- ONE GAP PER ROW, not one BETWEEN rows. The footer's list layout puts its
-- padding above every child after the first, and the divider is the first --
-- so N rows means N gaps (divider to row 1, then row to row), not N - 1.
function footer_height(row_count: number): number
	if row_count <= 0 then
		return 0
	end
	return row_count * (METRICS.ACTION_HEIGHT + METRICS.GAP) + STYLE.WINDOW_RULE
end

-- What the body gives up so the footer fits: the footer itself plus the ONE
-- further gap the sheet's own layout puts between the two.
--
-- Zero when there is no footer, rather than the bare divider height: a window
-- with no buttons draws no divider either, so there is nothing to reserve.
function body_offset(row_count: number): number
	if row_count <= 0 then
		return 0
	end
	return footer_height(row_count) + METRICS.GAP
end

-- The window frame's outer height, in REAL pixels, at a given point in the
-- open/shut wipe.
--
-- `title_half` is the headroom the title plate straddling the top border needs
-- and is NOT wiped -- the plate is what the player sees first, and a title that
-- grew with the sheet would read as the window inflating rather than opening.
-- `stroke` is added to the measured sheet because the sheet's border is drawn
-- inside it, so a sheet measured at its own size is one border short.
--
-- ROUNDED: the frame is clipping its contents, and a fractional height makes
-- the bottom border shimmer as the wipe runs.
function outer(title_half: number, sheet: number, stroke: number, wipe: number): number
	return title_half + math.round((sheet + stroke) * wipe)
end

return table.freeze {
	footer_height = footer_height,
	body_offset = body_offset,
	outer = outer,
}
