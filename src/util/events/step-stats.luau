-- How long the last dispatch of each shared step signal took.
--
-- This exists so a captured frame hitch can be ATTRIBUTED rather than merely
-- reported. Without it, "a 300ms frame happened in room 12" is another round of
-- guessing; with it, the same line says whether the game's own per-frame Luau
-- accounted for 280ms of that or for 0.4ms of it -- which is the difference
-- between a bug in this codebase and a rendering, streaming or network stall
-- that no amount of Luau optimisation will touch.
--
-- Cost is two os.clock() reads per dispatcher per frame (~0.08us total), which
-- is why it is always on rather than behind a flag: a diagnostic you have to
-- remember to enable is not there on the frame you needed it.

const stats = {
	-- Seconds spent inside the last render-step and physics-step dispatch,
	-- i.e. running every listener connected to those signals.
	render = 0,
	physics = 0,
}

function stats.record(which: string, seconds: number)
	if which == "render" then
		stats.render = seconds
	else
		stats.physics = seconds
	end
end

return stats
