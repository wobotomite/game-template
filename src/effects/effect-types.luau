-- Types for the effect registry. See init.luau for what the registry does and
-- README.md for how to write an entry.

type __list = typeof(script.Parent.list)

-- Generates the union of every valid effect name from the SHAPE OF THE list/
-- FOLDER, so `effects.new "boss/ground-telegrph"` is a type error rather than a
-- runtime one. A path is built the same way the runtime walk builds it --
-- nested folders joined with "/" -- so the two cannot disagree about what an
-- effect is called.
--
-- ONLY LEAVES. A grouping folder is not an effect name: the runtime walk
-- registers ModuleScripts and recurses into Folders, so a folder path resolves
-- to nothing and asserting on it is the registry's job, not a name it should
-- ever have offered.
--
-- "Leaf" is the discriminator because it is the one available here -- a node
-- with children is a folder, a node without is a module. THE LIMIT OF THAT:
-- an `init.luau` entry, which Rojo turns into a ModuleScript that HAS children,
-- would be treated as a folder and left out of the union. The runtime would
-- still register and run it; it just would not typecheck by name. Nothing in
-- this tree is written that way, and the effects spec asserts that no entry
-- directory holds both a module and children, so the day somebody does it
-- fails loudly instead of quietly narrowing the type.
--
-- NONE OF THIS IS TESTABLE OUTSIDE STUDIO. luau-lsp cannot evaluate type
-- functions and Lune has no DataModel, so this walk runs in exactly one place.
-- The spec checks the same rule against the real folder in plain Lua, which is
-- a proxy for the type and not the type itself.
--
-- IMPORTANT, AND THE REASON tests/effects.spec.luau EXISTS: luau-lsp 1.68.1
-- does not support user-defined type functions -- it reports "This syntax is
-- not supported" for these and for util/tables/const-record, which has used the
-- same feature for months. Studio's analyser does evaluate them. So this union
-- constrains names in Studio and NOT on the command line, and a union that
-- silently degrades to `string` would still typecheck every typo without
-- anything visibly breaking. Never treat this as the only check on effect
-- names; the spec verifies every `new()` call site against the real folder.
type function EffectNamesImpl()
	local names = types.unionof()

	-- Instance members that show up alongside children and are not children.
	local function is_member(name: string): boolean
		return name == "Parent"
			or name == "Name"
			or name == "ClassName"
			or name == "FindFirstChild"
			or name == "FindFirstAncestor"
			or name == "WaitForChild"
			or name == "GetChildren"
	end

	-- Does this node have children of its own? That is what separates a FOLDER
	-- from a module here: `list/boss` groups entries, `list/boss/lane` is one.
	local function has_children(current: type): boolean
		for key, prop in current:properties() do
			local name = key:value()
			if type(name) == "string" and not is_member(name) and prop.read then
				return true
			end
		end
		return false
	end

	local function walk(current: type, prefix: string)
		for key, prop in current:properties() do
			local name = key:value()
			if type(name) ~= "string" or is_member(name) or not prop.read then
				continue
			end

			local path = if prefix == "" then name else `{prefix}/{name}`
			if has_children(prop.read) then
				-- A grouping folder. Not a name; recurse for the entries in it.
				walk(prop.read, path)
			else
				names = types.unionof(names, types.singleton(path))
			end
		end
	end

	walk(__list :: type, "")

	return names
end

export type EffectName = EffectNamesImpl<>

-- Ends the effect. Safe to call more than once, and safe to call from inside
-- the effect itself.
export type Cleanup = () -> ()

-- Instances the effect was handed, by key. Binding an instance also binds the
-- effect's LIFETIME to it: when the instance leaves the DataModel the effect is
-- cleaned up, which is what stops a ghost's aura outliving the ghost.
export type Instances = { [string]: Instance }

-- Plain values the effect reads: positions, radii, colours, durations.
export type Attributes = { [string]: any }

export type InstanceGetter = <T>(key: string) -> T
export type AttributeGetter = <T>(key: string) -> T

-- What every module in list/ returns. The varargs are cleanup functions the
-- effect wants run when it ends -- disconnects, part removals, restoring
-- something it changed. Returning none is fine for an effect that fully
-- schedules its own teardown.
export type Effect = (cleanup: Cleanup, get: InstanceGetter, attr: AttributeGetter) -> ...Cleanup?

export type Handle = {
	-- Bind another instance after the fact; same lifetime rule as `instances`.
	bind: (key: string, instance: Instance) -> (),
	-- End the effect now.
	cleanup: Cleanup,
	-- True until the effect has been cleaned up.
	is_running: () -> boolean,
	-- Silences the long-running warning for an effect that is meant to persist.
	allow_long_run: () -> (),
}

return nil
