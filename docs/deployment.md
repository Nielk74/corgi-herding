# Running the herd server

The first milestone uses one Go process with checkpoint files. PostgreSQL and
Redis are deliberately deferred until the persistent journey milestone. Both
players must connect to the same server address. On a local network, use the
server computer's LAN address and port 8790; `localhost` on a phone means that
phone, not the server computer.

## Always updated server on this Mac

After the first successful GitHub release, run from the repository:

```sh
tools/deploy-server-macos.sh --repo Nielk74/corgi-herding
```

This requires Apple Silicon macOS, the GitHub CLI authenticated as the current
user, and an available port 8790. Pass `--port`, `--bind`, or `--data-dir` to
change the defaults. The installer checks for an existing listener and leaves
it alone. It registers two user launch agents:

| Job | Behavior |
| --- | --- |
| `com.corgiherding.server` | Runs the authoritative server and restarts after a crash. |
| `com.corgiherding.update` | Checks the latest published GitHub release every five minutes. |

Files live under `~/Library/Application Support/Corgi Herding/`:

| Path | Contents |
| --- | --- |
| `state/` | Persistent herd checkpoints, including private reconnect credentials. |
| `releases/` | Downloaded binaries and checksums; previous releases are retained for recovery. |
| `current-version` | Last accepted release tag. |
| `launch-domain` | Selected launchd domain: `gui/UID` for a graphical login or `user/UID` for a background user manager. |
| `logs/` | Server and update logs. |

The updater only reads GitHub's latest non-draft, non-prerelease release. CI
uploads all artifacts into a draft before publishing it. The downloaded Apple
Silicon binary is checked against that release's `SHA256SUMS`. The binary link
is swapped atomically, the exact server launch agent restarts, and `/healthz`
must return `status: ok` and the expected release version. If that check fails,
the previous binary is restored, restarted, and checked again. Saved state is
kept outside the release directories. Future incompatible save-format changes
must include migrations and a backup strategy before they ship.

`bash tools/deploy-test-updater.sh` exercises initial installation, a healthy
update, no-op checks, checksum rejection, rollback, cached-release retry, and
both graphical/background launchd domains using isolated service and network
stand-ins. It never stops a real service.

Updates briefly disconnect players. The Android client reconnects with its saved
credentials. The installer uses a graphical login domain when available and
otherwise the existing background user domain on a headless Mac. User launch
agents run while that user manager exists; after a reboot, this macOS user must
log in to start them again. The Mac must remain awake and on the network to
serve the phones. This is a LAN development host, not an independently
available cloud service.

Check health or trigger an update immediately:

```sh
curl -fsS http://127.0.0.1:8790/healthz
"$HOME/Library/Application Support/Corgi Herding/update-server.sh" \
  "$HOME/Library/Application Support/Corgi Herding"
deployment_root="$HOME/Library/Application Support/Corgi Herding"
launch_domain=$(<"$deployment_root/launch-domain")
launchctl print "$launch_domain/com.corgiherding.server"
```

To stop this deployment without deleting its saved games:

```sh
deployment_root="$HOME/Library/Application Support/Corgi Herding"
launch_domain=$(<"$deployment_root/launch-domain")
launchctl bootout "$launch_domain/com.corgiherding.update"
launchctl bootout "$launch_domain/com.corgiherding.server"
```

The plist files remain in `~/Library/LaunchAgents/` and will load at next login.
To keep the service disabled, move its two `com.corgiherding.*.plist` files out
of that folder. Keep the state folder private when making backups.

## Docker Compose on another host

```sh
docker compose up -d --build server
curl -fsS http://127.0.0.1:8790/healthz
```

The server runs as an unprivileged container user, persists saves in the named
`corgi-state` volume, and restarts unless deliberately stopped. To update this
deployment, check out a completed release tag and run the same build command.
Compose does not automatically pull changes; the macOS launch agent above is
the automatic release updater provided by this milestone.

For a public host, point a domain at the machine, allow inbound ports 80 and
443, and use the optional Caddy profile for HTTPS and WebSockets:

```sh
CORGI_DOMAIN=herd.example.com CORGI_BIND=127.0.0.1 \
  docker compose --profile public up -d --build
```

Use `https://herd.example.com` in the client. The example domain must be replaced
with one you control. The raw game port binds to loopback in this command so
public clients reach it through TLS. This setup requires a host and domain; the
repository does not provision either. No cloud credentials are bundled.
