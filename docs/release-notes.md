An early playable prototype of Corgi Herding: two herders, two shared corgis and ten sheep, with six quiet landscapes.

New in this build: a small environmental sound layer. Short wind breaths and occasional distant bird phrases leave long gaps of silence. No music loop, command beeps or animal chorus. At most two sounds play together, using a small bank of original synthesized samples. The listener follows the herder, not the high camera. A Sound on/off toggle fits beside Server address in the existing menu and saves separately from the herd invitation.

Sound stops on menu, disconnect, background or focus loss. Returning requires a fresh accepted snapshot and a new quiet delay; missed sounds are discarded. This is an early atmosphere experiment. Measured output and lifecycle checks cannot establish subjective comfort on phone speakers, and human listening feedback is still needed.

Cloud Pasture remains the newest place. A broad grassy ridge climbs through three resting shelves above an Alpine valley, a distant tarn and snow peaks. Wander uphill, bring the flock back down, or sit halfway with the corgis. Steep flanks frame the gentle ground without falls. There is no bridge, gate, new control or arrival prompt.

Choose among Alpine valley, Cactus canyon, Larch Hollow, Sunward Orchard, Canyon Oasis and Cloud Pasture on the portrait start screen. Each herd keeps its immutable layout, animals and progression. Previous APKs retain access to their supported landscapes; Cloud needs this update. Version negotiation and one bounded rollback retry preserve the saved invitation.

Cloud herders and dogs follow the ridge rather than cutting across steep ground. A disconnected herder pauses and resumes the accepted walk after returning, including a server restart or a lost predicted tap. Sheep remain guided by dog pressure rather than automatically solving the route to pasture. All three shelves are places to graze calmly.

Sunward Orchard remains a place for a gentler detour: two curious sheep can stop for fallen apples. Let them finish or call either corgi. Their finite snack is remembered, so it never becomes a repeating chore. A lowered head supplies the feedback; no snack meter, quest or timer.

Canyon Oasis retains both dry paths around its rock and the other landscapes keep their original behavior. Frozen full-simulation comparisons guard Orchard and Oasis, alongside the older landscape regressions. Exact route anchors, animal states and input sequences stay unchanged; only tiny cross-platform differences in actor coordinates are tolerated.

Play in portrait. Both players use the same server address: one chooses a landscape, creates a herd and shares its invite code, the other joins. Tap the open ground to walk; tap a corgi to show its Come/Stay/Go menu, which closes after use. Tap the nearby gate to open it, or your herder to sit. No permanent joystick or command bar. Mountain ranges and canyon vistas extend beyond the accessible valley, with natural terrain boundaries and gentle camera following. There is no score or timer.

The landscape now has visible ground relief: rolling grazing terraces and an asymmetrical rocky valley, with layered evergreens and gold/rust foliage in the middle distance. Animals follow the displayed terrain height, and ground taps account for the surface height on slopes. The [supplied landscape photographs](https://github.com/Nielk74/corgi-herding/blob/main/docs/design.md#landscape-direction) guide composition only; they are not bundled game assets. This remains a stylized procedural prototype. The authoritative Go simulation remains on a 2D plane; collision, routes and interactions use each herd's versioned layout.

Warmer sunlight, cooler ambient light and deeper shadows give the terrain more contrast. Ambient occlusion anchors animals and rocks, distant haze separates the ridges, and two soft shader beams suggest sunlight through the valley. This Android build uses raster lighting and screen-space effects; hardware ray tracing is not enabled. These settings still require device performance profiling.

The initial hosted server is a LAN prototype. Both phones need access to the host network. A custom server URL can be entered on the start screen. See [deployment instructions](https://github.com/Nielk74/corgi-herding/blob/main/docs/deployment.md).

APK updates use one persistent release signing identity. Server binaries for macOS Apple Silicon and Linux amd64/arm64 accompany this build; `SHA256SUMS` covers all downloadable binaries.

This milestone uses simple procedural geometry and local file checkpoints. Puppy adoption, training progression, a persistent journey and production account security are later milestones. Human playtesting on two phones is still needed to establish whether the herding feels good.
