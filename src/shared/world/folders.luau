const tags = require(script.Parent.Parent.records.tags)

-- The three folders every model splits into, and the only safe way to make
-- them.
--
--   Logic      contracts -- markers, bounds, spawns, interactables. Tagged,
--              and read through `world/markers`.
--   Structure  the shell -- floor, walls, ceiling. Collision and streaming
--              weight; no script reads it.
--   Deco       cosmetic only, and never load-bearing (a client that builds its
--              own dressing leaves this empty on the server).
--
-- The point is that what a script may touch is obvious from the Explorer
-- alone. The split is by CONCERN and it NESTS: a sub-model that is a thing in
-- its own right carries its own three.
--
-- Get-or-create, so a builder pass never has to know whether it is the first
-- one to want a folder.

-- Get-or-create. Builders call this in any order; readers use `find_folder`.
function folder(parent: Instance, name: string): Folder
	const existing = parent:FindFirstChild(name)
	if existing and existing:IsA "Folder" then
		return existing
	end
	const created = Instance.new "Folder"
	created.Name = name
	created.Parent = parent
	return created
end

-- Read side: nil when the model has no such folder (a hand-authored template
-- with nothing cosmetic in it, or a room whose Deco is still client-pending).
function find_folder(parent: Instance, name: string): Folder?
	const existing = parent:FindFirstChild(name)
	return if existing and existing:IsA "Folder" then existing else nil
end

function logic(model: Instance): Folder
	return folder(model, tags.LOGIC_FOLDER)
end

function structure(model: Instance): Folder
	return folder(model, tags.STRUCTURE_FOLDER)
end

function deco(model: Instance): Folder
	return folder(model, tags.DECO_FOLDER)
end

return table.freeze {
	folder = folder,
	find_folder = find_folder,
	logic = logic,
	structure = structure,
	deco = deco,
}
