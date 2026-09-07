# Initial deployment verification

Verified on 2026-09-08 (Europe/Paris), including the first live deployment.

## Portrait and landscape revision

The signed Android candidate was installed and exercised at 1080×2400 in a
read-only Android emulator connected to an isolated Go server. Both Alpine valley
and Cactus canyon were created from the touch UI. A second authenticated network
client joined each landscape. Portrait gameplay and the contextual corgi menu
were captured directly from Android in `docs/images/`; these are rendered game
screenshots, not concept art. The previous landscape screenshot was replaced.

Scene regressions verify portrait orientation, hidden controls by default,
temporary shared-dog commands, nearest-target selection for overlapping taps,
bridge destination convergence from either bank, and rejection of fence targets
before advancing the movement sequence. The real two-Godot-client network test
checks shared cactus snapshots, commands, movement and reconnect sequencing.
Go race/vet, workflow lint, Android signing and 16 KiB alignment checks passed.
Physical two-phone playtesting and frame-rate profiling remain outstanding.

## Release updater

`bash tools/deploy-test-updater.sh` passed the following cases using isolated GitHub,
launchd, and HTTP stand-ins with real SHA-256 checks and filesystem swaps:

- Initial verified release staging.
- Healthy release update.
- Already-current release without a restart.
- Rejected checksum mismatch; the current binary remained selected.
- Failed health check; the previous version was restored and healthy.
- Successful retry from the verified cached release.
- Saved background user domain selected for a headless installation.
- Invalid launch domain rejected before any service operation.
- Final shutdown writes included in the checkpoint backup.
- Candidate writes an incompatible save, fails health, and restores the exact
  old checkpoint before the old binary is checked.
- Successful update keeps the new live save and retains previous backup evidence.
- Rollback restores checkpoint absence when no previous save existed.
- A failed launchd bootstrap restores the old server and checkpoint.

Both forward replacement and rollback unload only the known server launch agent,
allowing its configured 30-second graceful exit before copying or restoring a
checkpoint. The updater verifies that its recorded process has exited before
starting another writer. The test accepts only the expected `bootout` and
`bootstrap` lifecycle calls. All deployment scripts passed `bash -n`.

## Actual container

The server Dockerfile built successfully with Go 1.26 and Alpine 3.22.
`docker compose config --quiet` passed. The built image was then started with
version `deployment-smoke`, a read-only root filesystem, the unprivileged
`corgi` user, and a separate named state volume. It was exposed only at
`127.0.0.1:8793` for this test.

| Check | Observed result |
| --- | --- |
| Initial `/healthz` | HTTP 200; `status: ok`, `version: deployment-smoke`, `protocol: 1`, `sessions: 0`. |
| Create first player | Succeeded with a valid six-character invitation. |
| Join second player | Succeeded with a distinct player identity and reconnect token. |
| Graceful container restart | Logs recorded `meadow server stopped` followed by a new startup. |
| `/healthz` after restart | HTTP 200; the same version, `status: ok`, `sessions: 1`. |
| Third player joining the saved herd | HTTP 409: `this herd already has two herders`. |
| Container health check | `healthy`, zero failing streak. |

The dedicated smoke container and its test-only state volume were removed after
the checks. No production service or saved game was used. This verifies the
deployment and checkpoint lifecycle; it does not replace two-phone gameplay
testing or verification of the final downloadable APK.

## Live macOS installation

The installer downloaded and checked release `build-2`, selected the available
background user launchd domain, and started the server on port 8790. Both
loopback and LAN health checks returned `status: ok`, `version: build-2`, and
`protocol: 1`. Process ownership and working directory matched this deployment.
The update agent was registered with a 300-second interval and its first run
exited successfully. The deployed updater matched the repository copy.

This headless macOS session required `Background` in `LimitLoadToSessionType`;
the generated plists now support both `Aqua` and `Background`, and the selected
domain is saved for subsequent restarts and updates.

## Unattended release update

At 2026-09-07 22:21:41 UTC, the registered 300-second job independently detected
`build-3`. It downloaded, verified, and accepted the release at 22:21:43 UTC.
No manual update or restart command was used. Server logs recorded a clean
`build-2` shutdown followed by `build-3` startup; the updater's second scheduled
run exited with code zero. `/healthz` returned `status: ok`, `version: build-3`,
and `sessions: 1`.

The active binary's SHA-256 was
`6e63ca3f6a5bdee24410026a4ebd156c3278d7d08ec9b118c7f1c8271d1ecb33`,
matching `corgi-server-darwin-arm64` in a fresh download of the published
`build-3` checksum manifest. The binary symlink selected the `build-3` release
directory.

The existing Android-created herd retained its open gate, seated player with
input sequence 1, two dogs, and ten sheep. Its saved tick was 1696; server logs
then recorded the same player reconnecting to that herd at that tick. No
reconnect credentials are included in this report.
