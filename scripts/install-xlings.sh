#!/usr/bin/env bash
#
# Download, verify and install xlings from a pinned release tarball.
#
# This is the build-time installer used by the Dockerfile. It deliberately does
# not use the upstream quick_install.sh: the image needs a pinned version, a
# checksum check, predictable output and no release-source probing.
#
# Environment:
#   XLINGS_VERSION         release version, without or with a leading "v"
#   XLINGS_DOWNLOAD_BASE   base URL serving <base>/v<version>/<asset>
#   TARGETARCH             docker buildx arch (amd64/arm64); falls back to uname
#   XLINGS_INSTALL_USER    run `self install` as this user (default: current)
#   XLINGS_SKIP_DOWNLOAD   reuse /opt/xlings/<asset> if it is already present

set -euo pipefail

log() { printf '[xlings-install] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

[ -n "${XLINGS_VERSION:-}" ] || die "XLINGS_VERSION is required"

version="${XLINGS_VERSION#v}"
base="${XLINGS_DOWNLOAD_BASE:-https://github.com/openxlings/xlings/releases/download}"
base="${base%/}"

raw_arch="${TARGETARCH:-$(uname -m)}"
case "$raw_arch" in
    amd64 | x86_64)  arch="x86_64" ;;
    arm64 | aarch64) arch="aarch64" ;;
    *) die "unsupported architecture: $raw_arch" ;;
esac

asset="xlings-${version}-linux-${arch}.tar.gz"
url="${base}/v${version}/${asset}"
dest="/opt/xlings"
archive="${dest}/${asset}"
checksum="${archive}.sha256"

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar >/dev/null 2>&1 || die "tar is required"

mkdir -p "$dest"

verify() {
    local file="$1" sidecar="$2" expected actual
    [ -s "$file" ] || return 1
    [ -s "$sidecar" ] || return 1
    read -r expected _ < "$sidecar" || return 1
    expected="${expected,,}"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ]
}

if [ "${XLINGS_SKIP_DOWNLOAD:-0}" = "1" ] && verify "$archive" "$checksum"; then
    log "using cached ${asset}"
else
    log "downloading xlings ${version} (${arch})"
    log "  ${url}"
    rm -f "$archive" "$checksum"
    curl -fsSL \
        --retry 5 --retry-delay 2 --retry-all-errors \
        --connect-timeout 20 \
        -o "$archive" "$url"
    curl -fsSL \
        --retry 5 --retry-delay 2 --retry-all-errors \
        --connect-timeout 20 \
        -o "$checksum" "${url}.sha256"
fi

verify "$archive" "$checksum" || die "checksum verification failed for ${asset}"
log "checksum verified"

# A stable name for the entrypoint's offline self-heal path.
ln -sfn "$archive" "${dest}/xlings.tar.gz"

extract_dir="$(mktemp -d /tmp/xlings-src.XXXXXX)"
cleanup() { rm -rf "$extract_dir"; }
trap cleanup EXIT

tar -xzf "$archive" -C "$extract_dir"
src=""
for candidate in "$extract_dir"/xlings-*/; do
    if [ -d "$candidate" ]; then
        src="${candidate%/}"
        break
    fi
done
if [ -z "$src" ] || [ ! -x "${src}/bin/xlings" ]; then
    die "archive has no executable bin/xlings"
fi

install_user="${XLINGS_INSTALL_USER:-}"
if [ "$(id -u)" -eq 0 ] && [ -n "$install_user" ]; then
    install_home="$(getent passwd "$install_user" | cut -d: -f6)"
    [ -n "$install_home" ] || die "no home directory for user ${install_user}"
    chown -R "${install_user}" "$extract_dir"
    log "installing into ${install_home}/.xlings as ${install_user}"
    runuser -u "$install_user" -- \
        env HOME="$install_home" XLINGS_NON_INTERACTIVE=1 \
        bash -c "cd $(printf '%q' "$src") && ./bin/xlings self install"
else
    log "installing into ${HOME}/.xlings as $(id -un)"
    (cd "$src" && XLINGS_NON_INTERACTIVE=1 ./bin/xlings self install)
fi

if [ "$(id -u)" -eq 0 ] && [ -n "$install_user" ]; then
    runuser -u "$install_user" -- env HOME="$install_home" "$install_home/.xlings/bin/xlings" --version
else
    "$HOME/.xlings/bin/xlings" --version
fi
