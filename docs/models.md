# Models: layout and lookup

Two conventions, enforced by `shared/world/folders` and `shared/world/markers`. Neither is required to
build a game; both stop being optional the moment a place file contains content
a human authored in Studio and a script has to find things in it.

## Layout — `Logic` / `Structure` / `Deco`

Every model a game builds or ships splits into three folders, so **what a script
may touch is obvious from the Explorer alone**:

| Folder | Holds | Read by code? |
| --- | --- | --- |
| `Logic` | Contracts — markers, bounds, spawn points, doors, interactables. **Everything in here is tagged.** | Yes, and only through tags |
| `Structure` | The shell: floor, walls, ceiling, steps. Collision and streaming weight. | No |
| `Deco` | Cosmetic only. A client that builds its own dressing leaves this empty on the server, so it **must never be load-bearing**. | No |

The three folders are the *concern*, and they **nest**. Group by system below
them — `Structure/Shell/`, `Deco/Props/` — and apply the same split at every
level: a sub-model that is a thing in its own right carries its own
Logic/Structure/Deco.

`model_layout.logic(model)` and friends get-or-create, so a builder pass never
has to know whether it is the first one to want a folder.

### Make sub-models modules

If everything one unit needs lives inside its own model, its `PrimaryPart` is
the anchor, and nothing outside names it — then duplicating the model and
pivoting it into place adds another one **with no code change**. That property
is worth designing for; it is the difference between "add a sixth one" being a
drag-and-drop and being an afternoon.

## Lookup — tags, never `FindFirstChild`

```luau
const found = model_layout.scan(room, { tags.BOUNDS, tags.ENTRANCE, tags.SPAWN })
const bounds = model_layout.require_part(found, tags.BOUNDS, "room 12")
const sign = model_layout.optional_part(found, tags.SIGN, "room 12")
```

### Why not names

A tag survives what a name does not: reparenting the marker into a folder,
renaming it in Studio, or an author hand-building a model to the same contract.
None of those raise an error when they break a name lookup — the marker is
simply not found, and what happens next depends on where the read lands.

### The cast is the bug

The habit this replaces is:

```luau
const bounds = model:FindFirstChild "Bounds" :: BasePart
```

`FindFirstChild` returns `Instance?`. The `:: BasePart` asserts the nil away
**without checking anything**. So a model missing its marker does not fail at
the lookup — it fails a page later, on whatever first indexes the nil
(`attempt to index nil with CFrame`), possibly inside a build running under
`fatal.guard`, taking the server with it. The error names the wrong file.

`require_*` fails **at the lookup**, naming the model, the tag, and the class it
wanted. `optional_*` returns nil and means it, so the caller's type says so and
the analyzer makes them handle it.

### Wrong class is a bug, not an absence

`optional_of` warns rather than silently returning nil when the tagged instance
is the wrong class. A Model carrying a tag meant for a BasePart means somebody
tagged the wrong instance; treating that as "not there" hides the mistake until
something downstream misbehaves for an unrelated-looking reason.

### One walk, not six

`scan(root, wanted)` does a **single** `GetDescendants` pass bucketed by tag.
Resolving a room wants half a dozen markers out of a few hundred instances; six
separate walks would each allocate a fresh array of all of them.
`CollectionService:HasTag` in the inner loop beats `GetTags`, which allocates
per descendant.

## Tag names are contracts

Put them in `shared/records/tags.luau`, never inline. A tag written as a string
literal in two files is a contract between them that nothing checks: the server
tags `FlickerLight`, a client scans for `FlickerLights`, and the result is no
error, no warning, and a feature that quietly stops working. A record makes a
typo a nil index at require time.

## Shared raycast filters

`shared/world/character-exclusion` keeps one list of every player character for every
`RaycastParams` that must treat characters as "not terrain":

```luau
const params = RaycastParams.new()
character_exclusion.track(params) -- sets FilterType for you
```

It sets `FilterType` itself, because an Exclude list on an Include filter is the
one way to get this exactly backwards — and that reads as "the probe collides
with nothing but people", which looks like a physics problem rather than a
one-word mistake.

Maintained on character lifecycle rather than rebuilt per ray: **assigning**
`FilterDescendantsInstances` makes the engine rebuild the whole exclusion set
whether or not anything in it changed, and the set only actually changes when
somebody spawns or dies.
