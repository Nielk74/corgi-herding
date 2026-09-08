# Landscape routes

Five places share a quiet cooperative world. Larch Hollow has an offset route;
Sunward Orchard adds an optional apple detour. Canyon Oasis opens two dry paths
around weathered rock instead of using a river crossing.

The two existing landscapes retain their current playable bounds and route.
Every herd keeps its animals, invite credentials, saved positions, and selected
landscape. New landscapes should add a place to travel together without timers,
scores, forced restarts, or harsher failure.

## Larch Hollow

A sheltered autumn valley, with golden larches, soft grasses, a stream, and a
quiet pasture. The bridge sits toward the back of the clearing; the pasture gate
sits toward the front. The flock follows a gentle S between them. Players have
room to regroup and call the dogs back if sheep scatter.

| Landscape | Bridge center Y | Gate center Y | Playable bounds |
| --- | --- | --- | --- |
| Alpine valley | 0 | 0 | X [-17, 17], Y [-11, 11] |
| Cactus canyon | 0 | 0 | X [-17, 17], Y [-11, 11] |
| Larch Hollow | -4 | +4 | X [-17, 17], Y [-11, 11] |
| Sunward Orchard | +3 | +2 | X [-17, 17], Y [-11, 11] |

In these four river landscapes, the river remains at X [-1.5, 1.5], the fence remains at X=6, and opening widths
retain the current margins. This changes where the animals must go without
adding a new navigation system. Trees and autumn details must preserve readable
walkable space, including both approaches to the bridge and gate.

## Sunward Orchard

A sun-facing hillside with shallow grazing terraces, broad apple crowns and a
view toward distant farmland. Small tree groups leave the animals and crossing
approaches open. The orchard is not a rigid grid or a screen of trees around a
board. Inspect both the spawn view and the pasture view on a portrait Android
frame; a lower horizon must still reveal layered terrain rather than flat bands.

The version-2 layout adds one windfall zone at (-7, -5), radius 2.2. At most two
individual sheep discover it over the lifetime of this herd. They approach and
nibble when calm, then resume ordinary grazing. Either herder can use either dog
to interrupt them immediately; feeding progress is retained when interrupted.
Waiting is also a complete solution. There is no reward, counter or timer on screen.

The server owns the finite snack progress and persists it with the sheep, along
with the landscape layout. Reconnecting, backgrounding and restarting the server
must not reset it. Completed sheep never repeat the windfall distraction. The
client communicates nibbling only with a lowered head, without simulating local
progress or exposing the internal four seconds of feeding as an objective.

## Canyon Oasis

A sheltered dry saddle with two worn paths around low, broken sandstone.
Green grazing ground and a resting blanket sit to the east; cactus-dotted
shoulders and a distant spring make the clearing part of a wider canyon.
There is no playable river, fence or gate, and no new command or objective.

The canonical version-3 layout contains `rock_pass` with center (0, 0) and radius
3.4. Bounds and movement speeds remain unchanged. Eight fixed visibility anchors
on a radius-5.2 ring route herders and both shared dogs around the rock. An open
line to the destination stays direct; otherwise actors retain their chosen
bypass. Sheep use local avoidance and dog pressure, not automatic pathfinding
to the eastern pasture at X>8. A split flock is recoverable, not a lost run.

V3 herder and dog routes are included in snapshots and checkpoints. Disconnection
pauses a herder's walk without discarding the chosen destination; returning
restores it. Lost, unacknowledged taps are rebased to the server's last accepted
movement on reconnect. The client uses the same double-scalar planner, verified
against 32 shared Go/Godot route fixtures. A tiny outward presentation projection
handles single-precision position rounding at the rock edge; server collision
and the rock radius are never relaxed.

## One authoritative layout

Each herd receives an immutable layout when created. The server owns it and
includes it in snapshots:

```json
{"landscape":"larch","layout":{"version":1,"bridge_y":-4,"gate_y":4}}
```

Version 1 fixes the existing bounds, river width, bridge and gate opening widths,
fence X, player speed, and interaction distances. Only the two opening centers
vary. Future geometry changes need an explicit layout version rather than
silently changing an existing herd's route.

Version 2 retains those bounds and movement rules, adding the canonical Orchard
opening centers and forage zone. Exact nested geometry is validated on both
ends, including after JSON number decoding. Unknown or corrupt layouts and
invalid forage progress are rejected instead of overwriting checkpoints.

Version 3 explicitly replaces the river/fence topology with the canonical Oasis
rock footprint. Its legacy bridge/gate fields are zero and have no gameplay
meaning. Other layouts, saved routes and simulation traces are unchanged.
Invalid rock geometry, unsafe route segments and impossible animal positions
are rejected before starting sessions or overwriting a checkpoint.

The same layout must drive:

- Server collision checks, player and dog waypoints, gate interaction distance,
  and sheep steering toward openings.
- Client terrain, water and bridge surfaces, fence and gate placement, immediate
  movement prediction, contextual gate picking, and destination validation.
- Preview fixtures, gameplay smoke tests, and network integration checks.

The 3D surface remains presentation: the Go simulation continues on its 2D
plane. Visual hills must agree with the client ground mesh and touch picking.

## Saves and older clients

Persist the layout and its version with the herd so later releases cannot alter
the route underneath saved animals. Existing checkpoints without a landscape
continue to load as Alpine valley. Existing Alpine and Cactus checkpoints
without a layout load as version 1 with both centers at zero. Preserve all
credentials, animal identities, sequences, positions, gate state, and progression
during that migration. Unknown layout versions stop loading with a clear error
instead of resetting data or guessing geometry.

An older client cannot enter Larch Hollow while rendering the old centered
bridge. The WebSocket authentication message advertises `layout_version: 1`.
Unsupported clients receive an `update_required` error and close code 4002,
not an invalid-authentication response. Updated clients preserve their saved
credentials and show an update message instead of retrying forever. Legacy
clients may continue using the unchanged centered landscapes.

The health response retains `layout_version: 1` for existing APKs and adds
`layout_versions: [1, 2, 3]`. New clients choose the highest mutually supported
version; old APKs still reach their version-1 landscapes. Orchard needs version
2; Oasis needs version 3. A single re-probe also covers a newer health response followed by a server
rollback before authentication, including a resulting 4002 response.

New clients first probe `/healthz`: older servers do not advertise layout
support, so they receive the original authentication fields. One bounded
re-probe covers a rollback between that check and authentication. Rejections
pause in settings while preserving the saved invitation. Transient server
shutdown failures use retryable close code 1013 rather than bad-credential 1008.

Server release rollback must restore the matching pre-upgrade checkpoint as
well as the executable. Test migration and rollback with copies of actual
supported checkpoint fixtures.

## Acceptance before release

- Alpine and Cactus retain their current footprints, route, and saved profiles.
- A new Larch herd can be selected, joined by a second player, reconnected, and
  restarted with the same layout and all fourteen entities.
- A new Orchard herd supports the same journey checks. Two calm sheep discover
  the windfall, finish without intervention, and retain partial or completed
  progress through reconnect and restart. Dog pressure overrides nibbling and
  ordinary herding can still bring all ten sheep to pasture.
- Oasis supports both dry routes outward and back, nearby stops, changed dog
  commands, and resuming a walk after a dropped input or restart. Ordinary dog
  commands move all ten sheep through either route; a genuinely split flock
  can be retrieved without editing positions or relaxing collision.
- Both herders can command either corgi. A deterministic simulation moves all
  ten sheep through the offset bridge and gate into the pasture without
  teleporting animals, relaxing collision, or adding a failure timer.
- People and dogs can stop on the offset bridge, approach the gate from either
  side, and open it only within the existing interaction distance. Sheep never
  cross the river or fence away from those openings.
- A real Godot/Go network test compares the snapshot layout with the rendered
  bridge, gate picking point, and predicted collision geometry. Preview layout
  fixtures must match the same authoritative configuration.
- Portrait touch picking, actor grounding, hidden contextual controls, and the
  existing geometry budget pass for the new landscape at every supported zoom
  and camera pan.
- Unsupported clients retain credentials and receive an actionable update
  message. Supported checkpoints migrate without loss; failed deployment can
  restore the previous executable and save.

The intended playtest result is a relaxed change in coordination: one herder
helps the flock line up with the bridge while the other makes room near the
pasture. Wandering sheep create another small situation to handle together.
