-- PLACEHOLDER. The widget kit clicks, hovers and opens; this is the module it
-- calls to make a noise about it, stubbed to four no-ops so the kit can ship
-- and boot before the audio layer exists.
--
-- FOR THE INTEGRATOR: replace this whole file with the real `ui-sounds` from
-- the audio lane at merge. The real one routes each of these through the cue
-- engine and the UI sound bus; it exports at least these four names with these
-- signatures, so nothing in `src/client/ui` or `src/client/input` changes.
--
-- WHY A STUB AND NOT A NIL CHECK. The alternative is every button in the kit
-- guarding its own `if ui_sounds then`, which is four branches per widget that
-- are dead the moment audio lands, and one of them is always the one that gets
-- forgotten. A silent module is the same behaviour in one place.
return table.freeze {
	-- The pointer entered a control. Quietest of the four: it fires on
	-- movement, not on intent.
	hover = function() end,
	-- A control was activated.
	click = function() end,
	-- A menu was opened, and the one below closed it again. Called by
	-- `src/client/ui/menu-state` when the open-menu count leaves zero, not by
	-- each panel, so nesting panels does not stack the sound.
	open = function() end,
	close = function() end,
}
