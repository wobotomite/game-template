-- IS THE PLAYER ACTUALLY AT THE CONTROLS, and what are they holding.
--
-- Every input layer needs the same two answers before it acts: is this client
-- in a state where a keypress means what it looks like, and which device should
-- the on-screen hints be drawn for. Asking the engine directly at each call
-- site gets it subtly wrong -- `UserInputService.PreferredInput` read once at
-- require time never updates, and the three ways a player can be "in the game
-- but not playing it" are easy to remember only two of.
--
-- SOURCES, not getters, so a UI can bind to them: a hotkey badge redraws itself
-- when a pad is plugged in without anyone polling for it.
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"
const GuiService = game:GetService "GuiService"

const vide = require(ReplicatedStorage.Packages.vide)
const menu = require(ReplicatedStorage.Client.ui["menu-state"])

-- Keyboard, Gamepad or Touch, as the ENGINE judges it -- which is not the same
-- as what hardware is attached. A player with a pad plugged in who is typing on
-- the keyboard prefers Keyboard, and the hints should follow their hands.
const preferred = vide.source(UserInputService.PreferredInput)
-- Optimistic at boot. `WindowFocused` only fires on a change, so a client that
-- starts focused (the normal case) would otherwise be treated as alt-tabbed
-- until the player clicked away and back.
const focused = vide.source(true)
const typing = vide.source(UserInputService:GetFocusedTextBox() ~= nil)
const core_menu = vide.source(GuiService.MenuIsOpen)

UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	preferred(UserInputService.PreferredInput)
end)
UserInputService.WindowFocused:Connect(function()
	focused(true)
end)
UserInputService.WindowFocusReleased:Connect(function()
	focused(false)
end)
UserInputService.TextBoxFocused:Connect(function()
	typing(true)
end)
UserInputService.TextBoxFocusReleased:Connect(function()
	typing(false)
end)
GuiService.MenuOpened:Connect(function()
	core_menu(true)
end)
GuiService.MenuClosed:Connect(function()
	core_menu(false)
end)

-- The three ways a keypress does not belong to the game. Typing is the one that
-- bites: without it, every letter of a chat message or a text field also fires
-- whatever hotkey shares it. The Roblox escape menu is the same problem with
-- the controller, and an unfocused window still receives input events on some
-- platforms.
function available(): boolean
	return focused() and not typing() and not core_menu()
end

return table.freeze {
	preferred = preferred,
	available = available,
	-- Stricter: input meant for the WORLD rather than for a UI. No menu open,
	-- and a living character to act with -- otherwise a held key keeps firing
	-- at a corpse, and the action the player takes on respawn is the one they
	-- were pressing when they died.
	gameplay = function(): boolean
		const player = Players.LocalPlayer
		const character = player and player.Character
		const humanoid = character and character:FindFirstChildOfClass "Humanoid"
		return available() and menu.state() == "none" and humanoid ~= nil and humanoid.Health > 0
	end,
}
