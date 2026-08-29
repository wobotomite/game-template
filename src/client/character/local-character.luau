const Players = game:GetService "Players"

-- The local character's root part, or nil while they are dead, still loading,
-- or the module was required before LocalPlayer existed. Three run scripts had
-- their own copy of this four-liner under two different names
-- (`character_root`, `local_root`).
--
-- LocalPlayer is read on each call rather than captured at require time: a
-- module pulled in early enough would otherwise cache nil forever. Callers are
-- per-frame code that simply skips a frame when there is no character, so this
-- returns nil rather than erroring.
return table.freeze {
	root = function(): BasePart?
		const player = Players.LocalPlayer
		const character = player and player.Character
		return character and character:FindFirstChild "HumanoidRootPart" :: BasePart?
	end,
}
