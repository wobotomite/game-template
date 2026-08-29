local Players = game:GetService "Players"
local ReplicatedStorage = game:GetService "ReplicatedStorage"

local app = require(script.ui.app)
local vide = require(ReplicatedStorage.Packages.vide)
local wait_for_loaded = require(script.boot["wait-for-loaded"])

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
