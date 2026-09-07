#!/bin/bash
set -euo pipefail

# Exercise the real updater against isolated GitHub/launchd/HTTP stand-ins.
# No real services, credentials, network requests, or saves are touched.
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/corgi-updater-test.XXXXXX")
export CORGI_DEPLOY_TEST_ROOT="$test_root"
export PATH="$test_root/mocks:$PATH"
mkdir -p "$test_root/mocks" "$test_root/runtime/bin" "$test_root/runtime/releases" "$test_root/runtime/state" "$test_root/fixtures"
touch "$test_root/runtime/server.plist"
printf '%s\n' 'example/corgi-herding' > "$test_root/runtime/repository"
printf '%s\n' 8790 > "$test_root/runtime/port"

cat > "$test_root/mocks/uname" <<'MOCK'
#!/bin/bash
case "$1" in -s) printf 'Darwin\n';; -m) printf 'arm64\n';; *) exit 1;; esac
MOCK
cat > "$test_root/mocks/gh" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$2" in
    view) cat "$CORGI_DEPLOY_TEST_ROOT/latest" ;;
    download)
        tag=$3
        while (($#)); do
            if [[ "$1" == --dir ]]; then destination=$2; break; fi
            shift
        done
        cp "$CORGI_DEPLOY_TEST_ROOT/fixtures/$tag/corgi-server-darwin-arm64" "$destination/"
        cp "$CORGI_DEPLOY_TEST_ROOT/fixtures/$tag/SHA256SUMS" "$destination/"
        ;;
    *) exit 1 ;;
esac
MOCK
cat > "$test_root/mocks/launchctl" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$CORGI_DEPLOY_TEST_ROOT/launchctl-calls"
if [[ "$1" == print ]]; then
    [[ -f "$CORGI_DEPLOY_TEST_ROOT/running" ]] || exit 1
    printf 'path = %s/runtime/server.plist\n' "$CORGI_DEPLOY_TEST_ROOT"
elif [[ "$1" == bootout ]]; then
    if [[ -f "$CORGI_DEPLOY_TEST_ROOT/final-flush.json" ]]; then
        cp "$CORGI_DEPLOY_TEST_ROOT/final-flush.json" "$CORGI_DEPLOY_TEST_ROOT/runtime/state/herds.json"
        rm "$CORGI_DEPLOY_TEST_ROOT/final-flush.json"
    fi
    rm -f "$CORGI_DEPLOY_TEST_ROOT/running"
elif [[ "$1" == bootstrap ]]; then
    binary=$(readlink "$CORGI_DEPLOY_TEST_ROOT/runtime/bin/corgi-server")
    tag=$(basename "$(dirname "$binary")")
    if [[ -r "$CORGI_DEPLOY_TEST_ROOT/fail-bootstrap" ]] && [[ "$tag" == "$(<"$CORGI_DEPLOY_TEST_ROOT/fail-bootstrap")" ]]; then
        exit 5
    fi
    if [[ -r "$CORGI_DEPLOY_TEST_ROOT/fixtures/$tag/new-state.json" ]]; then
        cp "$CORGI_DEPLOY_TEST_ROOT/fixtures/$tag/new-state.json" "$CORGI_DEPLOY_TEST_ROOT/runtime/state/herds.json"
    fi
    touch "$CORGI_DEPLOY_TEST_ROOT/running"
else
    exit 99
fi
MOCK
cat > "$test_root/mocks/plutil" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$2" in
    ProgramArguments.1) printf '%s/runtime/run-server.sh\n' "$CORGI_DEPLOY_TEST_ROOT" ;;
    ProgramArguments.2) printf '%s/runtime\n' "$CORGI_DEPLOY_TEST_ROOT" ;;
    *) exit 99 ;;
esac
MOCK
cat > "$test_root/mocks/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
binary=$(readlink "$CORGI_DEPLOY_TEST_ROOT/runtime/bin/corgi-server")
tag=$(basename "$(dirname "$binary")")
[[ -f "$CORGI_DEPLOY_TEST_ROOT/running" ]] || exit 7
# The old server cannot load a save emitted by the incompatible candidate.
if [[ "$tag" == build-2 ]] && grep -q '"incompatible":true' "$CORGI_DEPLOY_TEST_ROOT/runtime/state/herds.json"; then
    exit 7
fi
if [[ -r "$CORGI_DEPLOY_TEST_ROOT/fail-health" ]] && [[ "$tag" == "$(<"$CORGI_DEPLOY_TEST_ROOT/fail-health")" ]]; then
    exit 7
fi
printf '{"status":"ok","version":"%s"}\n' "$tag"
MOCK
cat > "$test_root/mocks/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$test_root/mocks/gh" "$test_root/mocks/uname" "$test_root/mocks/launchctl" "$test_root/mocks/plutil" "$test_root/mocks/curl" "$test_root/mocks/sleep"

make_release() {
    local tag=$1 fixture="$test_root/fixtures/$1"
    mkdir -p "$fixture"
    printf '#!/bin/sh\n# %s\nexit 0\n' "$tag" > "$fixture/corgi-server-darwin-arm64"
    (cd "$fixture" && shasum -a 256 corgi-server-darwin-arm64 > SHA256SUMS)
    printf '%s\n' "$tag" > "$test_root/latest"
}
assert_version() {
    [[ "$(<"$test_root/runtime/current-version")" == "$1" ]]
    [[ "$(readlink "$test_root/runtime/bin/corgi-server")" == "$test_root/runtime/releases/$1/corgi-server" ]]
}

make_release build-1
"$source_dir/deploy-update-server.sh" "$test_root/runtime" --stage-only
assert_version build-1
touch "$test_root/running"

make_release build-2
printf '%s\n' '{"schema":1,"seq":0}' > "$test_root/runtime/state/herds.json"
printf '%s\n' '{"schema":1,"seq":1}' > "$test_root/final-flush.json"
cp "$test_root/final-flush.json" "$test_root/expected-first-backup.json"
printf '%s\n' '{"schema":1,"seq":2}' > "$test_root/fixtures/build-2/new-state.json"
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
assert_version build-2
first_backup=("$test_root/runtime/checkpoint-backups/before-build-2."*)
cmp "$test_root/expected-first-backup.json" "${first_backup[0]}/herds.before.json"
cmp "$test_root/runtime/state/herds.json" "$test_root/fixtures/build-2/new-state.json"
# Subsequent old-server starts preserve the restored save instead of rewriting it.
mv "$test_root/fixtures/build-2/new-state.json" "$test_root/build-2-first-start.json"
calls_before=$(wc -l < "$test_root/launchctl-calls")
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
[[ "$(wc -l < "$test_root/launchctl-calls")" == "$calls_before" ]]

make_release build-3
printf '%s\n' tampered >> "$test_root/fixtures/build-3/corgi-server-darwin-arm64"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: a bad checksum was accepted.' >&2
    exit 1
fi
assert_version build-2

make_release build-4
printf '%s\n' '{"schema":1,"gate_open":true,"seq":9}' > "$test_root/final-flush.json"
cp "$test_root/final-flush.json" "$test_root/expected-rollback.json"
printf '%s\n' '{"schema":1,"landscape":"alpine","incompatible":true}' > "$test_root/fixtures/build-4/new-state.json"
printf '%s\n' build-4 > "$test_root/fail-health"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: an unhealthy release was accepted.' >&2
    exit 1
fi
assert_version build-2
cmp "$test_root/expected-rollback.json" "$test_root/runtime/state/herds.json"
failed_backup=("$test_root/runtime/checkpoint-backups/before-build-4."*)
cmp "$test_root/expected-rollback.json" "${failed_backup[0]}/herds.before.json"
cmp "$test_root/fixtures/build-4/new-state.json" "${failed_backup[0]}/herds.failed.json"
[[ "$(tail -n 1 "$test_root/launchctl-calls")" == "bootstrap gui/$(id -u) $test_root/runtime/server.plist" ]]

printf '%s\n' build-none > "$test_root/fail-health"
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
assert_version build-4
cmp "$test_root/runtime/state/herds.json" "$test_root/fixtures/build-4/new-state.json"
# A successful retry must not overwrite evidence from the rejected attempt.
cmp "$test_root/expected-rollback.json" "${failed_backup[0]}/herds.before.json"
cmp "$test_root/fixtures/build-4/new-state.json" "${failed_backup[0]}/herds.failed.json"

# Older installations omit this file and retain the GUI default above. New
# headless installs select the existing user domain and persist that choice.
printf 'user/%s\n' "$(id -u)" > "$test_root/runtime/launch-domain"
make_release build-5
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
assert_version build-5
[[ "$(tail -n 1 "$test_root/launchctl-calls")" == "bootstrap user/$(id -u) $test_root/runtime/server.plist" ]]

# Restore absence too: a failed candidate must not leave a new-format save
# behind when the previous installation had no checkpoint.
mv "$test_root/runtime/state/herds.json" "$test_root/state-before-absence-case.json"
make_release build-6
printf '%s\n' '{"schema":2,"incompatible":true}' > "$test_root/fixtures/build-6/new-state.json"
printf '%s\n' build-6 > "$test_root/fail-health"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: an unhealthy first checkpoint was accepted.' >&2
    exit 1
fi
assert_version build-5
[[ ! -e "$test_root/runtime/state/herds.json" ]]

make_release build-7
printf '%s\n' build-7 > "$test_root/fail-bootstrap"
printf '%s\n' '{"schema":1,"seq":17}' > "$test_root/final-flush.json"
cp "$test_root/final-flush.json" "$test_root/expected-bootstrap-rollback.json"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: a bootstrap failure was accepted.' >&2
    exit 1
fi
assert_version build-5
cmp "$test_root/expected-bootstrap-rollback.json" "$test_root/runtime/state/herds.json"
printf '%s\n' system > "$test_root/runtime/launch-domain"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: an invalid launch domain was accepted.' >&2
    exit 1
fi
assert_version build-5
printf 'PASS: staging, healthy update, no-op, checksum rejection, checkpoint flush/backup, incompatible-save rollback, cached retry, headless domain, absent-save restore, bootstrap-failure recovery, invalid domain rejection.\nIsolated evidence: %s\n' "$test_root"
