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

## Third place — Larch Hollow

An autumn shelter beneath an asymmetric rock face. Gold larches mixed with dark
firs follow a sloping shoulder; a small clear stream and grassy rest shelf open
toward distant mountains. The tree line should invite lingering, not hide the
flock. Give it a distinct terrain silhouette and spatial rhythm, not merely a
palette swap. Preserve unhurried herding and shared care.

The implemented route places the bridge at -4 and the pasture gate at +4.
Server snapshots, saved worlds, collision and the rendered scene share a
versioned layout. Twenty-four two-way prediction routes pass; 543 portrait
picking cases cover all three landscapes. The real two-client test walks to
the offset gate by tapping it, opens it for both players, visits the pasture,
returns over the bridge and reconnects. A deterministic server regression
brings all ten sheep into pasture with ordinary movement and collision limits.

The first Android composition was rejected: a distant grass slab pierced the
rock face, and an evenly spaced tree belt looked planted as a barrier. The
revised ground ends beneath the irregular rock foot without altering playable
heights. Three unequal woodland pockets replace the row; crown spacing also
prevents foliage intersections. The bridge and gate stay readable and the rest
shelf stays open. Android touch testing reaches and opens the offset gate.

Keep improving: the shoreline and trail bends remain visibly polygonal, the
far ridge faces are still too repetitive, and ambient sound and richer animal
animation are missing. This is a playable place to iterate on, not final art.

Later ideas to assess through play: a broad high pasture above cloud, and a
sheltered canyon oasis. Do not add a new place
until its own composition and route readability have been inspected.

## Fourth place — Sunward Orchard

An open sun-facing hillside, two shallow grazing terraces and a windfall beneath
broad apple crowns. This should feel spatially different from the enclosing
mountain valleys. The distant landscape matters as much as the tree palette.

The first actual Android composition was rejected. Broad nearly horizontal
terrain bands occupied the upper frame, the far village was not legible, and
an exposed upstream water cutoff drew attention to the construction. The canal
dominated the scene. Rework the landscape from the actual herder-follow view,
not only a centered preview. Keep playable heights and collision unchanged.

The second view established a readable mountain, hamlet and winding distant
brook, but revealed torn field-overlay triangles and regular shoreline shadow
teeth. Field color now belongs to the real ground vertices, not floating mesh
patches. Curved-bank normal sampling follows the bank instead of accidentally
sampling the submerged bed. An isolated square snow patch was also removed.
The revised Android frame no longer shows those defects. A new regression
checks 1,188 shoreline normals, in addition to the 793 terrain-picking cases.
The next capture exposed fine/coarse terrain cracks. Matching exterior grid
spacing and explicit transition triangles now stitch those seams; the final
Android windfall view no longer shows bright gaps through the hillside.

The small gameplay change is server-owned: at most two sheep discover windfalls,
pause for a finite snack, and return to grazing. Either dog can interrupt them;
waiting is a valid solution too. Partial and completed progress persist. A
lowered muzzle supplies the feedback, with no objective or additional control.
The real two-client test verifies natural discovery, monotonic snack progress
through reconnect and self-resolving feeding; scene tests verify the head pose.
An actual Android capture also shows the two feeding sheep slightly apart from
the flock with lowered muzzles; completed sheep return to normal grazing.
A subsequent live check used Android ground/gate taps and an automated second
client issuing ordinary dog commands: all ten sheep reached the pasture. It
also exposed a lingering arrival banner. That acknowledgement now fades once,
never repeats when a sheep wanders back, and stays silent when resuming a settled
herd. Human two-phone playtesting remains necessary to judge the feel.

The four landscape choices now occupy two portrait rows with large touch areas.
Thirty-two two-way predicted routes and exact nested JSON layout checks pass.
The new APK negotiates layout v2 without breaking v1 clients or erasing saved
invitations during upgrade, policy rejection or a server rollback.

Keep improving: the central channel still reads like a canal, distant houses
repeat, the palette is quite pale, and the foreground could tell more of a
place's story. These are explicit prototype limitations, not final art. The
[next landscape experiment](next-landscape.md) tests a rock spur with two dry
routes so the level structure itself can change, rather than repeating another
river and gate in different colors.

## Fifth place — Canyon Oasis

The first topology change is a sheltered dry saddle around a low rock spur.
Either broad path leads toward green pasture; no gate or river imposes a single
crossing. Sheep remain guided by dog pressure and local steering. Actual normal-
spawn tests bring all ten through either pass, and retrieve a genuinely split
flock, without changing positions, movement speed or the collision radius.

The first signed Android view was rejected. The concentric rock looked like a
button, hard path overlays formed a race circuit, and the distant water ended
in a sharp triangle against the canyon. Broken stone lobes replaced the tiers,
ground color replaced path overlays, and the spring moved into a complete
depression. The second capture still showed a circular plate under the stones
and overly abrupt pool banks. Those shortcomings prompted another visual pass;
the terrain tests alone were not enough to accept the scene.

The spring is now shallow and the outcrop base blends into the soil. A far-right
Android view exposed an additional terrain edge: the 20:9 phone sees more ground
than the 16:9 test window. Seventy-two actual-mesh ray checks now cover both
aspect ratios, both follow extremes and all supported zooms. They caught not
only a small mesh but also high distant terrain clipping the orthographic near
plane. An Oasis-only foreground taper fixes that without changing walking
heights or the other landscapes. A subsequent black rock-base artifact was a
triangle-winding mistake, not the intended lighting; front-face/normal checks
now guard the low apron as well.

The parallel reconnect review found a real bug: a lost predicted tap could
leave the client waiting indefinitely for an input sequence the server never
received. A separate first-snapshot-after-disconnect flag now restores accepted
movement without resetting arrival-message history. The network test closes
the socket just before a ground tap and uses normal recovery, with no test-only
reset of game state. Two precision regressions were also addressed: double-
scalar graph math agrees on 32 shared Go/Godot routes, and a tiny outward
presentation projection prevents float32 rounding from freezing animals on the
rock edge. Authoritative geometry and collision remain strict and unchanged.

The corrected signed Android build was then inspected at both camera-follow
extremes: no black stone base, cut-off foreground or exposed spring underside.
An Android-created herd and a second WebSocket client using ordinary dog
commands brought all ten sheep from normal spawns to pasture at tick 676. The
phone then walked around the rock, sat beside the second herder, called a corgi
and used the nearby Pet action. Controls disappear after each action; resuming
the already settled herd is quiet. The [new portrait capture](images/canyon-oasis.png)
shows the two herders, both dogs and flock, not a concept illustration.

Keep improving: distant cliff faces repeat, the spring is still a flat color
patch, and the foreground has limited detail. Animal animation and ambient
sound are still sparse. Emulator checks establish rendering and interaction,
not real-phone frame rates or the feel of two humans herding together. The next
candidate is an open Alpine ridge pasture with valley depth, described in the
[landscape experiments](next-landscape.md); it is not implemented in this build.

The first release attempt stopped at a new Orchard compatibility hash on Linux.
Matched Go 1.26.7 tests of the previous build and the new simulation produced
byte-identical full snapshots for all 700 ticks on Linux amd64, as they did on
Mac arm64. The cross-platform hash difference came from signed zero, not changed
behavior; raw coordinate differences were at most 3.56e-14 world units. The
replacement Orchard regression compares a full previous-build trace with exact
gameplay states and a 1e-12 bound only on actor position, velocity and target coordinates, stricter
than the former 1e-6 rounding. The failed workflow published nothing and left
the live server untouched.

## Sixth place — Cloud Pasture

Three broad grassy shelves follow a climbing ridge above an Alpine valley.
This changes the legal ground again: a union of shelf disks and wide path
capsules replaces the river crossing or rock bypass. Both players and both
dogs follow the whole safe route; checking only its endpoints would allow a
shortcut across steep country. Analytical segment coverage and a small
visibility graph are mirrored between Go and Godot, with 32 shared fixtures
and 6,006 ordered server routes. Lost-tap reconnect and retained routes are
checked through actual network disconnection, not test-state resets.

The first signed Android views were rejected at the starting shelf, middle
and upper end. The foreground was a soft empty green expanse, the snowy massif
ended on a flat-looking wall, and the tarn was a uniform cyan oval. A Cloud-only
pass added rocky runnels outside the walking corridor, a staggered foothill,
sparse distant woodland and an inlet with shallow-water colors. Far terrain
uses its own material surface in the same continuous mesh to avoid noisy
received shadows. Nearby terrain and animals retain their shadows; the global
light rig and every older landscape remain unchanged.

An Android-created staging herd and a second client using ordinary dog
commands brought all ten sheep uphill at tick 754, downhill at tick 2610,
and uphill again at tick 4029. Separate server tests retrieve a genuine
dog-created split. No actor positions are overwritten to pass these tests.
Every shelf supports calm grazing, and Cloud never announces completion,
including when returning to an already settled herd.

Two testing defects were found along the way. Godot can print a script parse
error but return exit zero; all CI import, test and export commands now pass
through an error-log guard. Also, a headless startup can reset the requested
window to 64x64, producing a square logical viewport. Tests now explicitly
set and verify the logical portrait dimensions. The corrected total is 1,267
terrain picks: 915 in the old five landscapes and 352 on Cloud. Fewer incidental
points are on-screen than in the earlier square window; no required fixture
or threshold was removed. Cloud additionally checks all 1,200 water triangles
against the ridge, 400 covered shoreline samples, 40 real-bank rays, 72 ground
frame rays and 92 actor-visibility probes. Geometry remains below 100,000 triangles.

Compatibility checks now include an independently captured 700-tick Oasis
trace from the previous build. Old/new snapshots are byte-identical within
each tested platform; exact state, geometry and route anchors remain required
across platforms, with a 1e-12 allowance only for actor coordinates. A successful
join also clears the stale “Opening a little world…” line when reopening the menu.

The refined signed APK was inspected on Android at both actual follow extremes,
including the upper herder at X=13.33, and on the middle shelf. There are no
visible holes, exposed backfaces, cut-off water or props hiding the animals.
The descent, resting shelves and tarn read more distinctly. Remaining work is
explicit: the mountain-foot silhouette is still quite wall-like, pine forms
repeat, and some broad terrain remains overly smooth. Distant stippled shading,
sparse animation and missing environmental sound still limit the atmosphere.
These captures verify a playable prototype, not real-phone performance or the
feel of two human players.

Actual Android taps called Maple, revealed the nearby Pet action and let the
herder sit beside their companion. The authoritative checkpoint recorded the
petting herder and happy dog. The [quiet portrait capture](images/cloud-pasture.png)
contains both herders, both corgis and the flock with no invite, command panel,
arrival text or permanent action bar.

The build-10 release attempt stopped during Cloud's initial HTTP connection on
Linux and published nothing. The server independently handled repeated six-herd
workloads with Cloud creation taking 7–37 ms. A controlled Godot experiment
instead reproduced an immediate HTTP timeout after a 13-second construction
frame, before the server received a request. The real-network tests now let
three engine frames finish before starting HTTP. CI deliberately inserts the
13-second startup delay on Cloud to retain this regression; the HTTP and network
test timeouts are unchanged. Empty timeout bodies and non-JSON server errors
also report ordinary connection errors without emitting engine JSON errors or
erasing the saved invitation. The default network test now explicitly covers
Alpine, with a separate Cactus invocation instead of accidentally testing Cactus
twice. The live server remains on the last completed release during failed CI.

The corrected build 11 passed CI and published its signed APK. Independent
downloads matched the release checksums and stable signing certificate. The
ordinary scheduled server update preserved all five existing herds exactly,
including the post-update checkpoint flush. A sixth Cloud herd created through
the published Android APK retained an interrupted walk through force-stop and
Return, reaching its original destination without another input. The resulting
six-herd checkpoint is the next release's preservation baseline.

## Sparse sound — an atmosphere experiment

The landscape had become more expansive, but it remained silent. This iteration
adds short filtered-noise wind breaths and occasional synthesized bird phrases,
not a permanent ambience loop or music. Two wind clips and three bird phrases
are generated once into 570,210 bytes of mono 16-bit PCM. There are at most two
ambient voices. Nothing is emitted for an optimistic command acknowledgment or each
individual sheep. The spatial listener follows the herder rather than the camera.

The first wind waits 9–16 seconds after a fresh accepted snapshot; the first
bird waits 24–42 seconds. Subsequent same-kind gaps are 28–52 and 42–86 seconds
after each clip. A four-minute deterministic scheduler trial produced eight
starts and a longest all-voice silence of 47.25 seconds. The scheduler discards
missed events after a stalled frame, menu, disconnect, focus loss or Android pause.
Reopening the gates alone is insufficient: a new accepted snapshot starts a new
quiet interval. A same-tick snapshot from a paused herd remains valid.

Sound on/off lives beside Server address, only in the existing menu. Both
buttons have 64-logical-pixel touch targets. The saved Return action and expanded
server field still fit a verified 720×1280 portrait. The preference uses its own
audio.cfg and does not mix with invitation credentials. Tests recreate the
muted preference and exercise twenty focus, background, menu and disconnect
cycles each, including actually started streams, rejected snapshots, duplicate
receipts, simultaneous voices and fixed cache/player allocations.

PCM checks establish faded endpoints, bounded peak, no clipping and negligible
DC offset. They do not establish pleasant sound. These short tonal bird calls
can feel whistle-like, and two wind variants may eventually become recognizable.
Phone-speaker/headphone listening and two-person playtesting remain needed;
the sounds are original synthesis, not field recordings. Keep the small mute
option and long silence while gathering that feedback.

The first actual Android interruption recording rejected the initial playback
implementation despite its passing scene tests. A roughly 120 ms fragment of
wind reappeared immediately on resume, before the fresh sound deadline. Its
waveform continued the interrupted source (correlation 0.917), and Android's
independent output power history corroborated it. Turning off system touch
sounds did not remove it. The pinned [Godot 4.6.3 OpenSL driver](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/android/audio_driver_opensl.cpp)
pauses its native queue without clearing already mixed PCM. Another scene timer
or bus mute cannot remove those queued samples.

The replacement keeps scheduling and synthesis platform-neutral but uses two
disposable static [Android AudioTracks](https://developer.android.com/reference/android/media/AudioTrack)
through Godot's built-in Java bridge. Interruption pauses and releases both
native voices; no old track is resumed, reloaded or looped. Other platforms keep
the two Godot players. Android distance attenuation and restrained stereo
placement use the herder's location and bearing when a brief bird phrase starts.
An API failure releases both slots and leaves the session quiet, without falling
back to the affected engine queue. The unchanged cached bank is 570,210 bytes;
two simultaneous static sample buffers add at most 301,644 bytes, excluding
transient JNI copies and Android's own overhead. No custom engine, Gradle plugin,
media permission or system-volume change is part of this implementation.

Capture validation also found a separate emulator recording problem: some runs
delivered only about one sixteenth of the PCM expected from their packet cadence.
Those recordings are rejected. Missing payload is not silence, and an ordinary
Android standby gap is explicitly distinguished from under-rate arriving packets.
The replacement passed an independent guest-side, output-only FLAC recording.
All 5,726,208 stereo frames were decoded at 48 kHz (119.296 seconds), without
the earlier sustained capture loss. One complete wind follows the first return.
A later wind starts afresh, is interrupted about two seconds into its 4.6-second
source, and is never resumed. Every sample in the final 29.296 seconds is exactly
zero, spanning backgrounding and the second return. That recording ends before
the next fresh wind after the second return; it does not claim that later onset.
This directly checks the former short stale-tail failure rather than only the
scene's stopped flags. Android's independent native-track history also records
the interrupted static voice being destroyed with unplayed frames remaining.

A second output recording contains 64.768 seconds of decoded, exactly zero PCM
while opening settings, selecting Sound off, force-stopping/relaunching the app,
and returning to the saved Cloud herd. Portrait captures before and after
restart both show the saved off preference. The default phone media volume was
left unchanged during these acceptance recordings. A further 454 fake-native
regressions exercise exact PCM writes, two-slot ownership, partial-write/API
errors, immediate cleanup of both slots, lifecycle interruption and teardown.
They supplement, not replace, the actual Android output checks.

## Juniper Shore — room to linger

The seventh place is a dry crescent around an Alpine bay, with three broad
grassy clearings, a stony beach and an open saddle between unequal mountain
massifs. The lake and steep grassy shoulders explain the limits. There is no
gate, swimming, fall penalty, destination objective or arrival message. Every
clearing is a reasonable place to stop. The actual walking mesh has 2.29 units
of relief; actors and touch picking use that same surface.

Version 5 adds its own canonical shoreline union and new-world spawns. Six
path anchors and three clearing disks define the complete walking footprint.
An eight-node graph retains safe routes around the bay across disconnects and
restarts. Normal dog-command simulations bring all ten sheep outward at tick
685 and back at 1895; a genuine dog-created split is retrieved at tick 1464.
No positions, speeds or collision boundaries are changed to make them pass.
All six older landscape traces remain fixed, including a frozen pre-Juniper
700-tick Cloud reference. State, layouts and route anchors compare exactly;
cross-platform actor coordinates retain the existing tightly bounded allowance.

A deeper Linux boundary sweep rejected the first routing implementation. One
legal capsule-edge point was accepted by nearest-distance membership but could
see no graph anchor because the rectangle projection differed by a last bit.
The v5-only correction first proves chords inside the same closed disk or
capsule by convexity, using exactly the walkability predicate. Other chords
must pass the existing complete analytical union test in both directions.
It adds no collision epsilon, coordinate movement or Cloud change. Fourteen
shared literal regressions include the exact failing Linux point. On Linux
amd64 and arm64, all generated legal edge points reach anchors, 2,500 actual
movement routes finish and 20,000 tested pairs are symmetric. Ordinary flock
journey and split-retrieval tick totals remain unchanged.

The first actual portrait views had an overly flat-looking lake and a regular
row of similarly shaped trees. The focused art pass introduces 21 junipers in
six uneven groups with spreading, crooked and wind-shaped silhouettes. Full
crown triangles stay outside the walking union. One opaque, non-displacing
water shader supplies slow, restrained tonal and normal changes, without a
reflection, transparency layer or new geometry. A same-camera Android water
region changes only a few grayscale levels between inspected frames; this
establishes rendered change, not the subjective comfort of an animation.

The original ground and clipped water arrays remain byte-identical on the
verified macOS/arm64 editor. Other platforms pin the unchanged Juniper-only
geometry source and run all numerical mesh checks; a Mac raw-byte golden is
not presented as universal libm bit identity. The refined full scene has
92,088 triangles, below the existing 100,000 limit. Tests cover all 7,050 water
triangles, 2,016 crown triangles, actual portrait picking, lower-frame coverage
and animal visibility. Geometry counts are not real-phone FPS measurements.

The signed Android preview was walked from the true right-follow extreme
through the middle and back to the true left extreme, using ordinary taps.
Both herders, both corgis and the flock remain readable at the left clearing;
the paired view has no invite panel or permanent action bar. The actual short
720×1280 logical portrait also fits seven choices, saved Return, expanded server
address and the real Sound row. Remaining criticism is explicit: broad rear
slopes are too smooth, the near-right shoulder is oversized and has a coarse
crease, and the wide follow deadzone can leave sheep off-screen when returning
through the middle. There are no observed new mesh holes or tree obstructions.
The second connected peer is automated; two-human play and phone performance
feedback are still needed.

The Android play check also exposed a contextual-control bug: a corgi could
wander out of petting range while its menu was open, causing Pet to disappear
and Go to expand into the same tap location. The fixed panel always allocates
four slots and disables Pet out of reach. Activation rechecks the current
distance too; the entire panel still closes after use. A 107-check GUI regression
first reproduces the old accidental Go action, then tests actual pointer presses
and releases on both portrait aspects with near, far and missing actors, a dog
moving during a held tap, and stale enabled state. Unavailable Pet cannot become
Go or a ground movement. A valid near tap sends exactly one Pet interaction.

The final signed preview also passed that near/far test on Android. Mochi was
moved normally out of reach while the panel remained open; tapping the original
Pet position left the disabled panel unchanged instead of opening Go. Returning
him nearby and tapping again produced an authoritative petting herder and happy
dog. The same herd and accepted input sequence survived the APK reinstall and
Return. The [quiet east-clearing image](images/juniper-shore.png) is an unedited
capture from that final preview connected to the candidate Go server.

A fresh herd created through Android also completed the full journey on the
candidate server. An automated second herder used ordinary Go commands to
position the two dogs; the primary stayed at its spawn for the outward leg.
All ten original sheep reached the east clearing after 695 live ticks and
returned west after another 766 ticks of return commands, with a quiet photo
pause between legs. Both humans stayed at the east end during the return drive.
After the dogs retreated, all ten resumed grazing at each end. These are test
observations, not player-facing timers or scores. No actor state was overwritten,
no sheep were replaced and `settled` remained zero throughout.
