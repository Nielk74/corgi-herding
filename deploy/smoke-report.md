# Initial deployment verification

Verified on 2026-09-08 (Europe/Paris), including the first live deployment.

## Release updater

`bash tools/deploy-test-updater.sh` passed all eight cases using isolated GitHub,
launchd, and HTTP stand-ins with real SHA-256 checks and filesystem swaps:

- Initial verified release staging.
- Healthy release update.
- Already-current release without a restart.
- Rejected checksum mismatch; the current binary remained selected.
- Failed health check; the previous version was restored and healthy.
- Successful retry from the verified cached release.
- Saved background user domain selected for a headless installation.
- Invalid launch domain rejected before any service operation.

Both forward replacement and rollback requested `SIGTERM`; the test rejects
forced `kickstart -k` calls. All deployment scripts passed `bash -n`.

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
