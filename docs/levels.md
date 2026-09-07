# Landscape routes

This is the proposed next iteration after the Alpine valley / Cactus canyon
terrain and lighting revision. Larch Hollow is not implemented yet.

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
| Larch Hollow, proposed | -4 | +4 | X [-17, 17], Y [-11, 11] |

The river remains at X [-1.5, 1.5], the fence remains at X=6, and opening widths
retain the current margins. This changes where the animals must go without
adding a new navigation system. Trees and autumn details must preserve readable
walkable space, including both approaches to the bridge and gate.

## One authoritative layout

Each herd receives an immutable layout when created. The server owns it and
includes it in snapshots. A first layout message can remain small:

```json
{"landscape":"larch","layout":{"version":1,"bridge_y":-4,"gate_y":4}}
```

Version 1 fixes the existing bounds, river width, bridge and gate opening widths,
fence X, player speed, and interaction distances. Only the two opening centers
vary. Future geometry changes need an explicit layout version rather than
silently changing an existing herd's route.

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

An older client must not enter Larch Hollow while rendering the old centered
bridge. Before enabling a noncentered route, add a capability/version check to
the WebSocket handshake and verify it in integration tests. Reject unsupported
layouts with a dedicated update-required response that preserves the client's
saved credentials; do not report this as invalid authentication. Legacy clients
may continue using the unchanged centered landscapes.

Server release rollback must restore the matching pre-upgrade checkpoint as
well as the executable. Test migration and rollback with copies of actual
supported checkpoint fixtures.

## Acceptance before release

- Alpine and Cactus retain their current footprints, route, and saved profiles.
- A new Larch herd can be selected, joined by a second player, reconnected, and
  restarted with the same layout and all fourteen entities.
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
