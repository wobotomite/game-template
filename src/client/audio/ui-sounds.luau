const ReplicatedStorage = game:GetService "ReplicatedStorage"

const cue = require(script.Parent.cue)
const sound_groups = require(script.Parent["sound-groups"])
const sounds = require(ReplicatedStorage.Shared.assets).sounds
const MIX = require(ReplicatedStorage.Shared.settings).audio.cues.ui

-- The interface's own voice: the five noises a widget kit makes, plus the one
-- an alert makes.
--
--   const ui_sounds = require(ReplicatedStorage.Client.audio["ui-sounds"])
--   button.MouseEnter:Connect(ui_sounds.hover)
--   button.Activated:Connect(ui_sounds.click)
--
-- A MODULE OF ITS OWN, rather than each widget building a spec. Every widget
-- in the game makes the same five noises, and the moment two of them own their
-- own copy of "what a click sounds like" the interface starts sounding like
-- two interfaces. This is also the one audio surface the widget kit is allowed
-- to depend on: it takes four names and needs no idea that a cue bus exists.
--
-- WHY THESE GO THROUGH THE CUE BUS and not `play-sound`. Interface sound is
-- the densest source of cues in the game and the one most able to ruin the
-- mix: a list of thirty buttons under a moving cursor fires a hover per row,
-- and a double-click is two clicks 40ms apart. The bus's per-cue cooldowns
-- collapse both, and BACKGROUND priority means a hover is the first thing
-- dropped when something that matters needs the voice.
--
-- The mix lives in `settings.audio.cues.ui`; the ids in `assets.sounds`. Both
-- are unset in a fresh game, which is silent and says so once per cue.

type Mix = { volume: number, pitch: number, jitter: number, min_interval: number, radius: number }

-- Frozen, and built ONCE at require time. A spec is the identity the bus keys
-- its cooldowns by, so a fresh table per call would mean every click is a
-- first click and no cooldown ever applies.
const function spec(mix: Mix, name: string, id: string, priority: number): cue.Spec
	return table.freeze {
		name = name,
		id = id,
		bus = sound_groups.UI,
		volume = mix.volume,
		pitch = mix.pitch,
		jitter = mix.jitter,
		priority = priority,
		min_interval = mix.min_interval,
		radius = mix.radius,
	}
end

-- HOVER is BACKGROUND and everything else is not. A hover is a side effect of
-- the cursor moving -- the player did not ask for it -- so it is the one that
-- should lose its voice to anything else. A click is the game answering an
-- action, and a purchase is a thing the player wants confirmed.
const HOVER = spec(MIX.HOVER, "UI_HOVER", sounds.UI_HOVER, cue.PRIORITY.BACKGROUND)
const CLICK = spec(MIX.CLICK, "UI_CLICK", sounds.UI_CLICK, cue.PRIORITY.ROUTINE)
const OPEN = spec(MIX.OPEN, "UI_OPEN", sounds.UI_OPEN, cue.PRIORITY.ROUTINE)
const CLOSE = spec(MIX.CLOSE, "UI_CLOSE", sounds.UI_CLOSE, cue.PRIORITY.ROUTINE)
const PURCHASE = spec(MIX.PURCHASE, "PURCHASE", sounds.PURCHASE, cue.PRIORITY.IMPORTANT)
const ALERT = spec(MIX.ALERT, "ALERT", sounds.ALERT, cue.PRIORITY.IMPORTANT)

-- Alerts may carry their own sound -- a warning and a reward are both alerts
-- and should not sound alike -- so `alert` takes an optional id and falls back
-- to the default one.
--
-- MEMOISED, for the same reason the five above are built once: the id is the
-- identity the cooldown is keyed by, and a spec rebuilt per alert would let a
-- burst of them all sound at once. Bounded by the number of distinct alert
-- sounds a game has, which is a handful.
const custom: { [string]: cue.Spec } = {}

const function alert_spec(sound: string): cue.Spec
	local found = custom[sound]
	if found == nil then
		found = spec(MIX.ALERT, "ALERT", sound, cue.PRIORITY.IMPORTANT)
		custom[sound] = found
	end
	return found
end

-- The voice an alert service speaks with. Registered by the game rather than
-- called from here, so the alert service keeps no opinion about audio and this
-- module keeps none about alerts:
--
--   alert.set_voice(ui_sounds.alert)
function alert(sound: string?)
	if sound == nil or sound == "" then
		cue.fire(ALERT)
		return
	end
	cue.fire(alert_spec(sound))
end

return table.freeze {
	hover = function()
		cue.fire(HOVER)
	end,
	click = function()
		cue.fire(CLICK)
	end,
	open = function()
		cue.fire(OPEN)
	end,
	close = function()
		cue.fire(CLOSE)
	end,
	purchase = function()
		cue.fire(PURCHASE)
	end,
	alert = alert,
}
