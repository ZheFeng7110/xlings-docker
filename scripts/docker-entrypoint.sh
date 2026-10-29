#!/usr/bin/env bash
#
# Container entrypoint.
#
#   1. Restore the xlings home if a mounted empty directory hides the one baked
#      into the image (offline, from /opt/xlings/xlings.tar.gz).
#   2. Export HOME/PATH/XLINGS_HOME so non-interactive `docker exec` and
#      `docker run IMG xlings ...` work without sourcing a shell profile.
#   3. With XLINGS_AUTO_INSTALL=1, provision the project's .xlings.json before
#      running the command. Off by default: starting a container never installs
#      anything unless the user asked for it.
#   4. Exec the requested command (bash when there is none).

set -euo pipefail

log() { printf '[xlings] %s\n' "$*" >&2; }

: "${HOME:=/home/dev}"
HOME="${HOME%/}"
export HOME
XLINGS_HOME="${XLINGS_HOME:-${HOME}/.xlings}"
XLINGS_HOME="${XLINGS_HOME%/}"
export XLINGS_HOME
export PATH="${XLINGS_HOME}/subos/current/bin:${XLINGS_HOME}/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

restore_home() {
    local baked_home="/home/dev/.xlings"
    local home_snapshot="/opt/xlings/home.tar.gz"
    local bootstrap="/opt/xlings/xlings.tar.gz"
    local tmp src dir
    dir="$XLINGS_HOME"
    [ -d "$dir" ] || dir="$(dirname "$XLINGS_HOME")"
    if [ ! -w "$dir" ]; then
        log "cannot restore xlings: ${dir} is not writable by uid $(id -u)"
        log "use the image's dev user, or mount a writable directory at ${XLINGS_HOME}"
        return 1
    fi

    # Fast path: the default home can be restored from the initialized snapshot,
    # with no network and no package install.
    if [ "$XLINGS_HOME" = "$baked_home" ] && [ -f "$home_snapshot" ]; then
        log "xlings home ${XLINGS_HOME} is empty; restoring the image's home snapshot"
        mkdir -p "$XLINGS_HOME"
        tar -xzf "$home_snapshot" -C "$XLINGS_HOME"
        log "restored $(xlings --version 2>/dev/null || echo 'xlings (unknown version)')"
        return 0
    fi

    # Custom XLINGS_HOME (or no snapshot): install from the release tarball.
    if [ ! -f "$bootstrap" ]; then
        log "xlings is missing from ${XLINGS_HOME} and no bootstrap archive exists"
        return 1
    fi
    log "xlings home ${XLINGS_HOME} is empty; installing from the image"
    tmp="$(mktemp -d)"
    tar -xzf "$bootstrap" -C "$tmp"
    src=""
    for candidate in "$tmp"/xlings-*/; do
        if [ -d "$candidate" ]; then
            src="${candidate%/}"
            break
        fi
    done
    if [ -z "$src" ] || [ ! -x "${src}/bin/xlings" ]; then
        log "bootstrap archive is invalid: ${bootstrap}"
        rm -rf "$tmp"
        return 1
    fi
    (cd "$src" && XLINGS_NON_INTERACTIVE=1 ./bin/xlings self install)
    rm -rf "$tmp"
    log "restored $(xlings --version 2>/dev/null || echo 'xlings (unknown version)')"
}

if [ ! -x "${XLINGS_HOME}/bin/xlings" ]; then
    restore_home
fi

project_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "${dir}/.xlings.json" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    [ -f "/.xlings.json" ] && printf '/\n'
}

if [ "${XLINGS_AUTO_INSTALL:-0}" = "1" ]; then
    root="$(project_root || true)"
    if [ -n "${root:-}" ]; then
        log "XLINGS_AUTO_INSTALL=1: installing project packages from ${root}/.xlings.json"
        if ! xlings install -y; then
            log "project install failed; run 'xlings install -y' in ${root} to retry"
        fi
    else
        log "XLINGS_AUTO_INSTALL=1 is set but no .xlings.json was found from ${PWD} upwards"
    fi
fi

if [ "$#" -eq 0 ]; then
    exec bash
fi

exec "$@"
