# Corgi Herding protocol v1

The Go server owns a 20 Hz simulation on an X/Y plane; Godot maps Y to Z.
HTTP base is user configurable (default http://127.0.0.1:8790).

`GET /healthz` returns `{status,version,protocol:1,layout_version:1,layout_versions:[1,2,3],sessions}`.
The singular capability deliberately remains 1 so existing clients can still
visit their version 1 herds. New clients choose the highest known advertised
`layout_versions` entry, falling back to the singular field on older servers.
Clients can probe this before authentication: older servers omit `layout_version`
and strictly reject unknown auth fields, so omit the capability when connecting
to those servers. Never discard saved credentials merely because a server has
not yet upgraded to support layout negotiation.
`POST /api/herds` with `{name:string,landscape?:"alpine"|"cactus"|"larch"|"orchard"|"oasis"}` creates a two-person herd and returns
`{code,player_id,token}`. `POST /api/herds/{code}/join` with `{name:string}`
returns the same fields for the second player. Save these credentials locally.
No third member is accepted. Names are limited to 24 characters.
Omitting `landscape` selects `alpine`; unsupported values return HTTP 400.
The selected landscape belongs to the herd, appears in every snapshot, and
survives reconnects and server restarts. Joining inherits the existing landscape;
it does not accept a landscape override. Layout version 1 preserves the same
playable bounds, river/fence X coordinates, speeds, and opening widths. Each
herd has an immutable layout included in every snapshot:

| Landscape | `layout.version` | `layout.bridge_y` | `layout.gate_y` |
| --- | --- | --- | --- |
| `alpine` | 1 | 0 | 0 |
| `cactus` | 1 | 0 | 0 |
| `larch` | 1 | -4 | 4 |
| `orchard` | 2 | 3 | 2 |
| `oasis` | 3 | unused (0) | unused (0) |

Sunward Orchard adds an immutable forage zone; other layouts omit `forage`:

```json
{"version":2,"bridge_y":3,"gate_y":2,"forage":{"id":"windfall","center":{"x":-7,"y":-5},"radius":2.2}}
```

Canyon Oasis replaces the playable river and fence with one impassable rock.
Its legacy zero-valued bridge/gate fields are unused, not hidden obstacles:

```json
{"version":3,"bridge_y":0,"gate_y":0,"rock_pass":{"center":{"x":0,"y":0},"radius":3.4}}
```

Only Oasis includes `rock_pass`. It has no gate or forage zone. `interact/gate`
returns a recoverable no-gate error and must not appear in its contextual UI.

Connect `GET /api/herds/{code}/ws` (WebSocket, no credentials in URL), then send
`{type:"auth",player_id,token,layout_version:3}` within 5 seconds when the server
advertises version 3. Server replies with snapshots.
Reconnection uses the same credentials; players remain in the herd. A replacement
connection supersedes the old connection. Never expose tokens in snapshots/logs.
Omitted/zero `layout_version` is legacy support for centered Alpine/Cactus
layouts only. Capability 1 accepts all version 1 layouts; capability 2 accepts
versions 1 and 2; capability 3 accepts versions 1, 2 and 3. Authenticated clients lacking support for their herd's layout
or sending an unknown capability receive `{type:"error",code:"update_required",message:...}`
followed by WebSocket close 4002, before they receive a snapshot or replace an
existing connection. Clients must preserve credentials and offer an update;
this is not an authentication failure. Invalid credentials still close with 1008.
Transient actor/shutdown failures close with 1013 so clients can reconnect.
A policy close does not prove a saved token has expired: keep it recoverable
while pausing repeated failures in settings. The client allows one bounded
health re-probe when a server rollback may have changed the auth capability.

Client messages:

```json
{"type":"move","seq":1,"target":{"x":-6,"y":2}}
{"type":"command","dog_id":"mochi","command":"come"}
{"type":"command","dog_id":"maple","command":"stay"}
{"type":"command","dog_id":"mochi","command":"go","target":{"x":2,"y":0}}
{"type":"interact","action":"gate"}
{"type":"interact","action":"pet","dog_id":"mochi"}
{"type":"interact","action":"sit"}
```

Server messages:

```json
{"type":"snapshot","tick":100,"code":"ABCDEF","landscape":"alpine","layout":{"version":1,"bridge_y":0,"gate_y":0},"gate_open":false,"settled":0,"players":[{"id":"p1","name":"A","position":{"x":-10,"y":0},"target":{"x":-10,"y":0},"seq":1,"state":"idle","connected":true}],"dogs":[{"id":"mochi","name":"Mochi","position":{"x":-8,"y":0},"state":"wander","command":""}],"sheep":[{"id":"s1","position":{"x":-5,"y":0},"state":"grazing","group":0}]}
{"type":"error","message":"..."}
```

In Orchard, up to two calm sheep within 4.7 units of the windfall center can
become curious. Only those two individuals are assigned over the herd's lifetime,
so there is no queue of repeated distractions. Assigned sheep include optional
persisted progress in snapshots (all version 1 sheep omit this field):

```json
{"id":"s1","position":{"x":-7,"y":-4},"velocity":{"x":0,"y":0},"state":"nibbling","group":0,"forage":{"zone_id":"windfall","remaining_ticks":60,"satiated":false}}
```

`foraging` means approaching; `nibbling` means eating, communicated through animal
body language, never a countdown UI. A nibble takes 80 active simulation ticks in
total. Any dog within 4.1 units immediately interrupts it; a herder within 2 units
also prevents calm feeding. Progress pauses rather than resetting. Once finished,
`remaining_ticks` is 0 and `satiated` is true; that sheep never returns for more.
Assignment, partial progress and satiation survive reconnects and checkpoints.
Sheep may always be guided away by either shared dog; waiting is optional.

World bounds: X [-17,17], Y [-11,11]. In versions 1 and 2 the river occupies X [-1.5,1.5],
crossable only where `abs(y-layout.bridge_y) <= 1.85`. Fence collision occupies
`abs(x-6) < 0.18`; its opening is passable only when `gate_open` and
`abs(y-layout.gate_y) <= 1.8`. Gate interaction requires a player within
3 units of `(6,layout.gate_y)`. Sheep in X>8 are counted settled but can wander again.
Player speed 4 units/s. Two dogs and ten sheep. Shared dog control.
Player and dog paths visit the bridge then gate when travelling east; returning
from the pasture visits the gate before the bridge. Both clients must use the
snapshot layout for prediction, interaction picking, and terrain presentation.

### Oasis navigation

Version 3 is walkable outside the rock's radius 3.4 and inside the unchanged
bounds. Every movement substep, at most 0.08 units, checks the entire segment
against the circle as well as its destination. Line of sight uses squared
nearest-point distance `>= radius * radius`, without a collision-relaxing epsilon.
The same rules apply to all actors. Sheep locally redirect inward movement around
the rock under pressure; there is no autonomous attraction to the east pasture.

Herders and dogs retain an optional `route:[{x,y},...]` of remaining anchors,
omitted when empty and always omitted on version-1/2 worlds. The final destination
remains in `target`, not in the queue. Eight version-defined anchors have order
E, NE, N, NW, W, SW, S, SE. Axis coordinates are `5.2` and `-5.2`; diagonal
coordinates are `3.676955262170047` and its negative. They are centered on the rock.

Planning uses those eight anchors plus start node 8 and target node 9, with
visible segments weighted by Euclidean distance. Dijkstra visits the lowest-index
node on ties within `1e-9`; it relaxes an edge only when the candidate is less
than the existing distance minus `1e-9`. [Shared planner fixtures](rock-routes.json)
list expected anchor indices for normal, tied and near-boundary cases.

Before each movement step, consume anchors within `0.08` units. Direct visibility
to the target clears the queue. Otherwise keep it unless empty, the first segment
is blocked, or the last anchor no longer sees the target (a moving `come` caller).
New destinations plan a new queue; repeated identical targets retain the chosen
bypass. Movement retains the existing speeds and collision substeps.

Oasis disconnections pause herders without discarding their target, sequence or
route; reconnects and restarts can resume that walk. Version-1/2 herders retain
their original stop-on-disconnect behavior. All worlds pause when nobody is
connected. Saved queues must contain at most eight unique canonical anchors,
with safe initial, intermediate and final segments; unsafe state is rejected
before any actor starts. Routes are never client-authoritative input.

Older checkpoints without a landscape field load as `alpine`; existing Alpine
and Cactus saves without a layout migrate to centered version 1 without changing
animal/player identities, credentials, positions, gate state, or simulation tick.
Unknown saved layout versions, noncanonical layouts, impossible forage state,
unsafe rock routes and actors inside rock fail startup without overwriting the
save. Existing version-1/2 simulation and snapshot fields are unchanged.
There is no account service or puppy progression
system yet.
