# Playtest direction — 8 September 2026

The player tried the released game and reported that the maps are too small,
dog control is difficult, and the world needs more realistic landscapes,
lighting, detail and motion. They explicitly requested a tutorial map and a
faster way to create large, detailed places. This changes the priority: another
small scenic variant is not sufficient progress on the core experience.

## Immediate changes

Keep portrait and minimal normal-play controls. The tutorial is an explicit
exception to the previous “no tutorial text” rule: show one short contextual
instruction, explain why it helps, and make each lesson and the entire guide
skippable. A dedicated practice place should teach walking, selecting either
shared dog, Come, Stay, placing a dog, gentle pressure, withdrawing to let sheep
graze, and affection/rest. No timer, score, punishment or mandatory graduation.
Observe real server state; do not mistake a sent input for accepted gameplay.

Dog repositioning currently requires selecting a dog, tapping Go, then tapping
ground. An optional direct drag from dog to ground reduces that repeated action.
Retain ordinary taps and the stable Come/Stay/Go/Pet menu. Preview the destination
using the dog's collar color; release sends one validated Go. Invalid terrain,
GUI release, a stale session, disconnect or backgrounding cancels safely. Do not
accidentally move the herder or cancel an already accepted herder walk.

## Actual scale, not just scenery

Existing world bounds are 34 × 22 units. The next large Alpine region is designed
inside 144 × 192 bounds with broad side clearings and return loops, not only a
long narrow route. Keep animal sizes, walking speed and personal attachment;
do not enlarge the world by shrinking everyone or accelerating travel.

New bounds and navigation require a new immutable protocol version. Every old
save, route and simulation trace remains unchanged. Camera following must work
in both horizontal directions and along the valley, while feet, picks and
rendered slopes continue to agree. Server-authored paths and boundaries are not
randomly generated decoration.

## Faster authoring prototype

Small JSON art recipes describe biome, seed, bounds, a graded terrain spine and
resting places. The Alpine recipe also references the candidate explicit region
graph, so side routes do not accidentally grow scenic cliffs or blocking trees.
The cactus dry-wash recipe is an art variant, not a second accepted large map.

`landscape_recipe.gd` samples continuous graded terrain with seeded surface
variation. `landscape_chunk_builder.gd` generates indexed 16-unit chunks on one
shared lattice, with identical shared heights/normals and nonoverlapping local
UV2 coordinates. Detail placement is seeded per chunk, slope-aware and grounded
on the actual mesh triangles, not the unsampled analytical height function.
Tall detail stays outside the intended walking area.

The core terrain builds have 120 chunks and 61,440 triangles each. Mesh heights
and smooth normals share the actual stored lattice. One flank descends and the
other rises, avoiding the enclosed bowl produced by raising every boundary.
The scenic ring stitches every one-unit edge vertex to a coarser indexed mesh;
shared face-derived normals do not expose a different shading seam per chunk.

The complete art scene adds an apron, grass, bounded pine/cactus/stone batches,
licensed grass/sand/rock surface blending and distant ridges. A reviewed source
recipe still defines the traversable layout separately: scenic meshes never
authorize new walking ground. Vegetation is spatially batched and range-culled;
this is not a claim that the entire world is streamed out of memory.

A narrow worn trail follows the authored spine as a visual suggestion, not a
mandatory path. Its mask is stored during initial mesh construction in unused
vertex alpha; the terrain shader stays opaque. There is no decal, overlay,
additional draw call or changed walking boundary. The trail checks compare
actual pre/post construction vertex, normal, index and UV channels exactly.
An initial after-the-fact mesh repaint was rejected because re-encoding packed
normals changed their values; writing the mask before the first encoding fixes
that issue. Alpine material elevation bands now distinguish meadow, exposed
rock and snow, while the cactus recipe explicitly disables snow.

Build a new ignored scene without overwriting an existing artifact:

```sh
bash tools/run-godot-check.sh "$GODOT" --headless --path client \
  --script res://tools/build_landscape.gd -- \
  --recipe=res://worlds/long_valley.recipe.json \
  --out=/absolute/ignored/build/long-valley.scn
```

Add `--full` for the complete scenery. The usual developer/CI path prepares both
named maps, replacing only their regeneratable ignored caches:

```sh
node tools/build-landscapes.mjs "$GODOT"
node tools/build-landscapes.mjs --check
```

The cook pins Godot 4.6.3, fingerprints source scripts, recipes, referenced
region, actual texture bytes and import settings, and verifies the saved scene
hash/size. Unchanged maps are reused; stale or damaged caches rebuild. CI cooks
and verifies before export. Runtime checks the scene's embedded recipe and
loads it without running the terrain generator. The fallback builder exists
for development; release acceptance explicitly tests the cached path.

The current complete Alpine/cactus cooks take approximately 1.8/1.5 seconds on
the authoring host and produce roughly 3MB scenes. This is **not Android FPS**,
whole-level design time or proof of finished gameplay. All-world art budgets
currently measure about 533k/406k triangles, including grass instances, props,
apron and distant scenery; many batches are outside the camera/range. Actual
phone frame time remains an acceptance gate.

Headless export initially discarded vegetation set through GPU-only instance
setters. Explicit CPU MultiMesh buffers and saved AABBs fix that failure. Tests
decode the actual serialized buffers, ground them against rendered triangles,
and independently verify before/after disk reload. Source transform calculations
alone are not export evidence. Maximum declared grass wind remains inside the
expanded culling bounds and keeps roots fixed. Pine geometry is currently static.

The [verified CC0 material kit](materials.md) provides real ground and stone
texture data. Use mipmaps and bounded mobile compression. Distribute vegetation
across separate chunk MultiMeshes: one giant MultiMesh cannot cull individual
instances. [Godot's MultiMesh guidance](https://docs.godotengine.org/en/4.6/tutorials/performance/using_multimesh.html)
supports this batching approach. Generate/save meshes before any baked indirect
lighting; UV2 alone is not GI, and no bake or hardware ray tracing has been
implemented by this authoring prototype.

## Critical acceptance

Do not publish merely because route tests pass. Inspect actual portrait walking,
dog dragging and guided practice. Large spaces need landmarks, varied density,
natural slopes and useful places to wander, not a repeated grass sheet. Verify
ordinary two-dog herding outward, back and around loops, split-flock recovery,
resting and reconnection without teleporting or relaxing boundaries.

The Bellflower spike now has a connected far crest and better middle-distance
layering, but the latest Android image still has strongly faceted mountains and
a tightly packed grazing flock. Those are recorded criticisms, not evidence of
realism or a completed playtest response. At that review, public build 13 remained
the verified release while these changes were developed and reviewed.

The first large-map Android art view was rejected: it looked like repeated grass
with a cut foreground edge. A fixed-perspective experiment and descending flank
now reveal the far ridge, with correctly visible foreground trees and shadows.
The next criticism is the overly angular pine crown and faceted mountain
shading. Denser irregular needle sprays and shared indexed scenic normals
improve those in the next actual Android render; the assets remain stylized.
Snow was then lowered to match the visible crest, but its first rendered pass
was too bright, so its reflectance was reduced for the next review.
`landscape_studio.tscn` explicitly labels its poses as scale figures,
not simulated gameplay; it can switch between Alpine and cactus recipes.

Rigid actor batching preserves original Body/Head/Tail animation targets and
merges only compatible opaque parts. Independent comparisons cover 81,744
posed vertices, authored colors, normals and materials across sitting, bobbing,
nibbling and wagging. The actual Android studio view changes from 591 to 291
draw calls while retaining the same 204,858 visible primitives and all 14
figures. That is a renderer-cost comparison, not a physical-phone FPS result.
Future material customization must not assume the original per-part materials
are still individually mutable after batching.

Native Android direct dragging has separately been exercised against the real
isolated Bellflower server: rose target previews move under the finger, release
produces a brief cream destination and the selected dog walks there. Both dogs
were repositioned; invalid sky release did not retarget the dog or move the
herder. The original accepted herder sequence/target remained unchanged. This
is input/server evidence, not a claim that two humans found herding fun.

The optional practice guide uses the existing Bellflower v6 geometry. The
welcome choice is explicitly named Practice meadow. Its controller observes
accepted snapshots plus freshly emitted local actions; socket send success is
not described as a server acknowledgement. It remains skippable and scoped to
practice, with local hidden/completed preferences separate from credentials.
Guide UI has passed its focused checks. Nonconflicting herder walking/sitting
and other-dog commands no longer discard a pending selected-dog lesson. A
replacement command to that dog, selection change or closed connection epoch
still invalidates the pending observation. At this stage, new large-world gameplay
was still being tested on Android, before the build-15 release verification below.

The first integrated signed Android candidate has now created a real v7 herd
on an isolated Go server. An ordinary second peer appears in the same world.
A native corgi drag produced a roughly 23-unit Go trip while the herder's
accepted sequence remained zero. A separate world tap then moved the herder
from (-48,74) to (-38.4401,47.2589), sequence 1. Actual walking frames show the
camera following across the terrain and settling after the walk. Backgrounding
and returning retained that endpoint and sequence. These are real input/server
observations, not the studio's staged figures or a complete flock journey.

The native Practice guide independently advanced through walking, dog selection
and Come. Its initial instruction and contextual menu both fit the portrait
frame. A wording gap after Come was found during that test: the controls close,
so the next Stay instruction now explicitly says to tap the dog again.

The same Android herd subsequently completed Stay, valid Go placement, observed
sheep pressure, withdrawal with Come, and sitting. No Skip was used. The guide
disappeared after the server reported sitting and stayed hidden after reinstall
and Return. One failed drag revealed an important boundary problem: the finger
landed about 0.19 units outside the legal clearing, on apparently ordinary grass.
Collision correctly rejected it, but the silent result was confusing. A focused
follow-up adds a two-second explanation only after an intentional invalid-ground
drag; ordinary taps and UI/lifecycle cancellations stay silent. Neither this
message nor scenic material changes enlarge the walking area.

The follow-up private APK displayed that explanation during a recorded native
drag. Moving the release point to nearby legal grass instead sent an ordinary
Go; Mochi arrived while the herder retained its sitting state, position and
accepted movement sequence. A separate Alpine view uses six sparse, broken
scree patches outside selected clearing edges. They are material hints, not a
complete boundary fence. Their inverse-red vertex mask preserves terrain,
normals, trail alpha, vegetation, draw batches and saved mesh channels. A clean
gap prevents interpolated paint leaking onto legal ground. Cactus and distant
default-white meshes do not acquire the mask. Broad rotated stone sampling
reduces the most conspicuous distant tiling, but the current grass remains too
mottled and the pines too rigid; neither change establishes finished realism.

The new camera uses the actual prepared triangles for grounding and picking,
including a binary64 ray/triangle predicate to avoid a float32 miss at an exact
shared edge. A v7-only bounded vertical clearance adjustment resolves two
foreground obstructions without permitting taps through scenery. All 16
clearing-centered views pass at three zooms and two portrait aspects; tested
continuous approaches and returns need at most 8.47 units of the 18-unit lift
cap. Lift rises/falls at bounded rates and the camera freezes at rest. These
geometry tests do not replace actual Android comfort review.

## Verified publication — build 15

Build 14 published nothing: the real-network gate caught an obsolete
maximum-capability assertion; an audit found three expectations of 5 instead of 7.
Correcting only those tests preserved strict old-layout and gameplay checks. The complete
[build-15 workflow](https://github.com/Nielk74/corgi-herding/actions/runs/34207085466)
then passed for source `7f68be2d3f93f12e74d53c9c504fe5304eb5024b`.

The [completed public release](https://github.com/Nielk74/corgi-herding/releases/tag/build-15)
was independently downloaded: every artifact checksum passed, the signed portrait
APK kept its existing certificate and passed 16 KiB alignment, and all three
server binaries had the expected architecture and source revision. The ordinary
scheduled updater installed the matching Darwin binary without intervention.
Both its final pre-update backup and a new-version checkpoint flush preserved
all nine existing herds exactly. Health and readiness now report build 15 and
layouts 1–7. No live herd was created or changed for that preservation check.

This release includes guided practice, direct dog dragging and the large valley.
The later invalid-drag explanation, scree hints and subsequent pine/grass studies
remain private follow-up candidates, not features of public build 15. Candidate
Android observations above are not claimed as a completed return test of the
exact published APK; that separate check is still pending here.
