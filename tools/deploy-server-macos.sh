#!/bin/bash
set -euo pipefail

repository="Nielk74/corgi-herding"
port=8790
bind_address="0.0.0.0"
deployment_root="$HOME/Library/Application Support/Corgi Herding"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
usage() {
    printf '%s\n' 'Usage: tools/deploy-server-macos.sh [--repo OWNER/REPO] [--port PORT] [--bind ADDRESS] [--data-dir PATH]'
}
while (($#)); do
    case "$1" in
        --repo) repository=${2:?Missing repository}; shift 2 ;;
        --port) port=${2:?Missing port}; shift 2 ;;
        --bind) bind_address=${2:?Missing bind address}; shift 2 ;;
        --data-dir) deployment_root=${2:?Missing data directory}; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { printf '%s\n' 'This installer currently supports Apple Silicon macOS.' >&2; exit 1; }
[[ "$port" =~ ^[0-9]{1,5}$ ]] && ((port > 1024 && port < 65536)) || { printf '%s\n' 'Choose a port from 1025 through 65535.' >&2; exit 1; }
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { printf '%s\n' 'Repository must be OWNER/REPO.' >&2; exit 1; }
[[ "$deployment_root" == /* ]] || { printf '%s\n' 'The data directory must be an absolute path.' >&2; exit 1; }
for dependency in gh curl shasum launchctl plutil lsof; do
    command -v "$dependency" >/dev/null || { printf 'Missing dependency: %s\n' "$dependency" >&2; exit 1; }
done
gh auth status >/dev/null

service_label="com.corgiherding.server"
update_label="com.corgiherding.update"
launch_domain="gui/$(id -u)"
agents_dir="$HOME/Library/LaunchAgents"
service_plist="$agents_dir/$service_label.plist"
update_plist="$agents_dir/$update_label.plist"

# Installing into a live service is deliberately explicit. Normal updates use
# the copied updater and never require rerunning this installer.
if launchctl print "$launch_domain/$service_label" >/dev/null 2>&1 || launchctl print "$launch_domain/$update_label" >/dev/null 2>&1; then
    printf '%s\n' "Corgi Herding is already installed. Run '$deployment_root/update-server.sh' '$deployment_root' to update it now." >&2
    exit 1
fi
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    printf 'Port %s already has a listener. Choose another --port; no process was stopped.\n' "$port" >&2
    exit 1
fi

umask 077
mkdir -p "$deployment_root/bin" "$deployment_root/releases" "$deployment_root/state" "$deployment_root/logs" "$agents_dir"
printf '%s\n' "$repository" > "$deployment_root/repository"
printf '%s\n' "$port" > "$deployment_root/port"
printf '%s:%s\n' "$bind_address" "$port" > "$deployment_root/address"
cp "$source_dir/deploy-run-server.sh" "$deployment_root/run-server.sh"
cp "$source_dir/deploy-update-server.sh" "$deployment_root/update-server.sh"
chmod 700 "$deployment_root/run-server.sh" "$deployment_root/update-server.sh"
"$deployment_root/update-server.sh" "$deployment_root" --stage-only

write_plist() {
    local plist=$1 label=$2 script=$3
    [[ ! -e "$plist" ]] || mv "$plist" "$plist.previous.$(date '+%Y%m%d%H%M%S')"
    plutil -create xml1 "$plist"
    plutil -insert Label -string "$label" "$plist"
    plutil -insert ProgramArguments -xml '<array/>' "$plist"
    plutil -insert ProgramArguments.0 -string /bin/bash "$plist"
    plutil -insert ProgramArguments.1 -string "$script" "$plist"
    plutil -insert ProgramArguments.2 -string "$deployment_root" "$plist"
    plutil -insert WorkingDirectory -string "$deployment_root" "$plist"
    plutil -insert EnvironmentVariables -xml '<dict/>' "$plist"
    plutil -insert EnvironmentVariables.PATH -string '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin' "$plist"
    plutil -insert RunAtLoad -bool YES "$plist"
    plutil -insert StandardOutPath -string "$deployment_root/logs/$label.log" "$plist"
    plutil -insert StandardErrorPath -string "$deployment_root/logs/$label.log" "$plist"
    if [[ "$label" == "$service_label" ]]; then
        plutil -insert KeepAlive -bool YES "$plist"
        plutil -insert ThrottleInterval -integer 5 "$plist"
        plutil -insert ExitTimeOut -integer 30 "$plist"
    else
        plutil -insert StartInterval -integer 300 "$plist"
        plutil -insert ProcessType -string Background "$plist"
    fi
    plutil -lint "$plist" >/dev/null
}
write_plist "$service_plist" "$service_label" "$deployment_root/run-server.sh"
write_plist "$update_plist" "$update_label" "$deployment_root/update-server.sh"
launchctl bootstrap "$launch_domain" "$service_plist"

healthy=false
expected_version=$(<"$deployment_root/current-version")
for ((attempt = 0; attempt < 30; attempt++)); do
    health_json=$(curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:$port/healthz" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$health_json" == *'"status":"ok"'* && "$health_json" == *"\"version\":\"$expected_version\""* ]]; then
        healthy=true
        break
    fi
    sleep 1
done
if [[ "$healthy" != true ]]; then
    printf 'Server failed to become healthy. Inspect %s/logs/%s.log.\n' "$deployment_root" "$service_label" >&2
    exit 1
fi
launchctl bootstrap "$launch_domain" "$update_plist"
printf 'Server is healthy on %s:%s. Updates check every 5 minutes.\nState and logs: %s\n' "$bind_address" "$port" "$deployment_root"
