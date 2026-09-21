-- Every id that points at something uploaded to Roblox, as data: images,
-- sounds, meshes, fonts, animations, badges, products, passes. See the header of
-- `src/shared/settings.luau` for why the three data files exist and how they
-- are read.
--
-- WHY IDS ARE NOT IN `settings`. An id changes when an asset is re-uploaded,
-- never because the game was rebalanced, and the people who change the two are
-- different. It also makes "what does this place depend on" one file to read
-- before a publish, and one file to grep when an asset is moderated.
--
-- THE UNSET SENTINEL. An id that has not been created yet is `0` (numeric ids)
-- or `""` (content strings), never nil and never a made-up number. Services that
-- read one check for the sentinel, warn ONCE naming the key, and carry on
-- without the feature -- so a fresh game boots clean with no products, badges or
-- notification strings configured. A guessed id fails silently instead: a wrong
-- SoundId plays nothing and reports nothing.
--
-- Place ids and CollectionService tags are NOT here: they predate this file and
-- live in `src/shared/records/place-ids.luau` and `src/shared/records/tags.luau`.
function deep(t)
	for _, value in t do
		if type(value) == "table" then
			deep(value)
		end
	end
	table.freeze(t)
end

const ASSETS = {
	-- DEVELOPER PRODUCTS, by the same KEY `settings.commerce.PRODUCTS` uses.
	-- `0` means not created yet; the products record skips it.
	--
	-- Create them on the Creator Dashboard, then paste the ids here.
	products = {
		COINS_SMALL = 0,
		COINS_LARGE = 0,
	},

	-- GAME PASSES, by key. `0` means not created yet.
	--
	-- The pass service reports an unset pass as not owned and warns once.
	passes = {},

	-- BADGES, by key. `0` means not created yet.
	--
	-- The badge service skips an unset badge and warns once.
	badges = {
		-- Awarded the first time a player's data loads, by the lifecycle
		-- fan-out. An EXAMPLE, and the one badge nearly every game wants.
		WELCOME = 0,
	},

	-- EXPERIENCE NOTIFICATION STRING IDS (Creator Dashboard -> Notifications).
	-- `""` means not created yet; the reminder scheduler then stays idle.
	notifications = {
		-- Sent when a player's next daily reward comes due. A notification
		-- string is authored on the Creator Dashboard, not here -- this is only
		-- its id -- and it must declare the parameters `day` and `reward`, which
		-- is what `src/server/players/daily-reminders.luau` fills in.
		--
		-- SENDING ALSO NEEDS THE OPEN CLOUD PACKAGE in ServerScriptService
		-- (`OpenCloud.V2.UserNotification`), which is a Roblox-published model
		-- rather than anything this repo can vendor. With the id set and the
		-- package missing, the scheduler warns once and stays idle.
		DAILY_READY = "",
	},

	-- SOUNDS the cue engine plays, by cue name. `rbxasset://sounds/...` engine
	-- sounds are fine for a graybox; only some of those paths exist, and a wrong one
	-- is silent. Check `Sound.TimeLength > 0` in Studio before trusting a new id.
	sounds = {},

	-- MUSIC playlists, by name. Each is an array of content ids.
	music = {},

	-- TEXTURES the effect primitives draw with.
	textures = {},

	-- FONTS the widget kit draws with. Swapping the two entries here restyles
	-- every label in the game.
	fonts = {},

	-- ICONS, by name. Input glyphs and widget icons.
	icons = {},
}

deep(ASSETS)

return ASSETS
