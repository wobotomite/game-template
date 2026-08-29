-- Pure timing math for the anticheat. No Roblox APIs so lune can exercise
-- it headless (tests/anticheat-heuristics.spec.luau).

export type IntervalStats = {
	count: number, -- number of intervals (events - 1)
	mean: number,
	cv: number, -- coefficient of variation: std / mean
}

export type MetronomeConfig = {
	min_events: number, -- events needed before a verdict is possible
	max_cv: number, -- below this the cadence is inhumanly regular
	min_mean: number, -- ignore cadences faster than this (limiter territory)
	max_mean: number, -- ignore cadences slower than this (not farming)
}

function interval_stats(times: { number }): IntervalStats?
	const n = #times - 1
	if n < 1 then
		return nil
	end
	local sum = 0
	for i = 1, n do
		sum += times[i + 1] - times[i]
	end
	const mean = sum / n
	if mean <= 0 then
		return nil
	end
	local variance = 0
	for i = 1, n do
		const deviation = (times[i + 1] - times[i]) - mean
		variance += deviation * deviation
	end
	variance /= n
	return { count = n, mean = mean, cv = math.sqrt(variance) / mean }
end

-- True when `times` (ascending event timestamps) look machine-generated:
-- enough of them, at a plausible farming cadence, with near-zero variance.
-- Human clicking bottoms out around cv 0.05 even when a client-side cooldown
-- gate quantizes mashing; timer-driven macros land under 0.01 plus network
-- jitter.
function is_metronomic(times: { number }, config: MetronomeConfig): boolean
	if #times < config.min_events then
		return false
	end
	const stats = interval_stats(times)
	if not stats then
		return false
	end
	return stats.mean >= config.min_mean and stats.mean <= config.max_mean and stats.cv <= config.max_cv
end

return table.freeze {
	interval_stats = interval_stats,
	is_metronomic = is_metronomic,
}
