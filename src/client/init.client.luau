const Players = game:GetService "Players"
const ReplicatedFirst = game:GetService "ReplicatedFirst"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const alert = require(ReplicatedStorage.Shared.services.alert)
const app = require(script.ui.app)
const vide = require(ReplicatedStorage.Packages.vide)
const preload = require(script.boot.preload)
const wait_for_loaded = require(script.boot["wait-for-loaded"])
const ui_sounds = require(script.audio["ui-sounds"])
const assets = require(ReplicatedStorage.Shared.assets)
const TRANSITION = require(ReplicatedStorage.Shared.settings).transition

-- THE CLIENT'S WHOLE BOOT, in order, and the order is the point. Every step
-- here waits on the one before it for a reason that is invisible in Studio,
-- where all of them finish in the same breath.

-- ================================ preload =================================

-- Collect every id in `assets` into one flat list of content strings.
--
-- RECURSIVE, because the asset tables are not one shape: `sounds` is a flat
-- map of name to id, `music` is a playlist (an array of ids) per name, and a
-- game adds sections of its own in whatever shape suits them. A collector that
-- understood only the flat case would silently skip the playlists, which is
-- exactly the kind of miss that reads as "the music starts late sometimes".
--
-- EMPTY STRINGS ARE SKIPPED. `""` is the unset sentinel in `assets` -- an id
-- that has not been created yet -- and the preloader warns once per asset that
-- fails to resolve. That warn exists to report an id that is DEAD, and a fresh
-- template with nothing uploaded would bury it under one line per stub.
const function gather(source: { [any]: any }, into: { string })
	for _, value in source do
		if type(value) == "table" then
			gather(value, into)
		elseif type(value) == "string" and value ~= "" then
			table.insert(into, value)
		end
	end
end

const images: { string } = {}
gather(assets.textures, images)
gather(assets.icons, images)

const cues: { string } = {}
gather(assets.sounds, cues)

const music: { string } = {}
gather(assets.music, music)

-- ALERTS GET THEIR VOICE before anything can raise one. `alert` is shared with
-- the server and cannot require client audio itself, so it takes the function.
alert.set_voice(ui_sounds.alert)

-- STARTED FIRST AND NOT WAITED ON. `start` returns immediately and warms on its
-- own thread, so the whole pass overlaps the data sync and the spawn below
-- instead of running after them. Nothing here blocks on `preload.finished()`: a
-- player who is in and has a body should be playing, and an asset that has not
-- arrived yet streams in on demand -- which is worse than preloaded and far
-- better than a loading screen held open for a music bed.
preload.start {
	content = images,
	sounds = cues,
	heavy_sounds = music,
}

-- =========================== the gate, then the UI ==========================

-- NOTHING ON SCREEN UNTIL THE PLAYER IS ACTUALLY IN. `wait_for_loaded` blocks
-- until saved data has synced down and a character exists.
--
-- Mounting before that is the default and it is wrong in a way that is easy to
-- miss in Studio, where both arrive almost instantly: every screen renders once
-- from nil, so a currency counter shows 0 and an inventory shows empty, then
-- both correct themselves a beat later. On a real connection that beat is long
-- enough to read.
wait_for_loaded()

vide.mount(app, Players.LocalPlayer:WaitForChild("PlayerGui", math.huge))

-- ============================== the hand-off ================================

-- LAST, AND ONLY AFTER THE MOUNT. This is what takes down the ReplicatedFirst
-- loading cover (`src/replicated-first/loading-cover.client.luau`). Dismissing
-- it before the mount would show a frame of bare game between the cover fading
-- and the first panel appearing, which is the seam the cover exists to hide.
--
-- An attribute on the service rather than a shared module, because the two
-- scripts genuinely cannot share one: the cover reads its data through a SECOND
-- mount of the shared files into ReplicatedFirst, so a module required from
-- there and the same module required from here are different objects with equal
-- contents. What crosses that boundary safely is exactly what is crossing it
-- here -- a string, compared by value.
ReplicatedFirst:SetAttribute(TRANSITION.DISMISS_ATTRIBUTE, true)
