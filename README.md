[中文](README_zh.md) | **English**

# xlings Docker image

Puts the [openxlings/xlings](https://github.com/openxlings/xlings) package manager into a container: interactive `xlings install` / `remove` / `use`, plus support for a project-level `.xlings.json` that installs project dependencies into the project's own SubOS.

- Pinned xlings version, with the release SHA-256 verified at build time
- Non-root `dev` user by default (uid/gid 1000), so mounted project directories are not left with root-owned files
- Two architectures: `linux/amd64`, `linux/arm64`
- Usable as a base image for preinstalling a team toolchain
- Automatically recovers offline when the home directory is shadowed by an empty volume

## Quick start

```bash
# Build locally
docker build -t xlings-docker:dev .

# Or use the published image
docker run --rm -it \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/ZheFeng7110/xlings-docker:latest
```

Inside the container:

```bash
xlings install node@20
node --version
xlings use node@20
xlings list
xlings remove node@20 -y
```

`docker run` needs `-it` for the full interactive experience; for non-interactive use (CI), pass the command directly:

```bash
docker run --rm ghcr.io/ZheFeng7110/xlings-docker:latest xlings install -y node@20
docker run --rm ghcr.io/ZheFeng7110/xlings-docker:latest xlings --version
```

## Project-level `.xlings.json`

Put a `.xlings.json` in the project root:

```json
{
  "workspace": {
    "ninja": "1.12.1"
  }
}
```

Mount the project and install:

```bash
cd my-project

docker run --rm -it \
  -v "$PWD:/workspace" \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/ZheFeng7110/xlings-docker:latest

# Inside the container (current directory is /workspace)
xlings install -y
ninja --version
```

xlings searches upwards from the current directory for `.xlings.json` and creates `.xlings/subos/_/` in the project root. Project dependencies live inside the project directory and do not depend on the home volume.

To install automatically at container startup, enable it explicitly (off by default):

```bash
docker run --rm -it \
  -e XLINGS_AUTO_INSTALL=1 \
  -v "$PWD:/workspace" \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/ZheFeng7110/xlings-docker:latest
```

The entrypoint runs `xlings install -y`; a failure only prints a notice and does not block entry into the shell. This also works in CI:

```bash
docker run --rm \
  -e XLINGS_AUTO_INSTALL=1 \
  -v "$PWD:/workspace" \
  ghcr.io/ZheFeng7110/xlings-docker:latest \
  xlings list
```

Add the directory generated in your project to your own `.gitignore`:

```gitignore
.xlings/
```

> Permissions: the `dev` user inside the image is uid/gid 1000. If your host user is not 1000,
> rebuild with `--build-arg DEV_UID=$(id -u) --build-arg DEV_GID=$(id -g)`, or make the mounted
> directory writable for uid 1000.

## Persistence

Packages are installed in `/home/dev/.xlings`; persist them with a named volume:

```bash
docker run --rm -it -v xlings-home:/home/dev/.xlings xlings-docker:dev
```

- **A named volume is recommended**: on first use, Docker copies the already-initialized home from the image.
- **Do not** bind mount an empty host directory onto `/home/dev/.xlings`; it hides the image contents. Even if that happens, the entrypoint restores the home offline from the in-image snapshot `/opt/xlings/home.tar.gz` (with a custom `XLINGS_HOME` it falls back to re-running `self install` from the release package).
- Project dependencies live in the project's `.xlings/` and persist with the project, independent of the home volume.

## Using as a base image

`USER dev` carries over to subsequent `RUN` instructions, so packages can be preinstalled directly:

```dockerfile
FROM ghcr.io/ZheFeng7110/xlings-docker:2026.10.26.1

RUN xlings install -y -g ninja@1.12.1 node@20
```

You can also install packages in bulk at build time:

```bash
docker build \
  --build-arg XLINGS_PACKAGES="ninja@1.12.1 node@20" \
  -t my-team/xlings:latest .
```

When you need root:

```dockerfile
USER root
RUN apt-get update && apt-get install -y --no-install-recommends something
USER dev
```

## Build

```bash
make build          # local architecture
make smoke          # image-level tests (IMAGE=xlings-docker:dev)
make test           # build + smoke
make build-multi    # amd64 + arm64, no push
make push           # push IMAGE:TAG; run docker login ghcr.io first
```

Common build arguments:

| Argument | Default | Description |
|---|---|---|
| `BASE_IMAGE` | `ubuntu:24.04` | Base image (only Ubuntu 24.04 is tested so far) |
| `XLINGS_VERSION` | `2026.10.26.1` | Pinned xlings release version |
| `XLINGS_DOWNLOAD_BASE` | GitHub releases | Base URL for release downloads; can point at a mirror |
| `XLINGS_DEFAULT_MIRROR` | `GLOBAL` | Default package index mirror written into the home (`GLOBAL` / `CN`) |
| `XLINGS_PACKAGES` | empty | Packages to preinstall at build time, space-separated |
| `DEV_UID` / `DEV_GID` | `1000` / `1000` | uid/gid of the `dev` user |

If your network has trouble reaching GitHub, switch the build download source and make the image use the CN index by default:

```bash
docker build \
  --build-arg XLINGS_DOWNLOAD_BASE=https://gitcode.com/xlings-res/xlings/releases/download \
  --build-arg XLINGS_DEFAULT_MIRROR=CN \
  -t xlings-docker:dev .
```

`XLINGS_DOWNLOAD_BASE` must serve files as `<base>/v<version>/<asset>` and provide the matching
`.sha256` alongside them. If a source is unreachable, any GitHub release proxy works too, for example
`https://ghfast.top/https://github.com/openxlings/xlings/releases/download`.

To switch the package index mirror at runtime (written into the home, persistent):

```bash
docker run --rm -it -v xlings-home:/home/dev/.xlings xlings-docker:dev \
  xlings config --mirror CN
```

## Tags

| Tag | Contents |
|---|---|
| `2026.10.26.1` | Pinned xlings version |
| `2026.10.26.1-ubuntu24.04` | Version + base image |
| `latest` | Latest stable combination |
| `sha-<short>` | Corresponding commit |

> The image is published to `ghcr.io/<github-owner>/xlings-docker`; for this repository that is `ghcr.io/ZheFeng7110/xlings-docker`.

## devcontainer / compose

- [`examples/devcontainer/devcontainer.json`](examples/devcontainer/devcontainer.json): VS Code Dev Containers, using the `dev` user, with `postCreateCommand` installing project dependencies automatically.
- [`examples/compose.yaml`](examples/compose.yaml): run `docker compose up` in the `examples/` directory; that directory is mounted as `/workspace`.

## Sandbox inside the container / Luban

The xlings SubOS sandbox needs bwrap and unprivileged user namespaces. Docker's default seccomp profile usually blocks it, so extra flags are required:

```bash
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  -v xlings-home:/home/dev/.xlings \
  xlings-docker:dev
```

Then check:

```bash
xlings self doctor --isolation
```

Notes:

- The container itself is the isolation boundary here; the nested sandbox is mainly for development and testing and should not be the only defense for untrusted code.
- On some hosts (rootless Docker, restricted AppArmor/seccomp) bwrap cannot work even with these flags; `xlings subos status <name>` explains why.
- Luban OS and nested kernels or virtual machines are out of scope for this image.

## Troubleshooting

```bash
# Self-check inside the image
xlings self doctor

# If home was shadowed or xlings disappeared, the entrypoint recovers automatically; manually you can:
# restart the container, or mount a named volume

# Inspect the current home, mirror and SubOS
xlings self config

# Garbled output or TUI problems in non-interactive environments
xlings --agent <command>
```

Common issues:

| Symptom | Cause / fix |
|---|---|
| `xlings: command not found` | The user was changed with `--user` but `HOME` is not writable; use the default `dev` user, or set a writable `HOME`/`XLINGS_HOME` |
| First start is very slow when running as root | `--user root` runs `self install` once in `/root/.xlings` (needs network); reuse the in-image home with `-e XLINGS_HOME=/home/dev/.xlings` |
| Project install fails with permission denied | Host uid differs from 1000; rebuild with `DEV_UID/DEV_GID`, or fix the directory permissions |
| Package installs are slow or fail | Switch the mirror with `xlings config --mirror CN`, or check your network/proxy |
| `xlings` output is not in the expected language | `xlings config --lang zh` / `--lang en` |
| Sandbox will not start | See the previous section; extra Docker flags are required |

## Testing

```bash
make build
IMAGE=xlings-docker:dev ./tests/smoke.sh

# Skip cases that need to download packages; pass the same uid if you changed it at build time
SMOKE_NETWORK=0 SMOKE_UID=1000 IMAGE=xlings-docker:dev ./tests/smoke.sh
```

Even without a real install locally, the tests still verify the version, the user, entrypoint passthrough, home self-healing, and that auto-install is off by default.
If you changed the uid at build time, run the tests with the same value, e.g. `make build DEV_UID=2000`
followed by `make smoke DEV_UID=2000`.

## License

Files in this repository are under [MIT](LICENSE). The xlings distributed inside the image comes from
[openxlings/xlings](https://github.com/openxlings/xlings) and is under Apache-2.0; its license text is
at `/usr/share/doc/xlings/LICENSE` in the image. The base image and packages installed through xlings
each follow their own licenses.
