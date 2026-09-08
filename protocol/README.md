# Corgi Herding protocol v1

The Go server owns a 20 Hz simulation on an X/Y plane; Godot maps Y to Z.
HTTP base is user configurable (default http://127.0.0.1:8790).

`GET /healthz` returns `{status,version,protocol:1,layout_version:1,layout_versions:[1,2,3,4,5],sessions}`.
The singular capability deliberately remains 1 so existing clients can still
visit their version 1 herds. New clients choose the highest known advertised
`layout_versions` entry, falling back to the singular field on older servers.
Clients can probe this before authentication: older servers omit `layout_version`
and strictly reject unknown auth fields, so omit the capability when connecting
to those servers. Never discard saved credentials merely because a server has
not yet upgraded to support layout negotiation.
`POST /api/herds` with `{name:string,landscape?:"alpine"|"cactus"|"larch"|"orchard"|"oasis"|"cloud"|"juniper"}` creates a two-person herd and returns
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
| `cloud` | 4 | unused (0) | unused (0) |
| `juniper` | 5 | unused (0) | unused (0) |

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

Cloud Pasture instead confines movement to one winding ridge and three quiet
shelves. It has no playable river, fence, gate, rock obstacle or forage zone:

```json
{"version":4,"bridge_y":0,"gate_y":0,"ridge":{"spine":[{"x":-10,"y":0},{"x":-2,"y":-5},{"x":5,"y":1},{"x":11,"y":4}],"half_width":3.6,"shelves":[{"center":{"x":-10,"y":0},"radius":6.2},{"center":{"x":-2,"y":-5},"radius":4.8},{"center":{"x":11,"y":4},"radius":5.2}],"rest":{"center":{"x":11,"y":4},"radius":4.6}}}
```

Only Cloud includes `ridge`. Its ordered spine, shelf disks and rest disk are
immutable canonical data, not editable navigation hints.

Juniper Shore is a gentle dry crescent around a lake, with three quiet clearings.
It has no gate, bridge, fence, rock obstacle, forage or rest/finish region:

```json
{"version":5,"bridge_y":0,"gate_y":0,"shore":{"path":[{"x":-11,"y":2},{"x":-8,"y":-3},{"x":-3,"y":-6},{"x":4,"y":-6},{"x":9,"y":-2},{"x":11,"y":4}],"half_width":3.6,"clearings":[{"center":{"x":-11,"y":2},"radius":5.2},{"center":{"x":-1,"y":-6},"radius":4.5},{"center":{"x":11,"y":4},"radius":4.8}],"lake_side":"left"}}
```

Only Juniper includes `shore`. `lake_side` describes presentation to the left of
the ordered path, not additional collision. `settled` always remains 0 here.

Connect `GET /api/herds/{code}/ws` (WebSocket, no credentials in URL), then send
`{type:"auth",player_id,token,layout_version:5}` within 5 seconds when the server
advertises version 5 and the client implements it. Server replies with snapshots.
Reconnection uses the same credentials; players remain in the herd. A replacement
connection supersedes the old connection. Never expose tokens in snapshots/logs.
Omitted/zero `layout_version` is legacy support for centered Alpine/Cactus
layouts only. Capability 1 accepts all version 1 layouts; capability 2 accepts
versions 1 and 2; capability 3 accepts versions 1, 2 and 3; capability 4 accepts
versions 1 through 4; capability 5 accepts versions 1 through 5.
Authenticated clients lacking support for their herd's layout
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

### Cloud navigation

Version 4 is the union of closed capsules of radius `half_width` around each
adjacent spine segment and the three closed shelf disks, intersected with the
unchanged world bounds. A valid destination alone does not make its approach safe.
All actors use whole-segment containment on every substep, at most `0.08` units.

Containment computes closed intervals of parameter `t` on `from+t*(to-from)`.
Each shelf and spine endpoint supplies a line-circle interval. The circle roots
are `(-b ± sqrt(b*b-a*c))/a`, with `a=dot(delta,delta)`,
`b=dot(from-center,delta)`, `c=dot(from-center,from-center)-radius²`.
Negative discriminants have no interval; zero-length segments use membership.
For each spine segment with axis `s` and squared length `L`, its oriented
rectangle intersects two slabs: `dot(point-start,s)` in `[0,L]`, and
`cross(point-start,s)` in `[-half_width*sqrt(L),half_width*sqrt(L)]`.
Intervals are clipped to `[0,1]`; exact primitive membership pins a covered
endpoint to 0 or 1. Sort by lower endpoint ascending then upper descending.
Their union must cover all of `[0,1]` without any positive gap. There is no
sampling or collision-relaxing epsilon. Graph calculations use double scalars.

Planning uses exactly six nodes: the four spine anchors in their given order,
start index 4 and target index 5. Use the Oasis Dijkstra tie rules (`1e-9`) and
route retention/arrival rules (`0.08`). Queues hold at most four unique canonical
anchors, never the target itself. [Shared fixtures](cloud-routes.json) pin routes
and visibility for shelf chords, detours, symmetric directions and near edges.
Changed targets replan; identical commands retain the current route. `sit` and
`stay` clear it. Cloud disconnect/restart pauses and preserves it like Oasis.

Sheep use local edge avoidance and tangent steering under dog pressure; they do
not follow the graph or automatically travel uphill. Without fear they slow to
grazing on any shelf. The separate `rest` disk only defines the internal `settled`
count, not an attraction force or visible score. Ordinary dog positioning can
bring the same ten sheep uphill, downhill, or reunite a separated flock.

### Juniper Shore navigation

Version 5 uses the same analytic closed capsule/disk union math as Cloud:
capsules join adjacent `shore.path` anchors, with radius `half_width`, and union
with `clearings`; intersect this union with the unchanged world bounds. Every
full actor segment must remain inside dry ground. In particular both end clearings
are reachable, but their direct chord crosses the lake and is forbidden. Do not
turn the unused bridge/gate fields into obstacles or relax a shoreline boundary.

The graph has eight nodes: six path anchors in their exact order, start index 6,
target index 7. Dijkstra retains the existing double-scalar `1e-9` tie rules.
Queues contain at most six unique canonical anchors, never the final target.
Use the same `0.08` arrival, direct-visibility clearing, repeated-target retention,
changed-command replanning, and moving-Come-caller rules as Cloud. All six anchors
may be retained if their segments are safe, though shortest routes often need fewer.
[32 shared fixtures](shore-routes.json) include both directions, duplicate anchor
ties, longer lake detours, near-boundary cases, and invalid lake endpoints.

New Juniper herders start at `(-14,0)` and `(-14,3)`, Mochi/Maple at
`(-12.2,-1)` and `(-12.2,2)`. Sheep index `i=0..9`, preserving IDs `s1..s10`,
starts at `(-10.7+i%3, -0.4+floor(i/3)*1.05)`. These spawns are only for new
Juniper worlds; loading a checkpoint never resets actors. The two humans and
both dogs retain speeds 4 and 4.6 units/s; sheep remain capped at 2.6 units/s.

Sheep use local edge avoidance and pressure-driven tangent steering, not graph
routes or destination attraction. Without dog fear, all three clearings permit
quiet grazing. Ordinary dog positioning can guide the same flock outward and
back, or retrieve stragglers after a genuine split. There is no settling objective.

Disconnect/restart pauses and preserves herder targets, sequences, and routes.
Snapshots/checkpoints deep-clone canonical path and clearing arrays. Missing or
changed v5 geometry, actors in water/outside bounds, unsafe/noncanonical/duplicate
or overlong queues, phantom gates, and nonzero `settled` reject the complete
checkpoint before actors start or files are overwritten. Old layout migrations
and v1–4 simulation behavior remain unchanged. Old clients may keep using their
existing worlds; only clients with advertised/implemented capability 5 enter Juniper.

Older checkpoints without a landscape field load as `alpine`; existing Alpine
and Cactus saves without a layout migrate to centered version 1 without changing
animal/player identities, credentials, positions, gate state, or simulation tick.
Unknown saved layout versions, noncanonical layouts, impossible forage state,
unsafe routes, actors inside rock or outside the ridge, and extra/malformed ridge
fields fail startup without overwriting the save. Existing version-1/2/3
simulation and snapshot fields are unchanged.
There is no account service or puppy progression
system yet.
