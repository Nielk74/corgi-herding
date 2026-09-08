# Wide cactus wash and quiet skies

This version adds the immutable version-8 Dry Wash region and sky presentation
for both large regions. The ten named places remain separate selections; older
herds are not converted to a different landscape.

Dry Wash has fourteen clearings, thirteen branching corridors and 144 × 192
bounds. Stored terrain terraces, softly worn wash fans and distant flat-topped
mesas follow the canonical region. Frozen Alpine mesh arrays and all earlier
simulation traces remain unchanged. Offline cooking produces complete checked
scenes; Android does not regenerate these large maps during ordinary loading.

The sky uses one camera-owned screen pass with a local, pause-aware cloud clock.
It does not animate the lighting cubemap. Optional menu-only Soft distance starts
off and is saved separately from herd credentials. It softens only distant
scenery, protects current actor silhouettes and preserves transparent world
labels. A tiny depth neighborhood protects anti-aliased ridge and pine edges.
Leaving a large region releases the pass and restores the older camera and sky.
This follows Godot's [depth reconstruction guidance](https://docs.godotengine.org/en/4.6/tutorials/shaders/advanced_postprocessing.html);
it is not hardware ray tracing or the engine's built-in depth of field.

Final local validation included Go vet and race tests, strict prepared-cache
receipts, 669,301 actual-mesh camera/route checks, 664,781 terrace/mesa checks,
7,678 Dry Wash integration checks, 5,337 Alpine integration checks and 3,433,818
atmosphere checks. The latter project actual posed actor vertices in both
portrait aspects, exercise live/preview guard replacement and test world exit,
pause/focus, invalid guard lists and independent camera resources. Shader source
guards are regression checks, not a substitute for GPU inspection.

The signed Android candidate rendered clouds and optional softening in both
large regions. Native ground taps walked from the southern wash into its western
branch, with the same player, two dogs and ten sheep retained on the server.
Background/resume retained the accepted endpoint and sequence. World labels
remained visible. The [portrait capture](images/wide-cactus-wash.png) is actual
gameplay on that candidate, not the authoring studio. The emulator used a
software graphics backend: this is not a physical-phone frame-rate measurement
or a two-human assessment of herding fun.

Extra plant meshes and sparse windborne seed/dust helpers remain private or
disabled authoring studies. They are not advertised as enabled gameplay effects
in this release. Publication and automatic deployment are verified separately
after the release workflow completes.
