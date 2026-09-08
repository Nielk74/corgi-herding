# Corgi Herding — design and technical direction

## North star

Does this make the two players feel more like they are raising, understanding
and working with these animals together?

The intended feeling is: “We are taking care of this little world together.”
Animal attachment matters as much as mechanical progress. Both humans can
command both dogs. Internally, use “herd” or “team”; do not assume a romantic
relationship between players.

## Experience

A cozy, minimalist, exactly two-player cooperative Android game with a fixed
semi-3D camera composed for a portrait phone. A couple of herders raises two corgis, cares for a
persistent flock, and gradually travels toward summer pasture. Touch-to-move
and a small command interface keep the world readable. Later platforms may
include tablets, ChromeOS, iOS and desktop.

Portrait is a requirement, not a rotated landscape layout. Use the tall frame for
layered scenery above readable animals. A gentle horizontal camera follow reveals
the valley without shrinking the flock. Tap ground to walk, a corgi for its small
temporary command panel, the nearby gate to open it, and your herder to sit.
Hide commands after use; no permanent joystick, dog tabs, action bar or tutorial
text. Invitations disappear once both herders are connected. Keep server settings
inside the menu and show connection status only when attention is needed.

Prepare → explore → encounter a herding situation → coordinate humans and
dogs → reach pasture or camp → relax, care and train → continue the journey.
Sessions need not complete an objective. Petting a dog, sitting together,
throwing a stick and watching sheep graze are valid reasons to play.

Avoid combat, harsh failure, timers, quest trackers, giant floating buttons,
health bars, XP spam, currencies, daily pressure, loot boxes and paid stat boosts.
Use ears, posture, barks, whistles, pointing and environmental composition to
communicate. Sheep that wander off become a new situation instead of a lost run.

## Milestone 1 — Ten Sheep and a Gate

One meadow, one river with a bridge, one gate and a resting pasture. Two players,
two corgis, ten sheep. Invite code host/join, touch movement, Come/Stay/Go,
dog pressure on sheep, gate interaction, sitting and petting. Soft boundaries
and open-ended herding; no reward popup. The gate opening and sheep settling
are the reward.

This deliberately small prototype establishes the loop before progression.
The acceptance test is two people naturally coordinating: “Go right”, “Wait,
call your dog”, “We lost one!” Human playtesting is required; simulation tests
alone cannot establish that the game is fun.

## Landscape direction

The walkable space should feel like a sheltered part of a broad landscape.
Extend terrain, paths, rivers and vegetation beyond the interactive valley;
compose layered mountain silhouettes and distant ridges into the fixed view.
Avoid the visible edges of a floating rectangular board. Steep rock faces,
dense woods, riverbanks and canyon slopes explain which routes are accessible.
Keep the sheep, dogs, bridge and gate legible in the foreground.

The grazing ground itself needs visible relief: rolling terraces, rounded
shoulders, shallow hollows and raised riverbanks. Compose an asymmetrical rocky
valley with slopes of different heights and shapes, a winding river below, and
distant peaks visible through the opening. The mountain backdrop should connect
visually to the ground where the animals walk. Keep the immediate herding routes
gentle enough to read clearly in portrait.

Build depth with several vegetation layers. Dark evergreen groups establish the
slopes, while gold and rust foliage marks parts of the middle distance. Let rock
faces, trees and meadow openings vary in density. The supplied photographs guide
landforms, color and composition; the game remains a stylized procedural
prototype, with no claim of photorealism.

Render herders, dogs, sheep and their contact shadows at the local terrain height.
Resolve ground taps against that displayed surface so an uphill or downhill tap
selects the point the player sees. Keep the bridge and gate readable where they
meet the ground. These heights are presentation only: the authoritative Go
simulation still uses its existing 2D coordinates, movement, flocking and
crossing rules. No terrain-height data is added to the network protocol or saves.

Supplied visual references, used only for inspiration:

- [Deep rocky valley and winding river](https://res.cloudinary.com/enchanting/q_70,f_auto,w_5568,h_3712,c_fit/exodus-web/2024/02/EX-HP-Hero-NAM-1.jpg): unequal slopes, exposed stone, and a strong foreground-to-distance valley opening.
- [Rolling alpine meadow and distant peaks](https://www.thetrainline.com/cms/media/1479/switzerland-summer-landscape-the-alps-backdrop.jpg?mode=crop&width=1080&height=1080&quality=70): soft grazing terraces, tree groups and broad mountain scale.
- [Steep rock with autumn forest, supplied thumbnail](https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSQgap-2fe7aR_Rn5HCM0OiEQWwvUw9y38pvvD3YrY9XFgsTsNI0juY1_k&s=10): dark evergreens mixed with gold and rust foliage beneath high rock faces.

These links document visual direction. The photographs are not game assets and
are not included in the repository or APK.

Lighting should make the relief readable through warm afternoon sunlight,
cooler ambient fill, and clear shadows under animals, trees and rocks. Keep
highlight headroom for white sheep and pale stone. A small contrast adjustment
supports the authored palette; haze starts beyond the nearby grazing ground
and separates distant ridges.

`ValleyLighting` uses one directional shadow map, low-quality SSAO at half
resolution, depth fog, and two faint world-space shader quads that suggest
sunlight through the valley. Their ordinary depth test hides them behind opaque
terrain. These are raster effects; hardware ray tracing, ray-marched light
shafts and volumetric fog are not enabled. Godot 4.6 documents SSAO and depth fog
for the [Compatibility renderer](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html).
The effect count is kept small, but frame time still needs measuring on target
phones before making a performance claim.

Five selectable landscapes offer quiet cooperative herding: an Alpine
valley with snowy peaks, a cactus canyon with warm mesas and saguaro cacti,
and sheltered Larch Hollow with gold/rust foliage, a sloping rest shelf and
an offset bridge and gate, plus Sunward Orchard with shallow terraces and broad
apple trees. Larch's gentle S-shaped route changes where the pair coordinates.
The orchard offers a quieter decision: let two sheep finish their fallen apples
or use a dog to bring them back. A lowered head communicates feeding; completed
snacks persist so this small detour never becomes a repeating chore. Neither
place adds a timer, score or loss condition. Canyon Oasis changes the geography
itself: two dry paths around broken stone open toward green pasture. There is
no gate or river to cross, and sheep remain responsive to the dogs rather than
automatically choosing a route. The pair can stay together or retrieve a split
flock from either side. Low rock keeps the animals visible in portrait.
The creator chooses the location; the server persists it for both players.
Large vistas are part of the presentation. Continuous free travel between
regions belongs to a later journey milestone.

## Animals

Sheep combine explicit states (grazing, alert, moving, fleeing, settling) with
cohesion, separation, alignment, avoidance of dogs/players/terrain and gentle
destination influence. A proximity graph identifies temporary flock groups.
The game should eventually make individual sheep recognizable.

Dogs use small state machines and utility tendencies. Personality affects
energy, curiosity, confidence, attention, independence, affection, patience,
play and herding instinct. Learned commands have familiarity and reliability,
not binary unlocks. Trust and affection are tracked separately toward each
player, communicated by behavior instead of percentages.

Training should happen through repetition, successful commands, rewards,
affection and context. Progress should be visible within a normal session.
Quirks (loving sticks, sleeping belly-up, disliking bridges) create attachment.
Adoption should show puppies behaving naturally, without numeric stat cards.

## Journey and presentation

Connected handcrafted dioramas: spring farm, countryside, forest, river valley,
village, foothills and mountain pasture. Geography and animal behavior create
situations: narrow bridges, orchard distractions, fog and mountain paths.
Never turn the game into timed puzzle boards.

Camps are places in the world for saving, training, resting, washing muddy dogs,
fetch, cooking and quiet company. Short sessions can be 2–5 minutes, encounters
10–15 minutes and journey segments 20–40 minutes. No forced real-world waits.
Sparse music and expressive environmental/animal sound leave room for silence.

## Technical foundation

- Godot 4.6.3 standard, GDScript, Android first; compatible mobile renderer.
- Fixed 3D presentation with terrain relief and surface-aware touch over unchanged 2D authoritative gameplay coordinates.
- Go modular monolith; one actor per active herd; 20 Hz simulation.
- HTTP for invitations; authenticated WebSocket JSON for gameplay.
- Client movement feedback and reconciliation; animal/remote-player interpolation.
- Bounded input queues, two-member limit, opaque reconnect tokens, snapshot validation.
- Seeded simulation for reproducibility. File checkpoints for the initial spike.
- PostgreSQL when persistent progression begins. Redis only with a concrete need.
- Single binary deployment, optional Compose. No microservices or Kubernetes.

Android backgrounding and changing networks are normal. Reconnect using locally
saved credentials and receive a full authoritative snapshot. Keep herds intact
while both players are offline and pause their simulation. Never log tokens.
Initial controls and anonymous identities are appropriate for trusted prototype
players; production public hosting needs further access control and abuse work.

## Subsequent milestones

1. Playtest the herd: tune pressure, clustering, navigation, feedback and mobile controls; verify 30/60 FPS on target phones.
2. Puppy attachment: adoption, names, Come/Stay training, rewards, distractions, affection and play.
3. Persistent journey: PostgreSQL, persistent dogs/flock, camp, three regions and campaign recovery.
4. World character: stronger animations, dog vocalizations, wildlife, weather, individual sheep, discoveries and photo mode.
5. Richer commands and customization: circling, pushing, bringing strays, guarding openings and camp decoration.

Long-term diagnostic tools include flock/pressure/navigation overlays, server
and predicted positions, input replays, tick timings and session/network
metrics. The first performance target is two people, two dogs, 20–40 sheep,
simple vegetation, sparse transparency and limited lighting complexity.

## Verified engine references

[Godot 4.6 Android export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html)
documents signing and SDK requirements; [command-line exports](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)
support CI builds. Editor and templates are pinned together and their official
release hashes are checked by `tools/install-godot.sh`.

The supplied long-form plan contained truncated passages and missing sections.
This document preserves the clear direction without inventing the missing text.
