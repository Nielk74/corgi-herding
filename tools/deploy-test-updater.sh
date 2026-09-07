#!/bin/bash
set -euo pipefail

# Exercise the real updater against isolated GitHub/launchd/HTTP stand-ins.
# No real services, credentials, network requests, or saves are touched.
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/corgi-updater-test.XXXXXX")
export CORGI_DEPLOY_TEST_ROOT="$test_root"
export PATH="$test_root/mocks:$PATH"
mkdir -p "$test_root/mocks" "$test_root/runtime/bin" "$test_root/runtime/releases" "$test_root/fixtures"
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
    [[ -f "$CORGI_DEPLOY_TEST_ROOT/running" ]]
elif [[ "$1" == kill ]]; then
    [[ "$2" == SIGTERM ]] || exit 99
elif [[ "$1" == kickstart ]]; then
    [[ "$2" != -k ]] || exit 99
else
    exit 99
fi
MOCK
cat > "$test_root/mocks/curl" <<'MOCK'
#!/bin/bash
set -euo pipefail
binary=$(readlink "$CORGI_DEPLOY_TEST_ROOT/runtime/bin/corgi-server")
tag=$(basename "$(dirname "$binary")")
if [[ -r "$CORGI_DEPLOY_TEST_ROOT/fail-health" ]] && [[ "$tag" == "$(<"$CORGI_DEPLOY_TEST_ROOT/fail-health")" ]]; then
    exit 7
fi
printf '{"status":"ok","version":"%s"}\n' "$tag"
MOCK
cat > "$test_root/mocks/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$test_root/mocks/gh" "$test_root/mocks/uname" "$test_root/mocks/launchctl" "$test_root/mocks/curl" "$test_root/mocks/sleep"

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
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
assert_version build-2
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
printf '%s\n' build-4 > "$test_root/fail-health"
if "$source_dir/deploy-update-server.sh" "$test_root/runtime"; then
    printf '%s\n' 'FAIL: an unhealthy release was accepted.' >&2
    exit 1
fi
assert_version build-2
[[ "$(tail -n 1 "$test_root/launchctl-calls")" == 'kill SIGTERM gui/'*'/com.corgiherding.server' ]]

printf '%s\n' build-none > "$test_root/fail-health"
"$source_dir/deploy-update-server.sh" "$test_root/runtime"
assert_version build-4
printf 'PASS: initial stage, healthy update, no-op, checksum rejection, graceful rollback, cached retry.\nIsolated evidence: %s\n' "$test_root"
