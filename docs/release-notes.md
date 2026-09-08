An early playable prototype of Corgi Herding: two herders, two shared corgis and ten sheep, with five quiet landscapes.

New place: Canyon Oasis. Wander a sheltered dry saddle beneath warm sandstone walls, with cactus outcrops, a distant spring and green grazing ground. Two paths pass around low broken rock; there is no river, fence or gate here. Take the flock together or regroup sheep from either side. Both herders still command both corgis, with no new button or objective.

Choose among Alpine valley, Cactus canyon, Larch Hollow, Sunward Orchard and Canyon Oasis on the portrait start screen. Each herd keeps its immutable layout, animals and progression. Previous APKs retain access to their supported landscapes; Oasis needs this update. Version negotiation and one bounded rollback retry preserve the saved invitation.

Oasis herders and dogs retain their chosen route around the rock. A disconnected herder pauses and resumes that walk after returning, including a server restart. Reconnection now also recovers correctly when the last tap was predicted locally but lost before the server received it. Sheep remain guided by dog pressure rather than automatically solving the route to pasture.

Sunward Orchard remains a place for a gentler detour: two curious sheep can stop for fallen apples. Let them finish or call either corgi. Their finite snack is remembered, so it never becomes a repeating chore. A lowered head supplies the feedback; no snack meter, quest or timer.

The quiet arrival acknowledgement now disappears automatically. It does not repeat when a sheep wanders back or appear when resuming an already settled herd.

Play in portrait. Both players use the same server address: one chooses a landscape, creates a herd and shares its invite code, the other joins. Tap the open ground to walk; tap a corgi to show its Come/Stay/Go menu, which closes after use. Tap the nearby gate to open it, or your herder to sit. No permanent joystick or command bar. Mountain ranges and canyon vistas extend beyond the accessible valley, with natural terrain boundaries and gentle camera following. There is no score or timer.

The landscape now has visible ground relief: rolling grazing terraces and an asymmetrical rocky valley, with layered evergreens and gold/rust foliage in the middle distance. Animals follow the displayed terrain height, and ground taps account for the surface height on slopes. The [supplied landscape photographs](https://github.com/Nielk74/corgi-herding/blob/main/docs/design.md#landscape-direction) guide composition only; they are not bundled game assets. This remains a stylized procedural prototype. The authoritative Go simulation remains on a 2D plane; collision, routes and interactions use each herd's versioned layout.

Warmer sunlight, cooler ambient light and deeper shadows give the terrain more contrast. Ambient occlusion anchors animals and rocks, distant haze separates the ridges, and two soft shader beams suggest sunlight through the valley. This Android build uses raster lighting and screen-space effects; hardware ray tracing is not enabled. These settings still require device performance profiling.

The initial hosted server is a LAN prototype. Both phones need access to the host network. A custom server URL can be entered on the start screen. See [deployment instructions](https://github.com/Nielk74/corgi-herding/blob/main/docs/deployment.md).

APK updates use one persistent release signing identity. Server binaries for macOS Apple Silicon and Linux amd64/arm64 accompany this build; `SHA256SUMS` covers all downloadable binaries.

This milestone uses simple procedural geometry and local file checkpoints. Puppy adoption, training progression, a persistent journey and production account security are later milestones. Human playtesting on two phones is still needed to establish whether the herding feels good.
