#!/bin/bash
set -euo pipefail

deployment_root=${1:?Usage: deploy-update-server.sh DEPLOYMENT_ROOT [--stage-only]}
stage_only=${2:-}
service_label="com.corgiherding.server"
service_target="gui/$(id -u)/$service_label"
repository=$(<"$deployment_root/repository")
health_port=$(<"$deployment_root/port")

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }
restart_server() {
    # KeepAlive starts the replacement after the old process flushes its save.
    launchctl kill SIGTERM "$service_target" 2>/dev/null || launchctl kickstart "$service_target"
}
[[ "$stage_only" == "" || "$stage_only" == "--stage-only" ]] || fail "Unknown option: $stage_only"
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || fail "This updater currently supports Apple Silicon macOS."

# A directory lock prevents simultaneous launchd and manual updates. Recover a
# stale lock only when its recorded owner is definitely gone.
lock_dir="$deployment_root/update.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
    if [[ -r "$lock_dir/pid" ]]; then
        lock_pid=$(<"$lock_dir/pid")
        if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$lock_dir/pid"
            rmdir "$lock_dir" 2>/dev/null || exit 0
            mkdir "$lock_dir" 2>/dev/null || exit 0
        else
            exit 0
        fi
    else
        exit 0
    fi
fi
printf '%s\n' "$$" > "$lock_dir/pid"
cleanup() { rm -f "$lock_dir/pid"; rmdir "$lock_dir" 2>/dev/null || true; }
trap cleanup EXIT

if [[ "$stage_only" == "--stage-only" ]] && launchctl print "$service_target" >/dev/null 2>&1; then
    fail "Stage-only installation requires the server service to be stopped."
fi

# GitHub's latest endpoint excludes drafts and prereleases. CI publishes a draft
# only after every release artifact has uploaded successfully.
release_tag=$(gh release view --repo "$repository" --json tagName --jq .tagName)
[[ "$release_tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || fail "Unsupported release tag."
current_version=""
[[ ! -r "$deployment_root/current-version" ]] || current_version=$(<"$deployment_root/current-version")
if [[ "$release_tag" == "$current_version" && -x "$deployment_root/bin/corgi-server" ]]; then
    exit 0
fi

asset="corgi-server-darwin-arm64"
release_dir="$deployment_root/releases/$release_tag"
if [[ ! -x "$release_dir/corgi-server" ]]; then
    download_dir=$(mktemp -d "$deployment_root/releases/.download.XXXXXX")
    log "Downloading $repository release $release_tag."
    gh release download "$release_tag" --repo "$repository" --pattern "$asset" --pattern SHA256SUMS --dir "$download_dir"
    expected_hash=$(awk -v filename="$asset" '$2 == filename || $2 == "*" filename {print $1}' "$download_dir/SHA256SUMS")
    [[ "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]] || fail "Missing or ambiguous checksum for $asset."
    actual_hash=$(shasum -a 256 "$download_dir/$asset" | awk '{print $1}')
    [[ "$actual_hash" == "$expected_hash" ]] || fail "Checksum mismatch for $asset."
    chmod 755 "$download_dir/$asset"
    mv "$download_dir/$asset" "$download_dir/corgi-server"
    [[ ! -e "$release_dir" ]] || fail "Release directory already exists but is incomplete: $release_dir"
    mv "$download_dir" "$release_dir"
fi
# Recheck cached releases too, including a release retained after rollback.
expected_hash=$(awk -v filename="$asset" '$2 == filename || $2 == "*" filename {print $1}' "$release_dir/SHA256SUMS")
[[ "$expected_hash" =~ ^[a-fA-F0-9]{64}$ ]] || fail "Missing or ambiguous cached checksum."
actual_hash=$(shasum -a 256 "$release_dir/corgi-server" | awk '{print $1}')
[[ "$actual_hash" == "$expected_hash" ]] || fail "Cached release checksum mismatch."

old_binary=""
[[ ! -L "$deployment_root/bin/corgi-server" ]] || old_binary=$(readlink "$deployment_root/bin/corgi-server")
ln -sfn "$release_dir/corgi-server" "$deployment_root/bin/corgi-server.next"
mv -f "$deployment_root/bin/corgi-server.next" "$deployment_root/bin/corgi-server"

if [[ "$stage_only" != "--stage-only" ]]; then
    # Only this installer's named launchd job is restarted; no port-based killing.
    restart_server || true
    healthy=false
    for ((attempt = 0; attempt < 30; attempt++)); do
        health_json=$(curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:$health_port/healthz" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$health_json" == *'"status":"ok"'* && "$health_json" == *"\"version\":\"$release_tag\""* ]]; then
            healthy=true
            break
        fi
        sleep 1
    done
    if [[ "$healthy" != true ]]; then
        if [[ -n "$old_binary" && -x "$old_binary" ]]; then
            ln -sfn "$old_binary" "$deployment_root/bin/corgi-server.rollback"
            mv -f "$deployment_root/bin/corgi-server.rollback" "$deployment_root/bin/corgi-server"
            restart_server || true
            recovered=false
            for ((attempt = 0; attempt < 30; attempt++)); do
                health_json=$(curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:$health_port/healthz" 2>/dev/null | tr -d '[:space:]' || true)
                if [[ "$health_json" == *'"status":"ok"'* && "$health_json" == *"\"version\":\"$current_version\""* ]]; then
                    recovered=true
                    break
                fi
                sleep 1
            done
            [[ "$recovered" == true ]] || fail "Release $release_tag failed; the previous binary was restored but is unhealthy. Inspect $deployment_root/logs/com.corgiherding.server.log."
            fail "Release $release_tag failed its health check; restored healthy $current_version."
        fi
        fail "Release $release_tag failed its health check and no earlier binary is available."
    fi
fi
printf '%s\n' "$release_tag" > "$deployment_root/current-version.next"
mv -f "$deployment_root/current-version.next" "$deployment_root/current-version"
log "Installed $release_tag ($actual_hash)."
