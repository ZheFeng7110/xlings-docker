#!/usr/bin/env bash
#
# Image-level smoke tests. Run against a built image:
#
#   IMAGE=xlings-docker:dev ./tests/smoke.sh
#   SMOKE_NETWORK=0 IMAGE=xlings-docker:dev ./tests/smoke.sh   # no package downloads
#
# Network tests install ninja@1.12.1, the same tiny static probe the upstream
# xlings CI uses. They need access to the package index and resource server.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"

IMAGE="${IMAGE:-xlings-docker:test}"
XLINGS_VERSION="${XLINGS_VERSION:-$(sed -n 's/^ARG XLINGS_VERSION=//p' "${ROOT}/Dockerfile")}"
NINJA_VERSION="${NINJA_VERSION:-1.12.1}"
SMOKE_UID="${SMOKE_UID:-1000}"
SMOKE_NETWORK="${SMOKE_NETWORK:-1}"
SMOKE_DERIVED="${SMOKE_DERIVED:-${SMOKE_NETWORK}}"

VOLUME="xlings-smoke-$$"
RESTORE_VOLUME="xlings-smoke-restore-$$"
TMPDIRS=()
DERIVED_IMAGE="xlings-smoke-derived:$$"

cleanup_dir() {
    local dir="$1"
    # Container-written files can be owned by uid 1000 while the CI runner uses
    # another uid, so the host cannot always delete them. Remove them through
    # the image itself (as root), then drop the now-empty host directory.
    docker run --rm --user root --entrypoint sh -v "${dir}:/cleanup" "$IMAGE" \
        -c 'rm -rf /cleanup/* /cleanup/.[!.]*' >/dev/null 2>&1 || true
    rm -rf "$dir" 2>/dev/null || true
}

cleanup() {
    local dir
    for dir in ${TMPDIRS[@]+"${TMPDIRS[@]}"}; do
        cleanup_dir "$dir"
    done
    docker volume rm -f "$VOLUME" "$RESTORE_VOLUME" >/dev/null 2>&1 || true
    docker image rm -f "$DERIVED_IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

section() { printf '\n==> %s\n' "$*"; }
ok() { printf '    ok: %s\n' "$*"; }
die() { printf '    FAIL: %s\n' "$*" >&2; exit 1; }

run() {
    printf '    $ %s\n' "$*"
    "$@"
}

# Like run, but capture combined output in $out. A failing command substitution
# would otherwise abort the script under `set -e` without showing what the
# container printed, which is exactly what is needed to debug a failure.
capture() {
    local status
    out="$("$@" 2>&1)" && return 0
    status=$?
    if [ "$status" -ne 0 ]; then
        printf '    $ %s\n' "$*"
        printf '%s\n' "$out" | sed 's/^/    | /' >&2
        printf '    FAIL: command exited %s\n' "$status" >&2
        exit 1
    fi
}

new_tmp() {
    # Sets NEW_TMP in the caller's shell. Do not call this through $(...):
    # a command substitution runs in a subshell, where the TMPDIRS update would
    # be lost and the directory never cleaned up.
    NEW_TMP="$(mktemp -d "${SMOKE_TMPDIR:-${ROOT}/.smoke}.XXXXXX")"
    TMPDIRS+=("$NEW_TMP")
    chmod 0777 "$NEW_TMP"
}

[ -n "$XLINGS_VERSION" ] || die "cannot read XLINGS_VERSION from Dockerfile"

printf 'image:   %s\n' "$IMAGE"
printf 'version: %s\n' "$XLINGS_VERSION"
printf 'network: %s\n' "$SMOKE_NETWORK"

section "image version"
capture docker run --rm "$IMAGE" xlings --version
printf '    %s\n' "$out"
case "$out" in
    *"$XLINGS_VERSION"*) ok "xlings reports ${XLINGS_VERSION}" ;;
    *) die "expected version ${XLINGS_VERSION} in: ${out}" ;;
esac

section "default user"
# shellcheck disable=SC2016  # expanded inside the container
capture docker run --rm "$IMAGE" sh -c 'printf "%s %s" "$(id -u)" "$HOME"'
[ "$out" = "${SMOKE_UID} /home/dev" ] || die "expected '${SMOKE_UID} /home/dev', got '${out}'"
ok "runs as dev (uid ${SMOKE_UID}) with HOME=/home/dev"

section "entrypoint passthrough"
capture docker run --rm "$IMAGE" sh -c 'xlings --version'
case "$out" in
    *"$XLINGS_VERSION"*) ok "command form works" ;;
    *) die "passthrough failed: ${out}" ;;
esac

section "self-heal over an empty home mount"
new_tmp; dir="$NEW_TMP"
capture docker run --rm -v "${dir}:/home/dev/.xlings" "$IMAGE" xlings --version
case "$out" in
    *"home snapshot"*) ok "restored the home offline from the image snapshot" ;;
    *) die "self-heal did not use the home snapshot:
${out}" ;;
esac
case "$out" in
    *"$XLINGS_VERSION"*) ;;
    *) die "self-heal produced the wrong version:
${out}" ;;
esac

section "self-heal over a home mount owned by another uid"
# A bind-mounted home belongs to the host user, which is often not the
# container's dev uid. Restoring the snapshot must not fail just because it
# cannot apply the archive's mode and mtime to the mount point itself.
# volume-nocopy keeps the volume empty so the entrypoint takes the restore path,
# and a root-owned 0777 directory is writable but not owned by dev.
run docker volume create "$RESTORE_VOLUME"
run docker run --rm --user root --entrypoint sh \
    --mount "type=volume,source=${RESTORE_VOLUME},target=/home/dev/.xlings,volume-nocopy" \
    "$IMAGE" -c 'chown 0:0 /home/dev/.xlings; chmod 0777 /home/dev/.xlings'
capture docker run --rm \
    --mount "type=volume,source=${RESTORE_VOLUME},target=/home/dev/.xlings,volume-nocopy" \
    "$IMAGE" xlings --version
case "$out" in
    *"home snapshot"*) ok "restored the snapshot over a foreign-owned mount" ;;
    *) die "self-heal failed on a foreign-owned mount:
${out}" ;;
esac

section "self doctor"
docker run --rm "$IMAGE" xlings self doctor >/dev/null
ok "home is healthy"

section "root user with the image home"
capture docker run --rm --user root -e XLINGS_HOME=/home/dev/.xlings "$IMAGE" xlings --version
case "$out" in
    *"$XLINGS_VERSION"*) ok "xlings works as root too" ;;
    *) die "root run failed: ${out}" ;;
esac

section "project install is off by default"
new_tmp; dir="$NEW_TMP"
cp "${HERE}/fixtures/project/.xlings.json" "${dir}/"
docker run --rm -v "${dir}:/workspace" "$IMAGE" sh -c 'test ! -e .xlings' \
    || die "the entrypoint installed a project without XLINGS_AUTO_INSTALL=1"
ok "no project packages installed without opt-in"

if [ "$SMOKE_NETWORK" = "1" ]; then
    section "global lifecycle: install, run, list, remove"
    run docker run --rm -i -e NINJA_VERSION="$NINJA_VERSION" "$IMAGE" bash -s <<'SCRIPT'
set -euo pipefail
xlings install -y -g "ninja@${NINJA_VERSION}"
ninja --version | grep -qx "${NINJA_VERSION}"
xlings list | tr -d '\0' | grep -qi ninja
xlings remove ninja -y
if command -v ninja >/dev/null 2>&1; then
    echo "ninja is still on PATH after removal" >&2
    exit 1
fi
SCRIPT
    ok "global install/remove works"

    section "project install from .xlings.json"
    new_tmp; dir="$NEW_TMP"
    cp "${HERE}/fixtures/project/.xlings.json" "${dir}/"
    run docker run --rm -v "${dir}:/workspace" "$IMAGE" bash -c '
set -euo pipefail
xlings install -y
test -x .xlings/subos/_/bin/ninja
.xlings/subos/_/bin/ninja --version | grep -q "^1\.12\.1"
'
    ok "project subos created at .xlings/subos/_"

    section "project root is found from a subdirectory"
    new_tmp; dir="$NEW_TMP"
    cp "${HERE}/fixtures/project/.xlings.json" "${dir}/"
    mkdir -p "${dir}/sub"
    chmod 0777 "${dir}/sub"
    run docker run --rm -w /workspace/sub -v "${dir}:/workspace" "$IMAGE" bash -c '
set -euo pipefail
xlings install -y
test -x ../.xlings/subos/_/bin/ninja
'
    ok "parent .xlings.json detected"

    section "XLINGS_AUTO_INSTALL=1"
    new_tmp; dir="$NEW_TMP"
    cp "${HERE}/fixtures/project/.xlings.json" "${dir}/"
    run docker run --rm -e XLINGS_AUTO_INSTALL=1 -v "${dir}:/workspace" "$IMAGE" \
        sh -c 'test -x .xlings/subos/_/bin/ninja && .xlings/subos/_/bin/ninja --version'
    ok "entrypoint provisioned the project before the command"

    section "installs survive a container restart"
    run docker volume create "$VOLUME"
    run docker run --rm -v "${VOLUME}:/home/dev/.xlings" "$IMAGE" \
        xlings install -y -g "ninja@${NINJA_VERSION}"
    run docker run --rm -v "${VOLUME}:/home/dev/.xlings" "$IMAGE" \
        sh -c 'xlings list | tr -d "\0" | grep -qi ninja'
    ok "named volume keeps packages between runs"

    if [ "$SMOKE_DERIVED" = "1" ]; then
        section "derived image with preinstalled packages"
        new_tmp; dir="$NEW_TMP"
        cat > "${dir}/Dockerfile" <<EOF
FROM ${IMAGE}
RUN xlings install -y -g ninja@${NINJA_VERSION}
RUN xlings list | tr -d '\\0' | grep -qi ninja
EOF
        run docker build -t "$DERIVED_IMAGE" "$dir"
        run docker run --rm "$DERIVED_IMAGE" ninja --version
        ok "FROM + RUN xlings install works"
    else
        printf '\n==> derived image test skipped (SMOKE_DERIVED=0)\n'
    fi
else
    printf '\n==> network tests skipped (SMOKE_NETWORK=0)\n'
fi

printf '\nAll smoke tests passed.\n'
