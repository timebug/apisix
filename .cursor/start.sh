#!/usr/bin/env bash
#
# Cloud Agent start script for the Apache APISIX development environment.
#
# Brings up the per-boot runtime services: an etcd data store and the APISIX
# gateway. It is idempotent and safe to run when the services are already up.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

export PATH="/usr/local/openresty/nginx/sbin:/usr/local/openresty/luajit/bin:/usr/local/openresty/bin:$PATH"

ETCD_DATA_DIR=/tmp/apisix-etcd-data
ETCD_LOG=/tmp/apisix-etcd.log

echo "==> Ensuring etcd is running on 127.0.0.1:2379"
if ! curl -sf http://127.0.0.1:2379/health >/dev/null 2>&1; then
    mkdir -p "$ETCD_DATA_DIR"
    nohup etcd \
        --data-dir="$ETCD_DATA_DIR" \
        --listen-client-urls=http://127.0.0.1:2379 \
        --advertise-client-urls=http://127.0.0.1:2379 \
        --enable-v2=true \
        --logger=zap >"$ETCD_LOG" 2>&1 &
    for _ in $(seq 1 30); do
        if curl -sf http://127.0.0.1:2379/health >/dev/null 2>&1; then break; fi
        sleep 1
    done
fi
if ! curl -sf http://127.0.0.1:2379/health >/dev/null 2>&1; then
    echo "ERROR: etcd failed to become healthy" >&2
    cat "$ETCD_LOG" >&2 || true
    exit 1
fi
echo "    etcd is healthy"

echo "==> Initializing APISIX (nginx config + etcd bootstrap)"
make init

echo "==> Starting APISIX gateway"
# `apisix start` exits non-zero if an instance is already running; that is a
# benign no-op for our idempotent boot flow.
./bin/apisix start || true

sleep 2
ADMIN_KEY=edd1c9f034335f136f87ad84b625c8f1
if curl -sf -o /dev/null -H "X-API-KEY: ${ADMIN_KEY}" \
        "http://127.0.0.1:9080/apisix/admin/routes"; then
    echo "==> APISIX is up: data plane + Admin API on http://127.0.0.1:9080"
else
    echo "WARN: APISIX Admin API did not respond yet; check logs/error.log" >&2
fi
