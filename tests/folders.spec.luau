--!nocheck
-- shared/world/folders: get-or-create, and the one way it goes wrong.
-- Run with:
--   lune run tests/folders.spec.luau
--
-- WHY THIS ONE. The failure is a DUPLICATE. A builder pass that creates a
-- second `Logic` instead of reusing the first puts half the markers in one and
-- half in the other, and every lookup then finds some of what it wanted. No
-- error, no warning, and a model that looks right in the Explorer until you
-- notice two folders with the same name.
--
-- It is three lines of code, which is exactly why it is worth pinning: nobody
-- re-reads three lines.

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"

h.title "folders:"

local folders = env.load "ReplicatedStorage.Shared.world.folders"

local function children_named(parent, name: string): number
	local count = 0
	for _, child in parent:GetChildren() do
		if child.Name == name then
			count += 1
		end
	end
	return count
end

do
	local model = roblox.Instance.new "Model"
	local first = folders.logic(model)
	local second = folders.logic(model)

	h.equals("the second call returns the same folder", first, second)
	h.equals("and does not create a duplicate", children_named(model, "Logic"), 1)
	h.equals("it is a Folder", first.ClassName, "Folder")
end

do
	local model = roblox.Instance.new "Model"
	folders.logic(model)
	folders.structure(model)
	folders.deco(model)
	h.equals("the three are distinct", #model:GetChildren(), 3)
end

do
	-- A child with the right NAME and the wrong CLASS is not the folder. Reusing
	-- it would parent markers into a Part, which is legal and silently wrong;
	-- creating a second child named Logic is at least visible in the Explorer.
	local model = roblox.Instance.new "Model"
	local impostor = roblox.Instance.new "Part"
	impostor.Name = "Logic"
	impostor.Parent = model

	local folder = folders.logic(model)
	h.equals("a same-named non-Folder is not reused", folder.ClassName, "Folder")
	h.check("the impostor is left alone", impostor.Parent == model)
end

do
	-- The read side. `find_folder` must NOT create -- callers use it to ask
	-- whether a model has been dressed yet, and a get-or-create there would
	-- make the answer always yes.
	local model = roblox.Instance.new "Model"
	h.equals("find_folder returns nil when absent", folders.find_folder(model, "Deco"), nil)
	h.equals("and creates nothing", #model:GetChildren(), 0)

	folders.deco(model)
	h.check("find_folder finds it once it exists", folders.find_folder(model, "Deco") ~= nil)
end

h.done()
