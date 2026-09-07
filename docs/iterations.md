# Landscape iteration journal

## Direction

Keep the game quiet, cooperative and portrait-first. Create places that are
pleasant to inhabit without an objective. Judge actual Android frames and touch
behavior, not only a description or a concept render. Photos are inspiration for
landform and light; they are not assets to paste behind the game.

## Review of build-4

What works: readable animals, shared dog interactions, tall framing, a skyline,
two connected players and controls that disappear after use.

What does not yet work: the playable meadow is flat; mountains look like repeated
separate objects; the straight river and evenly spaced boundary shrubs expose
the rectangular play area. Broad pastel lighting flattens the landforms. The
landscape needs a valley's connected slopes, not just a mountain-themed backdrop.

## Current pass — relief and light

- Shape rolling grazing shelves and hollows into the actual ground.
- Recess the river and raise its banks; keep crossings and gate access legible.
- Connect uneven rocky flanks to a layered, irregular mountain silhouette.
- Use evergreen and occasional gold/rust tree groups to reveal the contours.
- Place actors, props, trails and touch targets on the same sampled surface.
- Strengthen warm sunlight against cooler shadows without losing the animals.
- Keep the frame calm: no permanent controls, glitter, exposure pulses or urgency.

Acceptance needs a real portrait Android capture of both landscapes, a walk
uphill/downhill and over the bridge, height-aware picking tests, multiplayer
regressions, and the released APK/server checks. A ray-lit appearance must be
described honestly: shadow mapping and stylized shafts are not hardware ray tracing.

Android review rejected the first lighting pass: double-converted vertex colors
made the grass dull and the banks black; a broad snow stripe made the mountain
face look folded. Corrected authored color handling, rebuilt broken ridge crests
and snow patches, and tuned shadow bias to remove visible shoreline hatching.
The revised view preserves clear white sheep, orange corgis and cooler rock
shadows. Static scenery batching preserves the rendered geometry and leaves the
animated gate separate; it reduces Alpine terrain mesh instances from 426 to 22
and Cactus from 372 to 41. This is not a measured phone frame-rate claim.

Remaining critique: the foreground lake edge is visibly coarse, the straight
playable channel is still artificial, and the mountain face needs more varied
spatial composition in future places. Keep those shortcomings visible in the
review rather than treating this pass as final art.

Verification: Go race/vet and the Godot scene, terrain, batch-equivalence and
real two-client network tests pass. The signed local APK was exercised on a
portrait Android emulator: hill walking, descending to the bridge, stopping on
the deck, crossing, opening the gate and showing/dismissing the corgi controls.
Emulator evidence verifies rendering and interaction, not physical-phone FPS.

## Next place — Larch Hollow

An autumn shelter beneath an asymmetric rock face. Gold larches mixed with dark
firs follow a sloping shoulder; a small clear stream and grassy rest shelf open
toward distant mountains. The tree line should invite lingering, not hide the
flock. Give it a distinct terrain silhouette and spatial rhythm, not merely a
palette swap. Preserve unhurried herding and shared care.

Later ideas to assess through play: an orchard with shallow terraces, a broad
high pasture above cloud, and a sheltered canyon oasis. Do not add a new place
until its own composition and route readability have been inspected.
