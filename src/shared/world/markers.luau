-- INSTANCE-LEVEL TAG METHODS, not CollectionService's. `x:HasTag(tag)` and
-- `CollectionService:HasTag(x, tag)` are the same operation, but the instance
-- form drops a service dependency and — the reason it is worth a note — it is
-- the one Lune implements, so everything below can be exercised headlessly by
-- tests/markers.spec. The service form cannot, which would have left the module
-- with the most lookup logic in the tree completely untested.
-- Finding and creating TAGGED MARKERS in a model.
--
--   const found = markers.scan(room, { tags.BOUNDS, tags.ENTRANCE })
--   const bounds = markers.require_part(found, tags.BOUNDS, "room 12")
--   const sign = markers.optional_part(found, tags.SIGN, "room 12")
--
-- ======================= WHY TAGS AND NOT NAMES ==========================
--
-- A tag survives what a name does not: reparenting the marker into a folder,
-- renaming it in Studio, and an author hand-building a model to the same
-- contract. None of those raise an error when they break a name lookup -- the
-- marker is simply not found.
--
-- ============================ THE CAST IS THE BUG =========================
--
-- The habit this replaces is one line:
--
--     const bounds = model:FindFirstChild "Bounds" :: BasePart
--
-- `FindFirstChild` returns `Instance?`, and the cast ASSERTS THE NIL AWAY
-- WITHOUT CHECKING ANYTHING. So a model missing its marker does not fail at
-- the lookup. It fails a page later, on whatever first indexes the nil
-- ("attempt to index nil with CFrame"), possibly inside a build running under
-- a fatal handler and taking the server with it. The error names the wrong
-- file and the stack points at the consumer rather than at the model that was
-- authored wrong.
--
-- `require_*` fails AT the lookup, naming the model, the tag, and the class it
-- expected. `optional_*` returns nil and means it, so the caller's type says so
-- and the analyzer makes them handle it.
--
-- Present but the WRONG CLASS is a bug, not an absence: a Model carrying a tag
-- meant for a BasePart means somebody tagged the wrong instance, and treating
-- that as "not there" hides the mistake until something downstream misbehaves
-- for an unrelated-looking reason.

export type Scan = { [string]: { Instance } }

-- ONE descendant walk, bucketed by tag. Resolving a room wants six different
-- markers out of a few hundred instances; six separate walks would each
-- allocate a fresh array of all of them. `wanted` is small, so the inner loop
-- is cheaper than GetTags (which allocates per descendant).
function scan(root: Instance, wanted: { string }): Scan
	const buckets: Scan = {}
	for _, tag in wanted do
		buckets[tag] = {}
	end
	for _, descendant in root:GetDescendants() do
		for _, tag in wanted do
			if descendant:HasTag(tag) then
				table.insert(buckets[tag], descendant)
			end
		end
	end
	return buckets
end

function all(found: Scan, tag: string): { Instance }
	return found[tag] or {}
end

function first(found: Scan, tag: string): Instance?
	const bucket = found[tag]
	return if bucket then bucket[1] else nil
end

-- Present but the wrong class is a BUG, not an absence. A Model carrying a tag
-- that is supposed to be on a BasePart means somebody tagged the wrong
-- instance, and silently treating that as "not there" hides the mistake until
-- something downstream behaves strangely for an unrelated-looking reason.
function optional_of(found: Scan, tag: string, class: string, context: string): Instance?
	const instance = first(found, tag)
	if not instance then
		return nil
	end
	if not instance:IsA(class) then
		warn(
			`[layout] {context}: {instance:GetFullName()} is tagged "{tag}" but is a {instance.ClassName}, not a {class}; ignoring it`
		)
		return nil
	end
	return instance
end

function require_of(found: Scan, tag: string, class: string, context: string): Instance
	const instance = first(found, tag)
	assert(instance, `{context}: nothing is tagged "{tag}" (expected one {class})`)
	assert(
		instance:IsA(class),
		`{context}: {instance:GetFullName()} is tagged "{tag}" but is a {instance.ClassName}, not a {class}`
	)
	return instance
end

function require_part(found: Scan, tag: string, context: string): BasePart
	return require_of(found, tag, "BasePart", context) :: BasePart
end

function require_attachment(found: Scan, tag: string, context: string): Attachment
	return require_of(found, tag, "Attachment", context) :: Attachment
end

-- A marker's world CFrame, whichever class carries it.
--
-- Attachments are the right contract: a docking face needs no geometry, and an
-- invisible BasePart costs collision, streaming and a draw call to hold one
-- CFrame. But hand-authored content in a place file usually predates that
-- convention and uses invisible parts. Readers only ever want the CFrame, so
-- accept both rather than forcing a migration of content somebody built by
-- hand.
function is_marker(instance: Instance): boolean
	return instance:IsA "Attachment" or instance:IsA "BasePart"
end

function marker_cf(instance: Instance): CFrame?
	if instance:IsA "Attachment" then
		return instance.WorldCFrame
	elseif instance:IsA "BasePart" then
		return instance.CFrame
	end
	return nil
end

function require_marker_cf(found: Scan, tag: string, context: string): CFrame
	const instance = first(found, tag)
	assert(instance, `{context}: nothing is tagged "{tag}" (expected an Attachment or BasePart)`)
	const cf = marker_cf(instance)
	assert(
		cf,
		`{context}: {instance:GetFullName()} is tagged "{tag}" but is a {instance.ClassName}, which carries no CFrame`
	)
	return cf :: CFrame
end

function optional_part(found: Scan, tag: string, context: string): BasePart?
	return optional_of(found, tag, "BasePart", context) :: BasePart?
end

-- ========================== single-marker lookup ==========================

-- For the one-off cases that do not want a whole scan -- a single pad, one
-- status sign.

function find_in(root: Instance, tag: string): Instance?
	for _, descendant in root:GetDescendants() do
		if descendant:HasTag(tag) then
			return descendant
		end
	end
	return nil
end

function find_part_in(root: Instance, tag: string): BasePart?
	const found = find_in(root, tag)
	return if found and found:IsA "BasePart" then found else nil
end

function require_in(root: Instance, tag: string, class: string, context: string): Instance
	const found = find_in(root, tag)
	assert(found, `{context}: nothing under {root:GetFullName()} is tagged "{tag}" (expected one {class})`)
	assert(
		found:IsA(class),
		`{context}: {found:GetFullName()} is tagged "{tag}" but is a {found.ClassName}, not a {class}`
	)
	return found
end

function require_part_in(root: Instance, tag: string, context: string): BasePart
	return require_in(root, tag, "BasePart", context) :: BasePart
end

-- Every tagged descendant of `root`. For the cases where the count matters
-- rather than the first hit -- spawn points, interactables, props.
function all_in(root: Instance, tag: string): { Instance }
	const found: { Instance } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:HasTag(tag) then
			table.insert(found, descendant)
		end
	end
	return found
end

-- =============================== authoring ================================

-- Tag as you build, so a builder pass reads as one statement per marker rather
-- than a create and a tag that can drift apart.
function mark(instance: Instance, tag: string): Instance
	instance:AddTag(tag)
	return instance
end

-- A pure CFrame marker: an Attachment on `host`, tagged, positioned in the
-- host's local space. Entrances, exits and spawn points are all this.
function marker(host: BasePart, tag: string, cf: CFrame, name: string?): Attachment
	const attachment = Instance.new "Attachment"
	attachment.Name = name or tag
	attachment.CFrame = cf
	attachment.Parent = host
	attachment:AddTag(tag)
	return attachment
end

return table.freeze {
	scan = scan,
	all = all,
	first = first,
	optional_of = optional_of,
	require_of = require_of,
	require_part = require_part,
	require_attachment = require_attachment,
	optional_part = optional_part,
	is_marker = is_marker,
	marker_cf = marker_cf,
	require_marker_cf = require_marker_cf,

	find_in = find_in,
	find_part_in = find_part_in,
	require_in = require_in,
	require_part_in = require_part_in,
	all_in = all_in,

	mark = mark,
	marker = marker,
}
