--!nocheck
-- shared/world/markers: finding tagged instances, and failing usefully when
-- they are not there.
-- Run with:
--   lune run tests/markers.spec.luau
--
-- WHY THIS EXISTS. This module has more lookup logic than anything else in the
-- tree, and every one of its functions is about the same thing: what happens
-- when the model is authored wrong. That is precisely the case nobody exercises
-- by hand, because the models in front of you are authored right.
--
-- The distinction it exists to enforce -- `require_*` fails AT the lookup naming
-- the model, the tag and the class; `optional_*` returns nil and means it --
-- only pays off when something is missing, so every case below removes,
-- mistags, or misclasses something.

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"
local Instance = roblox.Instance
local CFrame = roblox.CFrame

h.title "markers:"

local markers = env.load "ReplicatedStorage.Shared.world.markers"

local BOUNDS = "Bounds"
local SPAWN = "Spawn"
local SIGN = "Sign"

-- A model shaped like the ones this is for: tagged markers scattered at
-- different depths, untagged scenery in between.
local function build()
	local model = Instance.new "Model"

	local shell = Instance.new "Folder"
	shell.Name = "Structure"
	shell.Parent = model
	for i = 1, 5 do
		local wall = Instance.new "Part"
		wall.Name = `Wall{i}`
		wall.Parent = shell
	end

	local bounds = Instance.new "Part"
	bounds.Name = "Bounds"
	bounds:AddTag(BOUNDS)
	bounds.Parent = model

	-- Nested, and named nothing in particular: the whole point of tags is that
	-- neither its name nor its depth matters.
	local logic = Instance.new "Folder"
	logic.Name = "Logic"
	logic.Parent = model
	local nested = Instance.new "Folder"
	nested.Parent = logic

	local spawn_a = Instance.new "Attachment"
	spawn_a.Name = "somethingelse"
	spawn_a.CFrame = CFrame.new(1, 2, 3)
	spawn_a:AddTag(SPAWN)
	spawn_a.Parent = nested

	local spawn_b = Instance.new "Attachment"
	spawn_b:AddTag(SPAWN)
	spawn_b.Parent = nested

	return model, bounds
end

-- ================================= scan ==================================

do
	local model = build()
	local found = markers.scan(model, { BOUNDS, SPAWN, SIGN })

	h.equals("scan buckets the tag that is present once", #markers.all(found, BOUNDS), 1)
	h.equals("scan buckets a tag with several instances", #markers.all(found, SPAWN), 2)
	-- A tag nobody used must come back as an empty bucket, not nil: a caller
	-- iterating `all()` should not have to nil-check a tag it asked for.
	h.equals("a tag with no instances is an empty bucket", #markers.all(found, SIGN), 0)
	h.equals("first returns nil for an absent tag", markers.first(found, SIGN), nil)
end

-- ====================== require_* fails at the lookup =====================

do
	local model = build()
	local found = markers.scan(model, { BOUNDS, SIGN })

	local part = markers.require_part(found, BOUNDS, "test model")
	h.check("require_part returns the tagged part", part ~= nil and part.Name == "Bounds")

	local ok, err = pcall(function()
		return markers.require_part(found, SIGN, "test model")
	end)
	h.check("require_part throws when the tag is absent", not ok)
	-- The message is the whole reason this is not a cast. It has to name the
	-- context and the tag, or the reader is back to guessing which of forty
	-- models was authored wrong.
	h.check("the error names the context", not ok and tostring(err):find "test model" ~= nil)
	h.check("the error names the tag", not ok and tostring(err):find(SIGN) ~= nil)
end

do
	-- Present but the WRONG CLASS is a bug, not an absence. Tagging a Model
	-- where a BasePart was meant is a mis-tag, and reporting it as "not found"
	-- hides it until something downstream misbehaves for an unrelated reason.
	local model = Instance.new "Model"
	local wrong = Instance.new "Model"
	wrong.Name = "NotAPart"
	wrong:AddTag(BOUNDS)
	wrong.Parent = model

	local found = markers.scan(model, { BOUNDS })
	local ok = pcall(function()
		return markers.require_part(found, BOUNDS, "test model")
	end)
	h.check("require_part refuses a tagged instance of the wrong class", not ok)

	-- The optional form does not throw, but it must not silently answer with
	-- the wrong thing either.
	h.equals("optional_part returns nil for the wrong class", markers.optional_part(found, BOUNDS, "test"), nil)
end

-- ============================== optional_* ===============================

do
	local model = build()
	local found = markers.scan(model, { BOUNDS, SIGN })
	h.check("optional_part finds what is there", markers.optional_part(found, BOUNDS, "test") ~= nil)
	h.equals("optional_part returns nil for what is not", markers.optional_part(found, SIGN, "test"), nil)
end

-- ============================== marker CFrame =============================

do
	local model = build()
	local found = markers.scan(model, { SPAWN, BOUNDS })

	-- Attachments and BaseParts both carry a CFrame, and hand-authored content
	-- uses invisible parts where generated content uses attachments. The
	-- resolver only ever wants the CFrame, so it accepts either.
	--
	-- ONLY THE BasePart BRANCH IS EXERCISED HERE. Lune does not implement
	-- `Attachment.WorldCFrame` -- it is a computed property with no default in
	-- its database -- so reading it raises regardless of what this module does.
	-- That is a limit of the test environment, not a gap in the code, and
	-- saying which is which is the point of writing it down: the alternative is
	-- a reader assuming the attachment path is covered.
	local from_part = markers.require_marker_cf(found, BOUNDS, "test model")
	h.check("require_marker_cf reads a BasePart", from_part ~= nil)

	h.check("is_marker accepts an Attachment", markers.is_marker(markers.first(found, SPAWN)))
	h.check("is_marker accepts a BasePart", markers.is_marker(markers.first(found, BOUNDS)))
end

-- =========================== single-tag lookup ============================

do
	local model = build()
	h.check("find_in locates a tag at any depth", markers.find_in(model, SPAWN) ~= nil)
	h.equals("find_in returns nil for an absent tag", markers.find_in(model, SIGN), nil)
	h.equals("all_in collects every instance with a tag", #markers.all_in(model, SPAWN), 2)
	h.equals("all_in returns empty for an absent tag", #markers.all_in(model, SIGN), 0)

	local ok = pcall(function()
		return markers.require_part_in(model, SIGN, "test model")
	end)
	h.check("require_part_in throws for an absent tag", not ok)
end

-- ================================ authoring ==============================

do
	local host = Instance.new "Part"
	local attachment = markers.marker(host, SPAWN, CFrame.new(4, 5, 6), "Entrance")
	h.check("marker tags what it creates", attachment:HasTag(SPAWN))
	h.equals("marker parents to the host", attachment.Parent, host)
	h.equals("marker names it", attachment.Name, "Entrance")

	local plain = Instance.new "Part"
	markers.mark(plain, SIGN)
	h.check("mark tags an existing instance", plain:HasTag(SIGN))
end

h.done()
