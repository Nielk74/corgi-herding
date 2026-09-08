# Same-view material studies

The separate landscape studio has authoring controls, not a proposed game HUD.
Use its fixed viewpoints to compare original and calmer grass, then original
pine needles, a stationary replacement shader, and gentle needle wind. Switching
biomes restores the original cached material references. No file is rewritten by
these controls. This makes a small visual comparison possible without rebuilding
or exporting a separate APK for every parameter adjustment.

The calmer Alpine study reduces texture contrast to 0.76 and saturation to 0.72.
Its contrast pivot is the measured mean color of the licensed grass albedo;
source images remain unmodified. Actual portrait Android comparison showed less
distracting mottling while retaining ground detail, the worn trail and relief.
That preset is selected for the next candidate, not the published build 15.
The cactus material does not inherit it. The scene remains visibly procedural.

Pine comparisons use the current source tint, instance colors and roughness.
In three sampled crown regions of actual original/stationary-shader Android
captures, nonzero differences were at most one RGB channel level out of 255.
That is sampled evidence, not a universal bit-identical rendering claim.
The shader's color handling follows the pinned
[Godot 4.6.3 material implementation](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/resources/material.cpp#L1138-L1147).

The wind prototype bends only the upper needles, with an analytical 0.08-unit
world-space limit and corrected surface normals. Existing trunks remain static.
An explicit clock freezes on focus loss or backgrounding without replaying
missed time. Geometry tests retain all original triangles, placement buffers and
whole-crown clearance. Actual sampled Android frames show small crown movement
without obvious tearing, palette jumps or shadow flashes. The software-rendered
emulator recording is too slow to establish animation comfort or phone FPS.
Runtime binding, picking and map-transition checks remain separate acceptance
work; a studio comparison is not a completed multiplayer playtest.
