# Changelog

All notable changes to the xlings Docker image are recorded here. The image
version follows the pinned xlings release it ships.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2026.11.16.1] - 2026-11-16

### Changed

- Pinned xlings updated from 2026.10.26.1 to
  [2026.11.16.1](https://github.com/openxlings/xlings/releases/tag/v2026.11.16.1).
- Base image switched from `ubuntu:24.04` to `debian:trixie-slim`. xlings
  ships its own glibc package and rewrites the ELF interpreter of glibc-linked
  payloads to point at it, so the base image's libc only matters for the few
  packages that deliberately stay on the host loader. Ubuntu 24.04 still works
  through `--build-arg BASE_IMAGE=ubuntu:24.04`.
- The base-image tag is now `<version>-debian-trixie`. The `-ubuntu24.04`
  suffix is no longer published.

### Fixed

- Restoring the home snapshot over a bind mount owned by another uid failed on
  Debian's tar with `.: Cannot change mode ... Operation not permitted`. Ubuntu's
  tar 1.35 carries an upstream fix that makes `--no-overwrite-dir` leave existing
  directories alone; Debian's does not. The snapshot is now built without a `.`
  member, so tar never touches the mount point on either tar, and the entrypoint
  no longer needs `--no-overwrite-dir`.

### Tests

- The smoke suite installs `node` as a glibc-linked probe and checks that the
  installed binary's interpreter points at xlings' glibc rather than the host's.
  `ninja` alone could not catch a broken glibc/elfpatch chain, because it is a
  static binary.

### Docs

- Corrected the published container URL in both READMEs.

## [2026.10.26.1] - 2026-10-29

First release.

### Added

- Container image for the [openxlings/xlings](https://github.com/openxlings/xlings)
  package manager, pinned to xlings 2026.10.26.1 with the release SHA-256
  verified at build time.
- Non-root `dev` user (uid/gid 1000, overridable with `DEV_UID` / `DEV_GID`)
  so bind-mounted project directories are not left with root-owned files.
- `linux/amd64` and `linux/arm64` images published to GHCR with
  `<version>`, `<version>-ubuntu24.04`, `latest` and `sha-<short>` tags.
- Entrypoint that restores the xlings home offline from an in-image snapshot
  when an empty volume hides it, and optional project provisioning from
  `.xlings.json` via `XLINGS_AUTO_INSTALL=1`.
- Build arguments for the download source and default package mirror
  (`XLINGS_DOWNLOAD_BASE`, `XLINGS_DEFAULT_MIRROR`) and for preinstalling
  packages into a derived image (`XLINGS_PACKAGES`).
- devcontainer and compose examples, image-level smoke tests, and a CI
  workflow with shellcheck and hadolint.
- English README alongside the Chinese one.

### Fixed

- Home snapshot restore over a bind mount owned by the host user.
- GitHub Actions trigger branch name and shellcheck SC2015 in the installer.

[2026.11.16.1]: https://github.com/ZheFeng7110/xlings-docker/compare/v2026.10.26.1...v2026.11.16.1
[2026.10.26.1]: https://github.com/ZheFeng7110/xlings-docker/releases/tag/v2026.10.26.1
