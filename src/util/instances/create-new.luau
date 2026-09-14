--!nonstrict
-- `Instance.new` taking a property table, with the property names CHECKED
-- against the real class.
--
--   const part = create("Part", {
--       Size = Vector3.one,
--       Anchored = true,
--       Parent = workspace,
--   })
--
-- `Sixe = Vector3.one` is a type error in Studio, and so is `Mass = 5` (that
-- one is read-only). The class name picks the return type too, so this is a
-- `Part` and not an `Instance`. NONE of that checking exists on the command
-- line -- see THE TYPE SIDE below for why, and for what to do about it.
--
-- ===================== WHEN TO USE THIS, AND WHEN NOT =====================
--
-- USE IT when the properties arrive as DATA -- a table built by a caller,
-- merged from defaults, or driven by config. That is the case this exists for,
-- and `util/instances/make-display-part` is the example: it merges four inert
-- defaults over whatever the caller passed.
--
-- DO NOT convert straight-line construction to this. It looks like an
-- improvement and it is a downgrade, measured:
--
--     const part = Instance.new "Part"
--     part.Sixe = Vector3.one     --> luau-lsp: Key 'Sixe' not found in
--                                     external type 'Part'
--
-- `Instance.new "Part"` already returns a typed `Part`, so every property write
-- after it is checked ON THE COMMAND LINE, where this module's type function is
-- not checked at all (see THE TYPE SIDE). Rewriting those sites as `create`
-- calls would trade a check that runs in CI for one that only runs in Studio,
-- and add a require to each file for the privilege. Roughly ten sites in this
-- tree look like candidates; none of them is one.
--
-- The one thing this catches that a direct write does not: assigning a
-- READ-ONLY property. `part.Mass = 5` passes luau-lsp silently, while
-- `create("Part", { Mass = 5 })` is an error, because `prop.write` prunes them.
-- That is not worth a rewrite on its own.
--
-- ======================== HOW THE FAST PATH WORKS =========================
--
-- Writing a property the normal way goes through the Instance metatable's
-- `__newindex`, which resolves the name and dispatches. The C function it
-- dispatches TO is not exposed anywhere -- except in a traceback. So: write to
-- a property that cannot exist, catch it, and ask `debug.info(2, "f")` for the
-- function one frame up, which is the setter itself. Calling it directly skips
-- the metatable lookup on every write.
--
-- It gives up no safety. The extracted function still validates: called with a
-- name the class does not have it raises "X is not a valid member of Y", the
-- same as the assignment would have. Verified in both environments.
--
-- IT IS A SMALL WIN, and the number is here so nobody has to re-lit it.
-- Measured in Studio -- 7 interleaved rounds, warmed, alternating values so
-- Roblox's unchanged-assignment short-circuit cannot flatter either side:
--
--     plain  instance[k] = v    90.4 ns/write (median)
--     set_property(...)         85.8 ns/write (median)
--
-- 5% on the write, which is 23 ns across a five-property instance, against the
-- 12.9us it costs to parent that instance into the workspace -- so about 0.2%
-- of one create. Worth keeping because it is free once resolved at load, not
-- because it is fast. Do not reach for this trick anywhere it would cost
-- clarity. (An earlier version of this comment implied a real speedup with no
-- measurement behind it; the constant-key benchmark that seems to show the
-- opposite is measuring Luau's inline cache for a literal index, which the real
-- loop -- keys from table iteration -- never gets.)
--
-- NO FALLBACK, AND NONE IS NEEDED. This is unconditional because the probe
-- always yields the setter -- on Roblox, and also under Lune, where the
-- stand-in Instance raises on an unknown write exactly like the real one and
-- hands back a genuine C function (`debug.info(probed, "sl")` reports `[C]`,
-- and it sets Name/Anchored/Size correctly while still rejecting bogus names).
-- An earlier version of this file carried a fallback branch justified by the
-- claim that Lune "accepts unknown properties silently". That claim was never
-- true; it was asserted rather than measured, and it bought a branch nothing
-- ever took.
--
-- The one way this trick degrades is worth naming, because it degrades
-- QUIETLY: if the probe target does not exist, indexing nil throws too, and
-- `debug.info(2, "f")` then hands back the enclosing Lua closure instead of the
-- C setter -- a function, so a `typeof` check would pass it -- and every write
-- afterwards re-runs the probe. Hence a freshly constructed Part rather than a
-- global like `workspace`: it is guaranteed to exist wherever `Instance` does.
-- `debug.info(set_property, "sl")` returning `[C]` is the discriminator if this
-- ever needs checking again.

const set_property = select(
	2,
	xpcall(function()
		-- A name no class will ever have; the write always throws.
		(Instance.new "Part" :: any)["__ignore_me_i_do_not_exist__"] = nil
	end, function()
		return debug.info(2, "f")
	end)
) :: (Instance, string, any) -> ()

-- ============================ THE TYPE SIDE ==============================

-- Class name -> the instance type it builds.
--
-- THIS TABLE IS THE WHOLE TRICK. A type function cannot turn the string "Part"
-- into the type `Part` -- `types` knows the primitives and nothing else, and
-- there is no lookup from a name to a Roblox class. But a table type mapping
-- one to the other is something the ANALYSER already understands, and the
-- built-in `index<Creatable, Class>` does the lookup without a type function
-- being involved at all. From there the class type carries its own property
-- list, so nothing has to be described twice.
--
-- WHY NOT ReflectionService, which an earlier version of this file used. It
-- works, and it is where the numbers in the friction log came from -- but only
-- at RUNTIME. Type functions run in a sandboxed VM whose allowlist is
-- assert/error/print, the pcall family, math/table/string/bit32/utf8/buffer and
-- `types`; host APIs are not in it, so `game` is nil in there and every lookup
-- fell through to the permissive fallback. The checking was inert, and inert in
-- the way that looks exactly like working. This approach needs no host access
-- at all, which is why it is not merely nicer but the only one of the two that
-- can run.
--
-- ADDING A CLASS IS ONE LINE. Anything not listed degrades to
-- `{ [string]: any }` -- unchecked, not broken -- so a missing entry costs that
-- one call site its checking and nothing else. These are the classes the two
-- trees actually construct.
type Creatable = {
	Animator: Animator,
	Attachment: Attachment,
	BallSocketConstraint: BallSocketConstraint,
	Beam: Beam,
	BindableEvent: BindableEvent,
	BloomEffect: BloomEffect,
	BlurEffect: BlurEffect,
	Camera: Camera,
	CanvasGroup: CanvasGroup,
	ColorCorrectionEffect: ColorCorrectionEffect,
	DepthOfFieldEffect: DepthOfFieldEffect,
	Fire: Fire,
	Folder: Folder,
	Frame: Frame,
	Highlight: Highlight,
	HumanoidDescription: HumanoidDescription,
	ImageLabel: ImageLabel,
	InputAction: InputAction,
	InputBinding: InputBinding,
	InputContext: InputContext,
	Model: Model,
	Motor6D: Motor6D,
	Part: Part,
	ParticleEmitter: ParticleEmitter,
	PointLight: PointLight,
	ProximityPrompt: ProximityPrompt,
	RigidConstraint: RigidConstraint,
	ScreenGui: ScreenGui,
	ScrollingFrame: ScrollingFrame,
	Smoke: Smoke,
	Sound: Sound,
	SoundGroup: SoundGroup,
	SpawnLocation: SpawnLocation,
	SpecialMesh: SpecialMesh,
	SpotLight: SpotLight,
	SurfaceGui: SurfaceGui,
	TeleportOptions: TeleportOptions,
	TextBox: TextBox,
	TextButton: TextButton,
	TextChatCommand: TextChatCommand,
	TextLabel: TextLabel,
	Tool: Tool,
	Trail: Trail,
	UICorner: UICorner,
	UIFlexItem: UIFlexItem,
	UIGradient: UIGradient,
	UIListLayout: UIListLayout,
	UIPadding: UIPadding,
	UIScale: UIScale,
	UIShadow: UIShadow,
	UIStroke: UIStroke,
	UITextSizeConstraint: UITextSizeConstraint,
	ViewportFrame: ViewportFrame,
	Weld: Weld,
	WireframeHandleAdornment: WireframeHandleAdornment,
	WorldModel: WorldModel,
}

-- The writable properties of an instance type, all optional, as a table type.
--
-- MODELLED ON vide's own `create`, which solves exactly this problem and has
-- shipped for longer than anything here -- see
-- `roblox_packages/.pesde/centau_vide@0.4.1/vide/src/create.luau`. Three things
-- were wrong before I read it, and all three are the kind that produce
-- `*error-type*` on every property rather than a clean failure:
--
--   * `types.optional(t)` is the API for "or nil". Building it by hand as
--     `types.unionof(t, types.singleton(nil))` throws, because `singleton`
--     takes a string or a boolean -- and a type function that throws poisons
--     every type it produces, which is what "everything is error-type" looks
--     like.
--   * `setproperty(key, ...)` takes the key TYPE straight from the iteration.
--     Rebuilding it with `types.singleton(name)` was an unnecessary round trip.
--   * This takes the INSTANCE TYPE, not the class name. The name-to-type lookup
--     belongs in the type alias below, where the built-in `index` does it. That
--     removes the `:value()` call entirely -- and with it the dependence on the
--     solver keeping `"Part"` a singleton inside the type function, which is one
--     less thing that can silently degrade.
--
-- `prop.write` is the filter: no write type means read-only, which covers
-- `Mass`, `ClassName` and every method, since a method is a read-only
-- function-typed member. `readparent()` walks up, because `Part` itself
-- declares almost nothing -- `Name`, `Parent`, `Size` and `CFrame` all live on
-- BasePart and Instance above it.
--
-- STILL NOT CHECKED ON THE COMMAND LINE. luau-lsp does not implement
-- user-defined type functions -- it reports "This syntax is not supported" and
-- renders every type they produce as `*error-type*`. That is not specific to
-- this module: vide's `create` gets the same treatment, and so does
-- `util/tables/const-record`. Only Studio evaluates these. A property table
-- showing as `*error-type*` in an editor is the expected luau-lsp result and
-- says nothing about whether the checking works in Studio.
-- ENUM PROPERTIES ARE WIDENED TO `EnumItem | string`, so a call site may pass
-- the enum's NAME:
--
--   create("Part", { Material = "Neon" })              -- accepted
--   create("Part", { Material = Enum.Material.Neon })  -- also accepted
--
-- The engine already takes either at runtime -- assigning a string to an
-- Enum-typed property resolves it by name and raises on a name no enum has --
-- so the narrow type was rejecting something that works. It cost the most on
-- property tables built from DATA, which is the case this module exists for: a
-- config table cannot hold an `Enum.Material`, so every such site had to
-- convert by hand or cast, and one cast there discards the checking on all the
-- OTHER keys too.
--
-- WHAT IT GIVES UP, SAID PLAINLY: a misspelled enum name is no longer a type
-- error, because the widened type accepts any string. It fails at the write
-- instead, loudly and with the property named. That is a worse check than
-- before for the one case, and a better one than the cast it replaces.
--
-- `probe` wraps every `types` call the enum test makes, and that is not
-- defensive padding: a type function that THROWS renders everything it produces
-- as `*error-type*`, so one unexpected shape in the reflection data would take
-- the whole property table down -- indistinguishable, from the editor, from the
-- checking simply not working. `is_enum` walks parents rather than comparing
-- against one type because the individual enum types sit beneath a shared
-- `EnumItem` ancestor, and the 16-step bound is a cycle guard: a malformed
-- chain would otherwise spin inside the analyser with nothing to interrupt it.
type function PropertiesOfInstance(instance: type?)
	const properties = types.newtable()

	const function probe(fn): any
		const ok, result = pcall(fn)
		return if ok then result else nil
	end

	const function is_enum(t): boolean
		local node = t
		for _ = 1, 16 do
			if node == nil then
				return false
			end
			if probe(function()
				return node:name()
			end) == "EnumItem" then
				return true
			end
			node = probe(function()
				return node:parent()
			end)
		end
		return false
	end

	while instance do
		for key, prop in instance:properties() do
			if prop.write then
				local write = prop.write
				if is_enum(write) then
					const widened = probe(function()
						return types.unionof(write, types.string)
					end)
					if widened ~= nil then
						write = widened
					end
				end
				properties:setproperty(key, types.optional(write))
			end
		end
		instance = instance:readparent()
	end

	return properties
end

-- The properties accepted by a class: `Properties<"Part">`.
export type Properties<Class> = PropertiesOfInstance<index<Creatable, Class>>

-- What `create` hands back, so `create("Part", ...)` is a `Part` and not a bare
-- `Instance` and callers stop casting.
export type Created<Class> = index<Creatable, Class>

-- ============================== the builder ==============================

-- PARENT IS WRITTEN LAST, and synchronously.
--
-- Last, because parenting is what makes an instance visible to replication,
-- streaming and every `ChildAdded` listener in the tree. Doing it after every
-- other property means none of them ever sees a half-built instance -- the
-- "build detached, insert once" rule, which is worth real time: parenting into
-- a live workspace is 12.9us against 0.6us into a detached folder.
--
-- SYNCHRONOUSLY, because the `task.defer` this used to do was not worth its
-- cost. Measured in Studio, timing the loop AND the queue drain -- both
-- variants measured identically so the shared per-frame idle cancels out of the
-- difference:
--
--     Parent deferred      15.56 us/instance
--     Parent last, sync    14.99 us/instance
--     deferring costs      +0.57 us  (+3.8%)
--
-- THE BENCHMARK TRAP HERE IS WORTH KNOWING, because the naive version of it
-- says deferral is six times FASTER. Read the clock before the queue drains and
-- the deferred variant reads 1.93us against 13.77us -- but that is not work
-- avoided, it is work that has not happened yet. The 12.9us parent write still
-- lands, in the same frame, a few resumption points later. Deferring reorders
-- work within a frame; it never removes it, and it cannot help a frame budget.
-- (The raw queue cost is too noisy to quote on its own -- 1900 / 2119 / 1152 ns
-- per call at batch sizes 100 / 1000 / 8000. The end-to-end number above is the
-- one to trust.)
--
-- The stronger argument is correctness, and it would hold even if the timing
-- were a wash. A deferred parent write means the instance is NOT parented when
-- `create` returns, so anything destroying or re-parenting it in the same frame
-- races the write -- and `make-display-part` had grown a whole hold-Parent-back
-- dance specifically to dodge exactly that. Both are gone.
@native
local function create(class: string, properties: { [string]: any }?): any
	const instance = Instance.new(class :: any)
	if properties then
		local parent: Instance? = nil
		for property, value in properties do
			if property == "Parent" then
				parent = value
			else
				set_property(instance, property, value)
			end
		end
		if parent then
			set_property(instance, "Parent", parent)
		end
	end
	return instance
end

-- THE TYPED SIGNATURE IS ASCRIBED RATHER THAN WRITTEN ON THE FUNCTION, which is
-- how vide does it and is worth copying rather than reinventing: the
-- implementation stays plainly typed (`string`, a loose table) so the body needs
-- no casts, and the generic machinery lives in one place where it can be read.
--
-- `Class | keyof<Creatable>` is vide's form. The union is what keeps `"Part"` a
-- singleton instead of widening it to `string` -- and `Class` staying narrow is
-- the entire load-bearing requirement, because `index<Creatable, Class>` on a
-- widened `string` resolves to nothing useful and every property goes
-- unchecked. A class name that is not in the map fails at `index` instead.
type Create = <Class>(class: Class | keyof<Creatable>, properties: Properties<Class>?) -> Created<Class>

return create :: Create
