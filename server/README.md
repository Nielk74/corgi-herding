# Meadow server

The first playable milestone runs one Go process with a 20 Hz actor for each
two-player herd. Each herd owns two shared corgis and ten sheep. Worlds pause
when nobody is connected. Both herders can return with their locally saved
credentials; reconnecting replaces the previous connection for that herder.
New herds can select `alpine` (the default), `cactus`, `larch`, `orchard`, `oasis`, or `cloud`. The
choice and immutable layout are stored with the herd and shared in snapshots.
Alpine/Cactus retain centered openings. Larch Hollow has its bridge at Y=-4 and
gate at Y=4, creating a different route through the same playable footprint.
Sunward Orchard uses version 2, bridge Y=3, gate Y=2 and a windfall patch at
(-7,-5). At most two sheep become curious and nibble briefly; either dog can
immediately guide them away. Partial nibbling progress and one-time satiation
persist. Canyon Oasis uses version 3: a radius-3.4 rock spur at (0,0), two dry
routes around it, and no playable river, fence or gate. Eight fixed navigation
anchors route both herders and corgis. Sheep follow dog pressure around the rock
and can split/reunite; they do not automatically navigate toward pasture.
Cloud Pasture uses version 4: a winding capsule ridge and three quiet shelf disks.
Four fixed anchors route herders and corgis, with analytical whole-segment checks
against the playable union. Sheep stay on the ridge through local edge avoidance
and dog pressure, with no automatic attraction uphill; any shelf permits calm
grazing. There is no playable river, gate, fence or forage patch. Existing
version-1/2/3 herds keep their exact prior simulation behavior.
Existing saves without a landscape load as Alpine; existing centered saves
without a layout migrate without changing their animals or credentials. Unknown
saved layout versions or impossible forage state fail startup. Clients negotiate
`layout_versions:[1,2,3,4]` from health before authenticating. The legacy singular
`layout_version:1` stays unchanged. Capability 1 admits version 1 worlds;
capability 2 admits versions 1/2, capability 3 admits 1/2/3, and capability 4 admits
all four versions. Unsupported layouts return `update_required`/4002
without changing credentials or replacing an existing player connection.
Oasis and Cloud herders keep a bounded, validated route queue while disconnected, resuming
on reconnect. Older herds retain their original stop-on-disconnect behavior.

```sh
go run ./cmd/server
go test -race ./...
go vet ./...
```

Configuration:

| Environment | Default | Purpose |
| --- | --- | --- |
| `CORGI_ADDR` | `:8790` | HTTP and WebSocket listener |
| `CORGI_STATE_DIR` | `data` | Private atomic JSON checkpoint directory |
| `CORGI_MAX_SESSIONS` | `100` | Total resident and saved herds; 1–10000 |

`GET /healthz` and `/readyz` expose version, protocol and herd count. Build with
`go build -ldflags '-X main.version=VERSION' ./cmd/server` to identify releases.
Health returns 503 when a checkpoint fails. Logs include session/player IDs and
simulation ticks, never bearer credentials.

HTTP invite responses should be saved immediately by clients. Credentials use
256-bit random bearer tokens; disk stores SHA-256 hashes. Invite codes reserve
the second permanent slot: share the code privately. No login or token recovery
is available in this milestone. JSON snapshots contain no credentials. Invalid
inputs, targets outside the terrain, distant interactions and third players are
rejected. API requests are limited by source IP and each authenticated socket
has an input token bucket; proxies must rate limit at their own edge as the
server deliberately does not trust forwarded IP headers.

Checkpoints are written atomically every 30 seconds, on invitations, and during
SIGTERM/SIGINT shutdown; the file has mode 0600. Keep the directory on persistent
storage. A crash may lose up to 30 seconds of movement. Back up `herds.json` while
preserving its permissions. Unsupported or corrupt checkpoints stop startup
instead of silently resetting progress. Schema migrations, PostgreSQL, puppy
training, permanent progression, account recovery and expired-herd cleanup are
future milestones. Existing herds are not evicted to create capacity.

Player and dog targets route through the bridge and gate, around Oasis rock, or along Cloud ridge.
Sheep combine grazing,
walking and fleeing states with local cohesion, separation, alignment, herder
avoidance and dog pressure. Nearby sheep form connected flock groups. Commands
are deliberately reliable for the first gameplay spike; personality and puppy
learning are not simulated yet. Gate opening requires proximity and is one-way
for the session. There is no timer, score or failure state.

Use TLS/WSS at a reverse proxy before exposing this server to the public
internet. Plain HTTP is supported for the initial local network Android build.
See [the wire contract](../protocol/README.md) and [deployment](../docs/deployment.md).
