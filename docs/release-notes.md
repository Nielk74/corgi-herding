An early playable prototype of Corgi Herding: two herders, two shared corgis and ten sheep, with four quiet landscapes.

New place: Sunward Orchard. Wander shallow grazing terraces beneath broad apple trees, with a view toward rolling farmland. Two curious sheep may stop for fallen apples. Let them finish, or call on either corgi to help them rejoin the flock. Their small snack is remembered across reconnects and server restarts, so it never becomes a repeating chore. A lowered head communicates feeding; there is no snack meter, quest or timer.

Choose among Alpine valley, Cactus canyon, Larch Hollow and Sunward Orchard on a two-row portrait selector. Each place keeps its authoritative bridge/gate layout, animals and progression. Previous APKs retain access to their supported landscapes; Orchard needs this update. Version negotiation and one bounded rollback retry preserve the saved invitation.

The quiet arrival acknowledgement now disappears automatically. It does not repeat when a sheep wanders back or appear when resuming an already settled herd.

Play in portrait. Both players use the same server address: one chooses a landscape, creates a herd and shares its invite code, the other joins. Tap the open ground to walk; tap a corgi to show its Come/Stay/Go menu, which closes after use. Tap the nearby gate to open it, or your herder to sit. No permanent joystick or command bar. Mountain ranges and canyon vistas extend beyond the accessible valley, with natural terrain boundaries and gentle camera following. There is no score or timer.

The landscape now has visible ground relief: rolling grazing terraces and an asymmetrical rocky valley, with layered evergreens and gold/rust foliage in the middle distance. Animals follow the displayed terrain height, and ground taps account for the surface height on slopes. The [supplied landscape photographs](https://github.com/Nielk74/corgi-herding/blob/main/docs/design.md#landscape-direction) guide composition only; they are not bundled game assets. This remains a stylized procedural prototype. The authoritative Go simulation remains on a 2D plane; collision, routes and interactions use each herd's versioned layout.

Warmer sunlight, cooler ambient light and deeper shadows give the terrain more contrast. Ambient occlusion anchors animals and rocks, distant haze separates the ridges, and two soft shader beams suggest sunlight through the valley. This Android build uses raster lighting and screen-space effects; hardware ray tracing is not enabled. These settings still require device performance profiling.

The initial hosted server is a LAN prototype. Both phones need access to the host network. A custom server URL can be entered on the start screen. See [deployment instructions](https://github.com/Nielk74/corgi-herding/blob/main/docs/deployment.md).

APK updates use one persistent release signing identity. Server binaries for macOS Apple Silicon and Linux amd64/arm64 accompany this build; `SHA256SUMS` covers all downloadable binaries.

This milestone uses simple procedural geometry and local file checkpoints. Puppy adoption, training progression, a persistent journey and production account security are later milestones. Human playtesting on two phones is still needed to establish whether the herding feels good.
