# Corgi Herding protocol v1

The Go server owns a 20 Hz simulation on an X/Y plane; Godot maps Y to Z.
HTTP base is user configurable (default http://127.0.0.1:8790).

`GET /healthz` returns `{status,version,protocol:1,sessions}`.
`POST /api/herds` with `{name:string,landscape?:"alpine"|"cactus"}` creates a two-person herd and returns
`{code,player_id,token}`. `POST /api/herds/{code}/join` with `{name:string}`
returns the same fields for the second player. Save these credentials locally.
No third member is accepted. Names are limited to 24 characters.
Omitting `landscape` selects `alpine`; unsupported values return HTTP 400.
The selected landscape belongs to the herd, appears in every snapshot, and
survives reconnects and server restarts. Joining inherits the existing landscape;
it does not accept a landscape override. Both landscapes share the authoritative
playable bounds, bridge, and gate layout below.

Connect `GET /api/herds/{code}/ws` (WebSocket, no credentials in URL), then send
`{type:"auth",player_id,token}` within 5 seconds. Server replies with snapshots.
Reconnection uses the same credentials; players remain in the herd. A replacement
connection supersedes the old connection. Never expose tokens in snapshots/logs.

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
{"type":"snapshot","tick":100,"code":"ABCDEF","landscape":"alpine","gate_open":false,"settled":0,"players":[{"id":"p1","name":"A","position":{"x":-10,"y":0},"target":{"x":-10,"y":0},"seq":1,"state":"idle","connected":true}],"dogs":[{"id":"mochi","name":"Mochi","position":{"x":-8,"y":0},"state":"wander","command":""}],"sheep":[{"id":"s1","position":{"x":-5,"y":0},"state":"grazing","group":0}]}
{"type":"error","message":"..."}
```

World bounds: X [-17,17], Y [-11,11]. River occupies X [-1.5,1.5],
crossable only on the bridge at Y [-2,2]. Fence at X=6; opening at
Y [-2,2] is passable only when gate_open. Gate interaction requires player
within 3 units of (6,0). Sheep in X>8 are counted settled but can wander again.
Player speed 4 units/s. Two dogs and ten sheep. Shared dog control.
Older checkpoints without a landscape field load as `alpine`. There is no
account service, progression, or general schema migration system in milestone 1.
