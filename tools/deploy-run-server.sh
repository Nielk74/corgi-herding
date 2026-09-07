#!/bin/bash
set -euo pipefail

# This copy lives outside the checkout so updates survive a moved repository.
deployment_root=${1:?Usage: deploy-run-server.sh DEPLOYMENT_ROOT}
export CORGI_ADDR
export CORGI_STATE_DIR="$deployment_root/state"
CORGI_ADDR=$(<"$deployment_root/address")
exec "$deployment_root/bin/corgi-server"
