const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])

-- Keeps workspace.CurrentCamera pointed at the local character, and on a
-- CameraType the player can actually look around with. OPT-IN:
--
--   require(ReplicatedStorage.Client.character["camera-attach"]).start()
--
-- YOU PROBABLY DO NOT NEED THIS. With `Players.CharacterAutoLoads` on and no
-- camera swapping, the stock PlayerModule controller binds the subject and
-- sets the type itself, every time, and this module is a watchdog for a race
-- that never happens. It is here for the moment you turn auto-loading OFF --
-- which a round-based game does on day one -- and then meet both halves below.
--
-- When a game spawns by hand -- auto-loading off, `LoadCharacter` called on a
-- timer or once a level exists -- a character regularly lands while that
-- player's client is still loading, with no camera scripts up to hear about
-- it. The engine's own CameraSubject bind
-- is missed and the camera is left floating wherever it started, following
-- nothing, while the player walks around off screen.
--
-- Nothing recovers from that on its own, and the reason is worth knowing: a
-- game's own `camera.CFrame` writes (lean, recoil, aim assist) are RELATIVE
-- rotations applied on top of whatever the stock controller wrote. With no
-- subject the controller writes nothing, so a camera that starts detached
-- stays detached for the session. Re-assert it from the client, where the
-- character is guaranteed to exist by the time this looks.

-- Fixed is the value a Camera is BORN with -- it is the zero of the enum, not
-- something anyone opts into -- and Custom is written onto it afterwards by
-- the stock PlayerModule camera controller. Same race as the missing subject
-- above: when a character lands before that controller is up (or the
-- controller re-initialises against a camera we swapped under it), the write
-- never happens and the player is left on a Fixed lens for the whole run --
-- no mouse look at all, and with LockFirstPerson on, no way out of it.
--
-- Nothing in this game ever wants Fixed, so any value that is neither Custom
-- nor the test-bot's Scriptable is treated as that stuck state and corrected.
local function repair_camera_type(camera: Camera)
	const kind = camera.CameraType
	if kind ~= Enum.CameraType.Custom and kind ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function attach(local_player: Player)
	const camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- Ahead of the health guard on purpose: spectate owns CameraSubject while
	-- you are dead but never touches CameraType, so a camera that came up
	-- Fixed leaves the death screen looking at nothing either. That is the one
	-- part of this worth fixing whether or not you are alive.
	repair_camera_type(camera)

	const character = local_player.Character
	const humanoid = character and character:FindFirstChildOfClass "Humanoid"
	-- Health guard: spectate owns the camera while you are dead and parks
	-- CameraSubject on a living teammate. Re-aiming at your own corpse from
	-- here would fight it every time the death screen cycles.
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if camera.CameraSubject ~= humanoid then
		camera.CameraSubject = humanoid
	end
	-- Only the Studio test-bot ever goes Scriptable, and it re-asserts that
	-- every frame while it drives; this just makes sure a bot run that ended
	-- badly cannot leave a player stuck behind a frozen lens. Deliberately not
	-- part of repair_camera_type: that one runs off the CameraType signal, and
	-- clearing Scriptable from there would fight the bot every frame.
	if camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- Three ways in, because any one of them can be the late one. The character:
-- a client that loaded after its own spawn never sees CharacterAdded, and
-- picks the existing character up through the observer's initial pass. The
-- camera: the engine replaces it on death, and it may not exist at all on the
-- frame this script first runs. The subject going nil: that is what a
-- destroyed character leaves behind, a camera frozen mid-air looking at
-- nothing.

local started = false
function start()
	if started then
		return
	end
	started = true

	-- The wait lives HERE, not at module scope. A RunContext=Client script runs
	-- out of ReplicatedStorage and can start before LocalPlayer is assigned --
	-- the trap local-character.luau documents -- but waiting for it at require
	-- time makes REQUIRING this module yield, and a module that yields on
	-- require is how a boot sequence loses the handler it was about to connect.
	-- The caller decides when to start; only then does anything block.
	while not Players.LocalPlayer do
		task.wait()
	end
	const local_player = Players.LocalPlayer

	observe_character(local_player, function(character: Model)
		task.spawn(function()
			-- The model can replicate a frame ahead of its Humanoid.
			if character:WaitForChild("Humanoid", 10) then
				attach(local_player)
			end
		end)
		return nil
	end)

	local camera_connections: { RBXScriptConnection } = {}

	local function watch_camera()
		for _, connection in camera_connections do
			connection:Disconnect()
		end
		table.clear(camera_connections)
		const camera = workspace.CurrentCamera
		if not camera then
			return
		end
		table.insert(
			camera_connections,
			camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
				if camera.CameraSubject == nil then
					attach(local_player)
				end
			end)
		)
		-- The controller can hand us a working camera and only drop it back to
		-- Fixed later -- on its own re-init, or when it loses the character mid
		-- respawn -- so the one-shot repair below is not enough on its own. The
		-- signal only fires on an actual change and the repair skips Scriptable,
		-- so this cannot ping-pong with the test-bot's per-frame writes.
		table.insert(
			camera_connections,
			camera:GetPropertyChangedSignal("CameraType"):Connect(function()
				repair_camera_type(camera)
			end)
		)
		attach(local_player)
	end

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch_camera)
	watch_camera()
end

return table.freeze {
	start = start,
}
