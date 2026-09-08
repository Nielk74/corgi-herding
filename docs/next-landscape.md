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

## Sixth place — Cloud Pasture

Return to the Alpine references with an open ridge walk. Three broad grassy
shelves and a generous climbing contour path overlook a distant lake, blue
valley haze and jagged snow peaks. Leave visible sky and avoid repeated cliff
curtains. Steep grassy flanks explain the boundary without falls.

The canonical version-4 layout defines four spine anchors, a 3.6-unit corridor
half-width and three broad shelf disks. Walkable ground is their union. All
movement segments, not only endpoints, must remain inside it. Matching analytical
coverage and a six-node visibility graph keep authoritative movement, prediction
and remote interpolation on the ridge. Retained routes survive disconnect and
restart. This stays deliberately bounded; it is not a general navigation system.

The pair can walk beside the flock, stop on any shelf and recover sheep resting
on lower grass. No bridge, gate, precision manoeuvre, timer or additional command.
Tests bring all ten sheep uphill and downhill from normal spawns and retrieve a
dog-created split. Neither the tests nor gameplay teleport animals to succeed.

Before accepting changes, inspect actual portrait views from both ends for valley depth,
readable animals and natural limits. Demonstrate both dogs guiding the flock up
and back, including retrieval of a split flock. Sitting halfway should feel as
complete as arriving: no completion prompt or added HUD. Existing five landscapes,
their saves and old-client behavior must remain unchanged.

## Seventh place — Juniper Shore

The prototype is a quiet Alpine lakeside crescent, with a stony beach below grassy
clearings and a long mountain view across the bay. The shore, not a gate, shapes a gentle
journey around a bay. Leave broad places for the pair to linger side by side;
the flock need not reach a finish. Keep water boundaries readable without walls,
falls or deep-water punishment.

The canonical version-5 union combines six path anchors and three generous
clearings. Both herders and corgis retain safe routes around the bay. Normal
dog-command tests move all ten sheep outward and back and recover a split flock.
There is no settled-state destination or arrival message. Existing six-landscape
geometry, saves and full simulation traces remain protected.

Carry forward Cloud's visual criticism: break up the distant mountain-foot
line, vary tree groups and give foreground land a more specific character.
The first Android views improved the open saddle and dry-shore readability but
showed overly regular junipers and flat-looking water. Refine those specifically,
without moving the shoreline or hiding actors behind more scenery. Lake motion
can be restrained opaque shading; it is not a ray-traced reflection. Sparse
environmental sound remains its separately tested system, with no additional HUD.
Actual portrait play at both ends and two-person feedback remain necessary.

## Eighth-place proposal — Bellflower Commons

Return to the Alps with a broad meadow that branches toward a sunny shoulder
and a sheltered grassy hollow. Both are places to spend time, not competing
objectives. The central common should be pleasant enough that nobody needs
to leave. This is a branching space, not another lake crescent or a recolored
ridge. A cactus dry wash with shallow erosion terraces remains a distinct
later possibility, not an extra landscape promised in the next release.

Before adding a place, address Juniper's return-view criticism: the camera can
retain too much of its old rightward position while the herder walks left.
Prototype a calm local-herder follow adjustment, retaining fixed angle, zoom
and pan limits. Do not follow the flock centroid or chase distant strays. Stop
movement when the herder rests, and inspect actual Android reversal footage
for drift, oscillation and excessive motion before accepting the change.

For the meadow spike, use a new versioned footprint only after testing ordinary
spawn-to-branch herding in both directions. A fork needs explicit connections;
an ordered spine must not accidentally create a shortcut between the branches.
Keep generous gathering areas and the same two herders, two shared dogs and
ten sheep. No new commands, animal behavior, gate, arrival message or reward.

Compose one continuous sampled heightfield: a shallow central hollow, a softly
raised shoulder and a lower sheltered branch. Improve the shapes of the land
before adding props. An asymmetric exposed-rock flank, diagonal erosion folds,
broken vegetation groups and a valley opening should connect the near grass
to distant peaks. Avoid smooth foreground wedges, repeated conical mountains,
regular tree rows and a surrounding wall. The photographs guide composition;
they are not textures or other distributable game assets.

Acceptance requires all ten sheep to visit either branch and return, and a
naturally split flock to be recoverable using ordinary commands. Retained routes
must survive reconnect and restart. Mesh, feet, picking and full movement
segments must agree. Inspect the center and both branches in both portrait
aspects and at true camera extremes; reject hidden animals, visible mesh edges
and unclear walking limits. Keep the existing triangle budget and all seven
released layouts, heights, saved state and simulation traces intact. Human
two-person feedback remains necessary to judge whether wandering and resting
actually feel unhurried.
