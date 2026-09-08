# Corgi Herding

Build the smallest pleasant cooperative experience described in docs/design.md.
Preserve the no-combat, no-timer, soft-failure design. Both players control both dogs.
Android is portrait-first. Keep controls hidden until an animal or interaction is
tapped; no persistent command bars. Compose broad Alpine and cactus landscapes
behind readable playable ground, with natural boundaries rather than a board rim.
Relief must affect the rendered playable ground, not only distant scenery.
Place actors and props on the sampled mesh surface and ray-pick that same surface.
Keep authoritative movement/interaction distances in the existing 2D coordinates.
Landscapes carry an immutable versioned layout. Bridge/gate geometry, collision,
waypoints, picking and persistence must agree. Preserve existing saved routes.
Negotiate server capabilities before auth; update/policy errors must not erase
saved invitations. Test outward and return routes when openings are offset.
Lighting should reveal slopes and preserve animal readability; describe shadow
mapping and stylized light shafts honestly, not as hardware ray tracing.
Orchard windfall behavior is server-owned and bounded to two individual sheep.
Keep partial/completed feeding in checkpoints; neither interruption nor reconnect
may reset it. Waiting is a valid solution. Communicate with animal posture, not
snack meters, chores or extra permanent controls. Inspect real portrait captures
at both camera-follow extremes before accepting a new landscape composition.

The Go server is authoritative at 20 Hz. The Godot client owns presentation,
interpolation and immediate movement feedback. Keep protocol/README.md in sync.
Never put session credentials, Android signing secrets, local paths or private
deployment credentials in public artifacts. Keep signing identity stable across releases.

Before shipping: Go tests with race detector and vet, Godot headless import and
scene smoke, signed APK verification, and verified server release checksums.
Release artifacts and a healthy running server are the definition of a shipped build.
The updater must only install completed releases and restore both the old binary
and its compatible checkpoint on failure.
