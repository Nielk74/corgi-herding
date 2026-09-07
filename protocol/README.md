# Corgi Herding protocol v1

The Go server owns a 20 Hz simulation on an X/Y plane; Godot maps Y to Z.
HTTP base is user configurable (default http://127.0.0.1:8790).

`GET /healthz` returns `{status,version,protocol:1,layout_version:1,sessions}`.
Clients can probe this before authentication: older servers omit `layout_version`
and strictly reject unknown auth fields, so omit the capability when connecting
to those servers. Never discard saved credentials merely because a server has
not yet upgraded to support layout negotiation.
`POST /api/herds` with `{name:string,landscape?:"alpine"|"cactus"|"larch"}` creates a two-person herd and returns
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

Connect `GET /api/herds/{code}/ws` (WebSocket, no credentials in URL), then send
`{type:"auth",player_id,token,layout_version:1}` within 5 seconds. Server replies with snapshots.
Reconnection uses the same credentials; players remain in the herd. A replacement
connection supersedes the old connection. Never expose tokens in snapshots/logs.
Omitted/zero `layout_version` is legacy support for centered Alpine/Cactus
layouts only. Authenticated clients lacking Larch support or sending an unknown
layout capability receive `{type:"error",code:"update_required",message:...}`
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

World bounds: X [-17,17], Y [-11,11]. River occupies X [-1.5,1.5],
crossable only where `abs(y-layout.bridge_y) <= 1.85`. Fence collision occupies
`abs(x-6) < 0.18`; its opening is passable only when `gate_open` and
`abs(y-layout.gate_y) <= 1.8`. Gate interaction requires a player within
3 units of `(6,layout.gate_y)`. Sheep in X>8 are counted settled but can wander again.
Player speed 4 units/s. Two dogs and ten sheep. Shared dog control.
Player and dog paths visit the bridge then gate when travelling east; returning
from the pasture visits the gate before the bridge. Both clients must use the
snapshot layout for prediction, interaction picking, and terrain presentation.
Older checkpoints without a landscape field load as `alpine`; existing Alpine
and Cactus saves without a layout migrate to centered version 1 without changing
animal/player identities, credentials, positions, gate state, or simulation tick.
Unknown saved layout versions and noncanonical layouts fail startup without
overwriting the save. There is no account service or progression system yet.
