const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const observe_rig = require(ReplicatedStorage.Util.observers["observe-rig"])
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
--
-- BUILT ON `observe-rig` RATHER THAN A PAIR OF `WaitForChild` CALLS. The
-- straightforward version waits up to thirty seconds for HumanoidRootPart and
-- Humanoid and gives up if either is still missing. That is wrong in both
-- directions: a character torn down mid-spawn leaves the observer's factory
-- thread parked for half a minute, and a character that gets its parts a
-- moment after the timeout never gets a ragdoll at all -- it is simply skipped,
-- silently, and dies frozen upright. `observe-rig` re-resolves on every child
-- added, so the rig arriving late is a second callback rather than a miss.
-- The nil guard below is still needed for the FIRST callback, which routinely
-- carries an empty model: CharacterAdded fires before the parts are in it.

-- The humanoid states that mean "this body should be limp". Dead is the
-- obvious one; Physics is the state a game puts a humanoid into deliberately
-- to knock it down while it is still alive, and a knockdown that leaves the
-- rig rigid looks like a bug rather than a hit.
const LIMP_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

-- THE JOINT LIMITS are `settings.character.RAGDOLL_JOINT`, with the reasoning
-- for the three groups written beside the numbers.
const RAGDOLL_JOINT = require(ReplicatedStorage.Shared.settings).character.RAGDOLL_JOINT

-- util/ragdolls names every socket it builds after the Motor6D it stands in
-- for, behind this prefix. Matching on it rather than on `IsA` alone is what
-- keeps these limits off a BallSocketConstraint the GAME put on the character
-- for its own reasons -- a grab, a tether, a held prop.
const SOCKET_PREFIX = "ragdoll-ball-socket ->"

-- Which group a socket belongs to, read off the joint it replaced. The socket
-- is parented to that Motor6D, so the joint's name is one hop away.
function joint_limits(socket: BallSocketConstraint): (number, number)
	const motor = socket.Parent
	const name = if motor then motor.Name else ""
	-- `Root`/`RootJoint` is the R15/R6 spelling of the same joint; `Waist` is
	-- the second spine joint R15 adds.
	if name == "Root" or name == "RootJoint" or name == "Waist" then
		return RAGDOLL_JOINT.TORSO_TWIST, RAGDOLL_JOINT.TORSO_SWING
	end
	if name == "Neck" then
		-- Attachment1 is the far side of the joint. On a stock rig that is the
		-- Head, but a rig with something else up there (a helmet root, a
		-- swapped-in prop) gets the general neck figure rather than the head's
		-- tighter one -- the point of the branch is the head specifically.
		const attachment = socket.Attachment1
		const part = if attachment then attachment.Parent else nil
		const swing = if part and part.Name == "Head" then RAGDOLL_JOINT.HEAD_SWING else RAGDOLL_JOINT.NECK_SWING
		return RAGDOLL_JOINT.NECK_TWIST, swing
	end
	return RAGDOLL_JOINT.LIMB_TWIST, RAGDOLL_JOINT.LIMB_SWING
end

function limit_socket(socket: BallSocketConstraint)
	const twist, swing = joint_limits(socket)
	socket.LimitsEnabled = true
	socket.UpperAngle = swing
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -twist
	socket.TwistUpperAngle = twist
end

function is_ragdoll_socket(instance: Instance): boolean
	return instance:IsA "BallSocketConstraint" and string.sub(instance.Name, 1, #SOCKET_PREFIX) == SOCKET_PREFIX
end

function limit_joints(character: Model)
	for _, descendant in character:GetDescendants() do
		if is_ragdoll_socket(descendant) then
			limit_socket(descendant :: BallSocketConstraint)
		end
	end
end

-- Last rites for a character the observer is about to stop watching. Its
-- StateChanged connection has just been dropped, so if it is dead and still
-- standing, nothing will ever lay it down again -- it stays a rigid upright
-- corpse for as long as the model is in the world. `is_init` because a
-- character that never got that far has no ragdoll to enable, and
-- `set_ragdoll` warns rather than doing nothing when asked anyway.
function keep_ragdolled(character: Model)
	const humanoid = character:FindFirstChildOfClass "Humanoid"
	if humanoid == nil or humanoid.Health > 0 then
		return
	end
	if ragdolls.is_init(character) and not ragdolls.is_ragdolled(character) then
		ragdolls.set_ragdoll(character, true)
		limit_joints(character)
	end
end

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
		const rig = observe_rig(player)

		-- The character these three are currently bound to, or nil between
		-- bodies. Compared by identity below, which is what makes a re-publish
		-- for the SAME character (a part streaming in, an appearance load
		-- finishing) cost nothing.
		local ready: Model? = nil
		local connection: RBXScriptConnection? = nil
		local sockets: RBXScriptConnection? = nil

		const function bind(parts: observe_rig.Rig)
			const character = parts.character
			if character == ready then
				return
			end

			if connection then
				connection:Disconnect()
				connection = nil
			end
			-- Only while it is still in the world: a model already destroyed on
			-- respawn is nobody's problem.
			if ready and ready.Parent ~= nil then
				keep_ragdolled(ready)
			end
			if sockets then
				sockets:Disconnect()
				sockets = nil
			end
			ready = nil

			const humanoid = parts.humanoid
			-- The empty-model callback lands here and does nothing. The next one
			-- arrives with the parts.
			if character == nil or humanoid == nil or parts.root == nil then
				return
			end

			-- pcall'd because a rig whose joints are still streaming in can fail
			-- to produce a root weld, and an error thrown here takes the whole
			-- observer with it -- this callback is not wrapped by anything.
			const ok, err = pcall(ragdolls.init_ragdoll, character)
			if not ok then
				warn(`[ragdolls] init failed for {character:GetFullName()}: {err}`)
				return
			end
			ready = character
			limit_joints(character)

			-- SOCKETS ARE BUILT AFTER THIS POINT TOO, so limiting once is not
			-- enough. util/ragdolls re-syncs the rig on every `set_ragdoll` and
			-- sockets up any joint that has appeared since -- the appearance load
			-- replacing the Head a few hundred ms in is the routine case, and it
			-- destroys the Neck Motor6D along with it. A socket built later and
			-- never limited is a free joint in an otherwise limited body, which
			-- is worse than no limits at all: one part flails and the rest does
			-- not. Hence both this connection and the re-limit inside `apply`.
			sockets = character.DescendantAdded:Connect(function(instance: Instance)
				if is_ragdoll_socket(instance) then
					limit_socket(instance :: BallSocketConstraint)
				end
			end)

			-- `const`, not a bare `function`: a bare one is a GLOBAL, and every
			-- character observed would overwrite the last -- so one player's
			-- StateChanged would ragdoll whichever character happened to be set up
			-- most recently.
			const function apply(state: Enum.HumanoidStateType)
				const want = LIMP_STATES[state] == true
				if want ~= ragdolls.is_ragdolled(character) then
					ragdolls.set_ragdoll(character, want)
					limit_joints(character)
				end
			end

			connection = humanoid.StateChanged:Connect(
				function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
					apply(new)
				end
			)
			-- A character that is ALREADY dead by the time we get here never fires
			-- a StateChanged for it: a corpse that streams in, a player joining
			-- mid-wipe, or just the observer losing the race with the death. Read
			-- the state instead of waiting to be told about the next one.
			apply(humanoid:GetState())
		end

		-- Subscribe first, then bind what is there now: the other order drops a
		-- character that arrives in between.
		const unsubscribe = rig.changed(bind)
		bind(rig.get())

		return function()
			unsubscribe()
			rig.destroy()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if sockets then
				sockets:Disconnect()
				sockets = nil
			end
			-- Not `keep_ragdolled` here: this runs when the PLAYER leaves, and
			-- their character goes with them.
			ready = nil
		end
	end)
end

return table.freeze {
	start = start,
}
