-- TELLING A TAP ON THE WORLD FROM EVERYTHING ELSE A THUMB DOES.
--
-- On a phone the whole screen is the camera control, the left of it is the
-- movement stick, the bottom right is jump, and any of it may be a button. A
-- game that wants "tap something in the world to interact with it" therefore
-- cannot just listen for TouchEnded: most touches that end are a look, a walk,
-- a jump or a press, and firing on those is how a mobile build ends up
-- interacting with scenery every time the player turns around.
--
-- So each touch is tracked from the moment it lands and DISQUALIFIED as soon as
-- it stops looking like a tap -- it drifted, it lasted too long, it turned the
-- camera, it started on a control, another finger joined it -- and only the
-- survivors are reported. Disqualification is one-way: a touch that has been
-- cancelled never becomes a tap again, however it ends.
--
-- The second gesture is the HOLD: a finger resting on the side of the screen
-- away from the movement stick, reported as a boolean while it is down. That is
-- the mobile stand-in for a held mouse button.
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"
const GuiService = game:GetService "GuiService"
const RunService = game:GetService "RunService"

const M = require(ReplicatedStorage.Shared.settings).controls.TOUCH

-- Compared against a dot product, so the threshold is converted once here
-- rather than an `acos` per touch per frame.
const CAMERA_COS = math.cos(math.rad(M.TAP_CAMERA_DEGREES))

type Touch = {
	origin: Vector2,
	at: number,
	-- The camera the touch STARTED under, and where it was looking. A camera
	-- swap mid-touch (a cutscene, a vehicle) invalidates the comparison rather
	-- than reading as an enormous turn.
	camera: Camera?,
	look: Vector3,
	-- "world", "button", "jump" or "move": what was under the finger when it
	-- landed. Only "world" can become a tap.
	kind: string,
	right_side: boolean,
	cancelled: boolean,
}
type Listener = { allowed: () -> boolean, tap: (Vector2) -> (), reset: (() -> ())?, suspended: boolean }

const touches: { [InputObject]: Touch } = {}
const listeners: { Listener } = {}
const hold_listeners: { { allowed: () -> boolean, changed: (boolean) -> (), held: boolean } } = {}

-- Any qualifying finger holds for everyone: a second thumb landing does not
-- start a second hold, and lifting one of two does not end it.
function update_holds()
	local holding = false
	for _, touch in touches do
		if touch.kind == "world" and touch.right_side then
			holding = true
			break
		end
	end
	for _, listener in hold_listeners do
		const value = holding and listener.allowed()
		if value ~= listener.held then
			listener.held = value
			listener.changed(value)
		end
	end
end

function point(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- What is under a screen position, as far as this module cares. The Roblox
-- touch controls live in CoreGui but are mirrored into the player's own
-- PlayerGui as `TouchGui`, which is the only way a game can find out where they
-- are -- hence the ancestor test rather than a name match alone.
function ui_at(position: Vector2): string?
	const player = Players.LocalPlayer
	const gui = player and player:FindFirstChildOfClass "PlayerGui"
	if not gui then
		return nil
	end
	for _, object in gui:GetGuiObjectsAtPosition(position.X, position.Y) do
		if object:FindFirstAncestor "TouchGui" then
			if object.Name == "JumpButton" then
				return "jump"
			end
			if string.find(object.Name, "Thumbstick", 1, true) then
				return "move"
			end
		end
		-- `Active` catches the frames a panel uses to swallow input without
		-- being a button: a tap on a modal's backdrop must not reach the world
		-- behind it.
		if object:IsA "GuiButton" or object:IsA "TextBox" or object:IsA "ScrollingFrame" or object.Active then
			return "button"
		end
	end
	return nil
end

function on_right_side(position: Vector2, camera: Camera): boolean
	return position.X >= camera.ViewportSize.X * M.RIGHT_SIDE_START
end

function cancel_world()
	for _, touch in touches do
		touch.cancelled = true
	end
end

function reset()
	table.clear(touches)
	update_holds()
	for _, listener in listeners do
		if listener.reset then
			listener.reset()
		end
	end
end

-- The disqualification test, run on movement and once a frame. The CAMERA test
-- is the one that earns its keep: a flick to look around drifts only a few
-- pixels under the thumb while swinging the view through tens of degrees, so
-- the drift and duration tests alone would call it a tap.
function check(input: InputObject, touch: Touch)
	const camera = workspace.CurrentCamera
	if
		(point(input) - touch.origin).Magnitude > M.TAP_DRIFT
		or os.clock() - touch.at > M.TAP_SECONDS
		or camera ~= touch.camera
		or not camera
		or camera.CFrame.LookVector:Dot(touch.look) < CAMERA_COS
		or input.UserInputState == Enum.UserInputState.Cancel
	then
		touch.cancelled = true
	end
end

UserInputService.TouchStarted:Connect(function(input: InputObject, processed: boolean)
	const position = point(input)
	const camera = workspace.CurrentCamera
	const ui = ui_at(position)
	-- `processed` means the engine already gave this touch to a GUI. Trusted
	-- only as a fallback, because it is false for the touch controls
	-- themselves, which is exactly the case the lookup above is for.
	const kind = ui or (if processed then "button" else "world")
	-- MULTI-TOUCH CANCELS. A second finger anywhere means the player is doing
	-- something two-handed -- walking while looking, pinching -- and neither
	-- finger is a tap. Both directions: the arriving touch is born cancelled,
	-- and the ones already down are cancelled by it.
	local blocked = false
	for _, other in touches do
		if other.kind == "button" or other.kind == "jump" or (kind == "world" and other.kind == "world") then
			blocked = true
		end
	end
	if kind == "button" or kind == "jump" or blocked then
		cancel_world()
	end
	touches[input] = {
		origin = position,
		at = os.clock(),
		camera = camera,
		look = if camera then camera.CFrame.LookVector else Vector3.zero,
		kind = kind,
		-- Stamped at birth and never recomputed: a hold that began clear of the
		-- movement stick stays a hold even if the finger wanders left.
		right_side = camera ~= nil and on_right_side(position, camera),
		cancelled = blocked or kind ~= "world",
	}
	update_holds()
end)

UserInputService.TouchMoved:Connect(function(input: InputObject)
	const touch = touches[input]
	if touch then
		check(input, touch)
	end
end)

UserInputService.TouchEnded:Connect(function(input: InputObject, processed: boolean)
	const touch = touches[input]
	touches[input] = nil
	update_holds()
	if not touch or touch.kind ~= "world" then
		return
	end
	check(input, touch)
	const camera = workspace.CurrentCamera
	const position = point(input)
	-- Tested AGAIN at the end, not only at the start: a panel that opened under
	-- the finger while it was down owns the release.
	if touch.cancelled or processed or not camera or ui_at(position) ~= nil then
		return
	end
	for _, listener in listeners do
		if listener.allowed() then
			listener.tap(position)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	update_holds()
	-- Per frame as well as on movement, because duration and camera angle can
	-- both cross their thresholds while the finger is perfectly still.
	for input, touch in touches do
		if touch.kind == "world" and not touch.cancelled then
			check(input, touch)
		end
	end
	-- A listener that stops being allowed mid-gesture gets one `reset`, so a
	-- feature holding a preview can drop it the moment the player is no longer
	-- in a state to act on it.
	for _, listener in listeners do
		const suspended = not listener.allowed()
		if suspended then
			cancel_world()
			if not listener.suspended and listener.reset then
				listener.reset()
			end
		end
		listener.suspended = suspended
	end
end)

-- The four ways a touch can end without TouchEnded ever arriving. Each of them
-- otherwise leaves a finger down in `touches` forever, which blocks every
-- future tap as a phantom second touch.
UserInputService.WindowFocusReleased:Connect(reset)
GuiService.MenuOpened:Connect(reset)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(reset)
-- `Players.LocalPlayer` is nil for the first moments of a client's life, and
-- this module is required at boot. Polled in a spawned thread rather than read
-- here, where a slow machine would throw and take the whole input layer with
-- it.
task.spawn(function()
	while not Players.LocalPlayer do
		task.wait()
	end
	Players.LocalPlayer.CharacterRemoving:Connect(reset)
end)

-- `allowed` is asked on every relevant event rather than being a flag the
-- caller sets, so a listener cannot go stale: the feature answers for itself,
-- at the moment it matters.
function listen(allowed: () -> boolean, tap: (Vector2) -> (), release: (() -> ())?)
	table.insert(listeners, { allowed = allowed, tap = tap, reset = release, suspended = false })
end

-- Is the player pressing the jump control. Not otherwise knowable: it is
-- CoreGui's button, and the engine reports its press to the character
-- controller and to nobody else.
function jumping(): boolean
	for _, touch in touches do
		if touch.kind == "jump" then
			return true
		end
	end
	return false
end

return table.freeze {
	listen = listen,
	jumping = jumping,
	listen_hold = function(allowed: () -> boolean, changed: (boolean) -> ())
		table.insert(hold_listeners, { allowed = allowed, changed = changed, held = false })
	end,
}
