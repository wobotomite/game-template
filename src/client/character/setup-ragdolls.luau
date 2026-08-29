const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const ragdolls = require(ReplicatedStorage.Util.ragdolls)

-- Every client builds and drives a ragdoll for EVERY character, its own
-- included. Nothing here is fired over the network: the humanoid state is
-- already replicated state, so all a client has to do is agree with it.
--
-- Why every client and not just the owner: the peer that owns the corpse
-- simulates it and replicates a pose PER PART, and a client whose rig still
-- has its Motor6Ds enabled is one rigid assembly that cannot hold that pose --
-- it would place the root and let the joints put the limbs back in a standing
-- T. Breaking the rig locally is what lets a watching client show the ragdoll
-- the owner is simulating. The sockets on a non-owner do no physics work; they
-- are there so the body does not fall apart if ownership ever lands here.
--
-- The other half of the contract is server-side (Server.setup-ragdolls): it
-- hands the corpse's ownership back to its player, without which none of this
-- moves a stud.
const wl = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

-- OPT-IN:
--
--   require(ReplicatedStorage.Client.character["setup-ragdolls"]).start()
--
-- BOTH HALVES ARE NEEDED. This one breaks the rig and enables the sockets; the
-- server half (Server.setup-ragdolls) turns off BreakJointsOnDeath, registers
-- the collision groups, and hands the corpse's network ownership back to its
-- player. Start one without the other and death is not a ragdoll, it is a body
-- that freezes upright -- which is exactly the symptom three separate causes
-- produced before both halves existed.
--
-- A module rather than a script that runs itself, because ragdolling on death
-- is a design decision. A template that made it for you would have to be
-- undone by every project that wanted something else.
local started = false
function start()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player): () -> ()
		return observe_character(player, function(character: Model): (() -> ())?
			-- WaitForChild with a timeout returns nil, and the casts below say
			-- otherwise -- so a character torn down mid-spawn used to reach
			-- hum.StateChanged and throw out of the observer factory, which is not
			-- pcall'd. Bail instead: no ragdoll on that character beats breaking
			-- the observer for it.
			const root = character:WaitForChild("HumanoidRootPart", 30) :: BasePart?
			const humanoid = character:WaitForChild("Humanoid", 30) :: Humanoid?
			if not root or not humanoid then
				return nil
			end
			-- Joints stream in after the character on some rigs; don't let a missing
			-- root joint kill the whole character observer.
			const ok, err = pcall(ragdolls.init_ragdoll, character)
			if not ok then
				warn(`[ragdolls] init failed for {character:GetFullName()}: {err}`)
				return nil
			end

			-- `const`, not a bare `function`: a bare one is a GLOBAL, and every
			-- character observed would overwrite the last -- so one player's
			-- StateChanged would ragdoll whichever character happened to be set up
			-- most recently.
			const function apply(state: Enum.HumanoidStateType)
				const want = wl[state] == true
				if want ~= ragdolls.is_ragdolled(character) then
					ragdolls.set_ragdoll(character, want)
				end
			end

			const connection = humanoid.StateChanged:Connect(
				function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
					apply(new)
				end
			)
			-- A character that is ALREADY dead by the time we get here never fires
			-- a StateChanged for it: a corpse that streams in, a player joining a
			-- run mid-wipe, or just the observer losing the race with the death.
			-- Read the state instead of waiting to be told about the next one.
			apply(humanoid:GetState())

			return function()
				connection:Disconnect()
			end
		end)
	end)
end

return table.freeze {
	start = start,
}
