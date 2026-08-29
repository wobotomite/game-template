const ReplicatedStorage = game:GetService "ReplicatedStorage"

const pseudo_signal = require(ReplicatedStorage.Util.events["pseudo-signal"])
const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- The applied HumanoidDescription of every player in the server, snapshotted
-- off their character as it spawns and kept until they leave. One place asks
-- the engine so nothing else has to: the gray-default window right after a
-- spawn resolves here, once, instead of in every consumer.

-- How long get_appearance_async waits before giving up. Callers treat nil as
-- "no appearance this run" and fall back (a viewmodel with no arm), so this
-- has to stay finite -- an unbounded wait would hang them forever on an
-- offline Studio run instead of letting them fall back.
const DEFAULT_TIMEOUT = 10
const POLL_INTERVAL = 0.1

-- Humanoid takes a moment to replicate under a freshly spawned character;
-- past this it never will.
const HUMANOID_TIMEOUT = 10

-- A description matching a freshly constructed one across all of these is the
-- placeholder the engine hands out before the real appearance applies: no
-- body parts, no clothing, no colours. Storing it would leave every consumer
-- dressed as the gray default for the rest of the run.
const BLANK_DESCRIPTION = Instance.new "HumanoidDescription"
const BLANK_FIELDS = table.freeze {
	"HatAccessory",
	"Face",
	"GraphicTShirt",
	"Shirt",
	"Pants",
	"Head",
	"StaticFacialAnimation",
	"Torso",
	"TorsoColor",
	"RightLeg",
	"RightArm",
	"LeftLeg",
	"LeftArm",
	"DepthScale",
	"FallAnimation",
	"BodyTypeScale",
}

local APPEARANCES: { [Player]: HumanoidDescription } = {}

-- Fires with the player whose stored description was just replaced, on every
-- spawn and every appearance load. Anything that caches something derived
-- from a description (rigs, viewmodel arms) rebuilds off this.
const on_appearance_update = pseudo_signal.new<<(Player, HumanoidDescription)>>()

-- The stored snapshot, or nil if none has been taken yet. Non-yielding, for
-- callers with nothing sensible to wait around for.
function get_appearance(plr: Player): HumanoidDescription?
	return APPEARANCES[plr]
end

-- The snapshot, waiting up to `timeout` seconds (default DEFAULT_TIMEOUT) for
-- one taken after the real appearance arrived. nil if it never does.
function get_appearance_async(plr: Player, timeout: number?): HumanoidDescription?
	const deadline = os.clock() + (timeout or DEFAULT_TIMEOUT)
	while not APPEARANCES[plr] or not plr:HasAppearanceLoaded() do
		if plr.Parent == nil or os.clock() >= deadline then
			return nil
		end
		task.wait(POLL_INTERVAL)
	end
	return APPEARANCES[plr]
end

function is_blank(desc: HumanoidDescription): boolean
	for _, field in BLANK_FIELDS do
		if (desc :: any)[field] ~= (BLANK_DESCRIPTION :: any)[field] then
			return false
		end
	end
	return true
end

-- The one way in: every path that turns up a description hands it here, so
-- the blank filter, the clone and the signal happen in exactly one place.
function store_appearance(plr: Player, desc: HumanoidDescription)
	if is_blank(desc) then
		return
	end
	const stored = desc:Clone()
	APPEARANCES[plr] = stored
	on_appearance_update:fire(plr, stored)
end

-- Yields on the character's Humanoid, so every caller spawns it rather than
-- stall the observer it is hooked to.
function extract_appearance(plr: Player, character: Model)
	const humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not humanoid or not humanoid:IsA "Humanoid" then
		return
	end
	-- The character can be replaced (death, LoadCharacter) while that wait is
	-- pending; a snapshot off the outgoing body would overwrite the new one's.
	if plr.Character ~= character then
		return
	end
	-- Throws while the engine is still applying the appearance -- the window
	-- right after a spawn or a revive.
	const ok, desc = pcall(humanoid.GetAppliedDescription, humanoid)
	if not ok or not desc then
		return
	end
	store_appearance(plr, desc)
end

observe_players(function(plr: Player): () -> ()
	const dispose = observe_character(plr, function(character: Model): (() -> ())?
		-- Applying an appearance parents its description under the character,
		-- so this catches every one that lands from here on -- the real
		-- appearance after the gray default, a later cosmetic swap -- without
		-- anything having to poll for it.
		const described = character.DescendantAdded:Connect(function(child: Instance)
			if child:IsA "HumanoidDescription" then
				store_appearance(plr, child)
			end
		end)
		-- And the spawn snapshot, for whatever was already applied by the
		-- time that hook went up.
		task.spawn(extract_appearance, plr, character)
		return function()
			described:Disconnect()
		end
	end)
	return function()
		dispose()
		APPEARANCES[plr] = nil
	end
end)

return table.freeze {
	get_appearance = get_appearance,
	get_appearance_async = get_appearance_async,
	on_appearance_update = on_appearance_update,
}
