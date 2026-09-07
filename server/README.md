# Meadow server

The first playable milestone runs one Go process with a 20 Hz actor for each
two-player herd. Each herd owns two shared corgis and ten sheep. Worlds pause
when nobody is connected. Both herders can return with their locally saved
credentials; reconnecting replaces the previous connection for that herder.
New herds can select `alpine` (the default) or `cactus`. The choice is stored with
the herd and shared with both players in snapshots. Existing checkpoints without
a landscape selection load as `alpine`; both landscapes use the same bridge and
gate simulation footprint.

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

Player and dog targets route through the bridge and gate. Sheep combine grazing,
walking and fleeing states with local cohesion, separation, alignment, herder
avoidance and dog pressure. Nearby sheep form connected flock groups. Commands
are deliberately reliable for the first gameplay spike; personality and puppy
learning are not simulated yet. Gate opening requires proximity and is one-way
for the session. There is no timer, score or failure state.

Use TLS/WSS at a reverse proxy before exposing this server to the public
internet. Plain HTTP is supported for the initial local network Android build.
See [the wire contract](../protocol/README.md) and [deployment](../docs/deployment.md).
