#!/usr/bin/env bash
#
# Cloud Agent install script for the Apache APISIX development environment.
#
# Installs the runtime toolchain (OpenResty, LuaRocks, etcd) and the Lua
# dependencies required to build and run APISIX from source. This script is
# idempotent: it can be re-run safely and skips work that is already done.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

OPENRESTY_PREFIX=/usr/local/openresty
# APISIX 2.6 targets OpenResty >= 1.19.3.2. On Ubuntu 24.04 (noble) the oldest
# OpenResty offered by the official repository is the 1.25.3.2 line, which runs
# APISIX 2.6 without modification.
OPENRESTY_SERIES='1\.25\.3\.2'
ETCD_VERSION=v3.4.13

echo "==> [1/6] Configuring APT repositories (OpenResty + universe)"
if [ ! -f /usr/share/keyrings/openresty.gpg ]; then
    wget -qO - https://openresty.org/package/pubkey.gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/openresty.gpg
fi
CODENAME="$(lsb_release -sc)"
echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/openresty.list >/dev/null
sudo add-apt-repository -y universe >/dev/null 2>&1 || true
sudo apt-get update -y

echo "==> [2/6] Installing OpenResty + build toolchain"
ORVER="$(apt-cache madison openresty | awk '{print $3}' | grep "^${OPENRESTY_SERIES}" | head -1 || true)"
if [ -n "$ORVER" ]; then
    OPENRESTY_PKG="openresty=${ORVER}"
else
    echo "WARN: pinned OpenResty ${OPENRESTY_SERIES} not found, using latest available"
    OPENRESTY_PKG="openresty"
fi
sudo apt-get install -y \
    "$OPENRESTY_PKG" \
    openresty-openssl111-dev \
    lua5.1 liblua5.1-0-dev \
    make gcc git unzip curl wget

echo "==> [3/6] Installing LuaRocks (from source)"
if ! command -v luarocks >/dev/null 2>&1; then
    sudo OPENRESTY_PREFIX="$OPENRESTY_PREFIX" bash ./utils/linux-install-luarocks.sh
else
    echo "    LuaRocks already installed: $(luarocks --version | head -1)"
fi

echo "==> [4/6] Installing etcd server + etcdctl (${ETCD_VERSION})"
if ! command -v etcd >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    arch="$(dpkg --print-architecture)"
    wget -q -O "$tmp/etcd.tar.gz" \
        "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${arch}.tar.gz"
    tar -xf "$tmp/etcd.tar.gz" -C "$tmp"
    sudo cp -a "$tmp/etcd-${ETCD_VERSION}-linux-${arch}/etcd" \
               "$tmp/etcd-${ETCD_VERSION}-linux-${arch}/etcdctl" /usr/local/bin/
    rm -rf "$tmp"
else
    echo "    etcd already installed: $(etcd --version | head -1)"
fi

echo "==> [5/6] Allowing LuaRocks git:// dependencies to resolve over HTTPS"
# Some dependency rockspecs (e.g. lua-resty-etcd) clone over the git:// protocol
# (TCP 9418), which is commonly blocked. Rewrite it to HTTPS.
git config --global url."https://github.com/".insteadOf "git://github.com/"

echo "==> [6/6] Installing APISIX Lua dependencies (make deps)"
export PATH="$OPENRESTY_PREFIX/nginx/sbin:$OPENRESTY_PREFIX/luajit/bin:$OPENRESTY_PREFIX/bin:$PATH"
make deps

echo "==> install.sh complete"
