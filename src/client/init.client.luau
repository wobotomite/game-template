local Players = game:GetService "Players"
local ReplicatedStorage = game:GetService "ReplicatedStorage"

local app = require(script.ui.app)
local vide = require(ReplicatedStorage.Packages.vide)

vide.mount(app, Players.LocalPlayer:WaitForChild("PlayerGui", math.huge))

print "Hello world, from client!"
