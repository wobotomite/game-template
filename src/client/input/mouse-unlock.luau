const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)

-- First-person locks the mouse; UIs need it back. The classic trick: an
-- invisible full-screen TextButton with Modal = true (and Active = false so
-- it sinks no input) unlocks the cursor while enabled. Any number of UIs can
-- hold the unlock; it releases when the last one closes.

-- NOT READ AT REQUIRE TIME. `Players.LocalPlayer` is nil for the first moments
-- of a client's life, and this module is required by UI modules that are
-- themselves required at boot -- so reading it here is a race that a fast
-- machine wins and a slow one loses, with the loss looking like a UI that
-- simply never appears. Resolved in the spawned poll at the bottom instead,
-- which also lets the ScreenGui be built now and parented later.
local local_player: Player? = nil

const screen = vide.create "ScreenGui" {
	Name = "MouseUnlock",
	ResetOnSpawn = false,
	Enabled = false,
	DisplayOrder = -100,

	vide.create "TextButton" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		Active = false,
		Selectable = false,
	},
}

-- `boolean`, not `true`: the removal below assigns nil, and `{ [string]: true }`
-- makes `true?` an error on the way in even though nil-to-remove is the whole
-- idiom.
const holders: { [string]: boolean } = {}

-- The cursor ICON follows the unlock. Under LockFirstPerson the mouse is pinned
-- to the middle of the screen, where the icon sits on top of the crosshair and
-- cannot click a thing -- so it is hidden while nothing holds the unlock, and
-- comes straight back the moment something does. That covers every holder at
-- once, which is the point: a UI that unlocks the mouse and then draws no
-- cursor to click with is worse than no unlock at all.
--
-- Only while the camera is locked, because a third-person game needs the cursor
-- as the ONLY way to press anything. Driven off the CameraMode signal as well
-- as set(), since whatever locks the camera does so from its own script and may
-- boot after this module is first required.
local function apply_icon()
	const player = local_player
	-- Before the poll below has resolved. The icon is applied again as soon as
	-- it does, so nothing is lost by returning here.
	if not player then
		return
	end
	const locked = player.CameraMode == Enum.CameraMode.LockFirstPerson
	UserInputService.MouseIconEnabled = not locked or screen.Enabled
end

local function set(key: string, open: boolean)
	if open then
		holders[key] = true
	else
		holders[key] = nil
	end
	screen.Enabled = next(holders) ~= nil
	apply_icon()
end

task.spawn(function()
	while not Players.LocalPlayer do
		task.wait()
	end
	const player = Players.LocalPlayer
	local_player = player
	screen.Parent = player:WaitForChild "PlayerGui"
	player:GetPropertyChangedSignal("CameraMode"):Connect(apply_icon)
	apply_icon()
end)

return table.freeze {
	set = set,
	-- Is anything holding the unlock right now. For the input layers that have
	-- to stand down while the player is working a UI -- the touch buttons stop
	-- drawing, gestures stop firing -- and which otherwise have no way to know
	-- that a cursor is what the screen is currently for.
	is_open = function(): boolean
		return next(holders) ~= nil
	end,
}
