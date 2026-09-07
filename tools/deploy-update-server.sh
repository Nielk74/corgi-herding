#!/bin/bash
set -euo pipefail

deployment_root=${1:?Usage: deploy-update-server.sh DEPLOYMENT_ROOT [--stage-only]}
stage_only=${2:-}
service_label="com.corgiherding.server"
launch_user=$(id -u)
launch_domain="gui/$launch_user"
[[ ! -r "$deployment_root/launch-domain" ]] || launch_domain=$(<"$deployment_root/launch-domain")
repository=$(<"$deployment_root/repository")
health_port=$(<"$deployment_root/port")

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }
[[ "$launch_domain" =~ ^(gui|user)/[0-9]+$ && "${launch_domain#*/}" == "$launch_user" ]] || fail "Invalid launchd domain for this user."
service_target="$launch_domain/$service_label"
transaction_active=false
backup_ready=false
checkpoint_present=false
service_plist=""
backup_dir=""
stopping_pid=""

stop_server() {
    local description stopped_pid plist
    if ! description=$(launchctl print "$service_target" 2>/dev/null); then
        # A removed launchd job may still be flushing its last checkpoint.
        if [[ "$stopping_pid" =~ ^[0-9]+$ ]] && kill -0 "$stopping_pid" 2>/dev/null; then
            return 1
        fi
        return 0
    fi
    plist=$(printf '%s\n' "$description" | sed -n 's/^[[:space:]]*path = //p' | head -n 1)
    [[ "$plist" == "$service_plist" ]] || { log 'ERROR: Refusing to stop a service with an unexpected plist.' >&2; return 1; }
    stopped_pid=$(printf '%s\n' "$description" | awk '$1 == "pid" && $2 == "=" {print $3; exit}')
    stopping_pid="$stopped_pid"
    # bootout prevents KeepAlive from starting another writer while checkpointing.
    # The installer's ExitTimeOut gives the server 30 seconds to flush its state.
    launchctl bootout "$service_target" || return 1
    if [[ "$stopped_pid" =~ ^[0-9]+$ ]]; then
        for ((attempt = 0; attempt < 35; attempt++)); do
            if ! kill -0 "$stopped_pid" 2>/dev/null; then
                stopping_pid=""
                return 0
            fi
            sleep 1
        done
        log 'ERROR: The stopped server process has not exited.' >&2
        return 1
    fi
}

wait_healthy() {
    local version=$1 health_json
    for ((attempt = 0; attempt < 30; attempt++)); do
        health_json=$(curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:$health_port/healthz" 2>/dev/null | tr -d '[:space:]' || true)
        if [[ "$health_json" == *'"status":"ok"'* && "$health_json" == *"\"version\":\"$version\""* ]]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

rollback() {
    local restore_file
    stop_server || return 1
    if [[ "$backup_ready" == true ]]; then
        if [[ "$checkpoint_present" == true ]]; then
            restore_file=$(mktemp "$deployment_root/state/.rollback.XXXXXX") || return 1
            cp -p "$backup_dir/herds.before.json" "$restore_file" || return 1
        fi
        # Retain any state the rejected binary wrote for diagnosis/recovery.
        if [[ -f "$deployment_root/state/herds.json" ]]; then
            mv "$deployment_root/state/herds.json" "$backup_dir/herds.failed.json" || return 1
        fi
        if [[ "$checkpoint_present" == true ]]; then
            mv -f "$restore_file" "$deployment_root/state/herds.json" || return 1
        fi
    fi
    ln -sfn "$old_binary" "$deployment_root/bin/corgi-server.rollback" || return 1
    mv -f "$deployment_root/bin/corgi-server.rollback" "$deployment_root/bin/corgi-server" || return 1
    launchctl bootstrap "$launch_domain" "$service_plist" || return 1
    wait_healthy "$current_version" || return 1
    printf '%s\n' "$current_version" > "$deployment_root/current-version.rollback" || return 1
    mv -f "$deployment_root/current-version.rollback" "$deployment_root/current-version" || return 1
    log "Restored healthy $current_version and its pre-update checkpoint; backup: $backup_dir."
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
cleanup() {
    local exit_status=$?
    trap - EXIT
    if [[ "$transaction_active" == true ]]; then
        if ! rollback; then
            log "ERROR: Automatic recovery failed. Previous binary: $old_binary; checkpoint backup: $backup_dir. Inspect $deployment_root/logs/com.corgiherding.server.log." >&2
        fi
        [[ "$exit_status" != 0 ]] || exit_status=1
    fi
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir" 2>/dev/null || true
    exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

if [[ "$stage_only" != "--stage-only" ]]; then
    [[ -n "$old_binary" && -x "$old_binary" && -n "$current_version" ]] || fail 'No installed server to update; run the installer first.'
    service_description=$(launchctl print "$service_target" 2>/dev/null || true)
    service_plist=$(printf '%s\n' "$service_description" | sed -n 's/^[[:space:]]*path = //p' | head -n 1)
    [[ -n "$service_plist" ]] || service_plist="$HOME/Library/LaunchAgents/$service_label.plist"
    [[ -r "$service_plist" ]] || fail "Server plist is missing: $service_plist"
    runner=$(plutil -extract ProgramArguments.1 raw -o - "$service_plist")
    installed_root=$(plutil -extract ProgramArguments.2 raw -o - "$service_plist")
    [[ "$runner" == "$deployment_root/run-server.sh" && "$installed_root" == "$deployment_root" ]] || fail 'Server plist does not belong to this deployment.'
    umask 077
    mkdir -p "$deployment_root/checkpoint-backups" "$deployment_root/state"
    backup_dir=$(mktemp -d "$deployment_root/checkpoint-backups/before-$release_tag.XXXXXX")
    printf '%s\n' "$current_version" > "$backup_dir/version.before" || fail 'Could not write checkpoint backup metadata.'
    transaction_active=true
    stop_server || fail 'Could not stop the current server cleanly.'
    # Copy after the final flush, while no server process can modify the file.
    if [[ -f "$deployment_root/state/herds.json" ]]; then
        cp -p "$deployment_root/state/herds.json" "$backup_dir/herds.before.json" || fail 'Could not back up the final checkpoint.'
        checkpoint_present=true
    fi
    backup_ready=true
fi

ln -sfn "$release_dir/corgi-server" "$deployment_root/bin/corgi-server.next"
mv -f "$deployment_root/bin/corgi-server.next" "$deployment_root/bin/corgi-server"

if [[ "$stage_only" != "--stage-only" ]]; then
    launchctl bootstrap "$launch_domain" "$service_plist" || fail "Release $release_tag could not start; restoring the previous release."
    wait_healthy "$release_tag" || fail "Release $release_tag failed its health check; restoring the previous release."
fi
printf '%s\n' "$release_tag" > "$deployment_root/current-version.next"
mv -f "$deployment_root/current-version.next" "$deployment_root/current-version"
transaction_active=false
log "Installed $release_tag ($actual_hash)."
