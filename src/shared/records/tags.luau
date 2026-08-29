-- CollectionService tag names and instance names that are CONTRACTS between
-- code that writes them and code that reads them -- usually across the
-- client/server boundary, where nothing checks that the two agree.
--
-- The point of the record is that a typo becomes a nil index at require time
-- instead of a feature that quietly stops working. A server that tags a light
-- `FlickerLight` and a client that scans for `FlickerLights` produce no error,
-- no warning, and no flickering lights.
--
-- Read tagged instances with CollectionService, never with FindFirstChild: a
-- tag survives renaming, reparenting into a folder, and being authored by hand
-- in Studio.
--
-- Add your game's tags here. The ones below are the template's own, referenced
-- by util modules that ship with it.

return table.freeze {
	-- ========================= util-owned contracts =======================

	-- util/extra-features/change-lighting skips any instance carrying this
	-- tag, so a light or effect that a feature owns outright is not stomped
	-- by a mood swap.
	LIGHTING_ENGINE_IGNORE = "LightingEngineIgnore",

	-- ============================ model layout ============================

	-- A convention worth keeping: every model a game builds or ships splits
	-- into these three folders, so what a script may touch is obvious from the
	-- Explorer alone.
	--   Logic      contracts -- markers, bounds, spawns, interactables.
	--              Tagged, and read through CollectionService.
	--   Structure  the shell -- floor, walls, ceiling. Collision and streaming
	--              weight; no script reads it.
	--   Deco       cosmetic only, and never load-bearing (a client that builds
	--              its own dressing leaves this empty on the server).
	LOGIC_FOLDER = "Logic",
	STRUCTURE_FOLDER = "Structure",
	DECO_FOLDER = "Deco",
}
