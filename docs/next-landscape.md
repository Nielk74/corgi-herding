# Landscape experiments

## Canyon Oasis

The fifth place changes the space players negotiate, not just its colors and
scenery. Two broad dry routes around a weathered rock spur open onto green
grazing ground beneath cactus-dotted canyon walls. The distant spring is scenery.
No gate, objective marker or new control. The [iteration log](iterations.md)
records the rejected compositions and fixes found on Android.

Implemented geometry, inspected in the signed portrait Android build:

- Keep the current world bounds, spawns, entity count and movement speeds.
- Place one impassable rock footprint at (0, 0), radius 3.4.
- Leave generous north and south routes around (0, +5.2) and (0, -5.2).
- Keep the east grazing ground beyond X=8 open. Settling there is quiet behavior,
  not a score or an explicit requirement to finish the level.

The canonical version-3 layout has one optional `rock_pass` object. Dispatch
that landscape explicitly; do not reinterpret old bridge/gate fields or touch
version-1/2 saves, geometry or simulation traces. Health keeps the legacy scalar
at 1 and advertises a supported-version list. Older clients keep their invites.

For herders and dogs, test a small visibility graph of eight fixed anchors on a
radius-5.2 ring. Direct visible targets stay direct. Otherwise use a deterministic
shortest bypass, retaining its chosen side while following it to prevent
oscillation. Mirror those rules in prediction. Continue collision-checked
movement substeps. This is a bounded obstacle experiment, not a general navmesh.

Sheep need local rock avoidance and tangential steering under dog pressure.
Do not make the flock automatically solve its route to the pasture. Leave
enough space for a split flock to be an amusing situation the pair can handle.

### Acceptance gate retained for future changes

Before implementing more obstacles, demonstrate both routes outward and back,
both shared dogs, all ten sheep reaching open pasture from normal spawns, and
retrieval of a split flock. Reject teleports, relaxed collision and animals
sticking against the rock. Test nearby stops, changed commands, reconnects,
canonical save validation, old simulation traces and checkpoint-safe rollback.

The rock must not hide the animals in portrait at either camera-follow extreme.
Actual Android images must show accessible paths and naturally bounded terrain,
not a round token on a board. Keep the landscape quiet and the controls hidden.
If that composition or sheep steering fails, revise the experiment before release.

## Next candidate — Cloud Pasture (not implemented)

Return to the Alpine references with an open ridge walk, rather than another
enclosed arena. Three broad grassy shelves and a generous climbing contour path
could overlook a distant lake, blue valley haze and jagged snow peaks. Leave
visible sky and avoid repeated cliff curtains. A low asymmetric rock shoulder
frames one side; steep grassy flanks explain the other boundary without falls.

This needs a real authoritative, wide ridge corridor and resting region, not
an invisible rectangular fence or a visual reskin. Keep the pair able to walk
beside the flock, stop on any shelf and recover sheep resting on lower grass.
No bridge, gate, precision manoeuvre, timer or additional command.

Before adding it, inspect actual portrait views from both ends for valley depth,
readable animals and natural limits. Demonstrate both dogs guiding the flock up
and back, including retrieval of a split flock. Sitting halfway should feel as
complete as arriving: no completion prompt or added HUD. Existing five landscapes,
their saves and old-client behavior must remain unchanged.
