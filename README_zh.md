**中文** | [English](README.md)

# xlings Docker 镜像

把 [openxlings/xlings](https://github.com/openxlings/xlings) 包管理器装进容器：交互式 `xlings install` / `remove` / `use`，并支持读取项目目录的 `.xlings.json`，把项目依赖装进项目自己的 SubOS。

- 固定 xlings 版本，构建时校验 release 的 SHA-256
- 默认非 root 用户 `dev`（uid/gid 1000），项目目录不会产生 root 属主文件
- 双架构：`linux/amd64`、`linux/arm64`
- 可作为基础镜像派生，预装团队工具链
- home 被空卷覆盖时自动离线恢复

## 快速开始

```bash
# 本地构建
docker build -t xlings-docker:dev .

# 或使用已发布镜像
docker run --rm -it \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/zhefeng7110/xlings-docker:latest
```

进入容器后：

```bash
xlings install node@20
node --version
xlings use node@20
xlings list
xlings remove node@20 -y
```

`docker run` 需要 `-it` 才能获得完整的交互体验；非交互场景（CI）直接用命令形式：

```bash
docker run --rm ghcr.io/zhefeng7110/xlings-docker:latest xlings install -y node@20
docker run --rm ghcr.io/zhefeng7110/xlings-docker:latest xlings --version
```

## 项目级 `.xlings.json`

在项目根目录放一个 `.xlings.json`：

```json
{
  "workspace": {
    "ninja": "1.12.1"
  }
}
```

挂载项目并安装：

```bash
cd my-project

docker run --rm -it \
  -v "$PWD:/workspace" \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/zhefeng7110/xlings-docker:latest

# 容器内（当前目录 /workspace）
xlings install -y
ninja --version
```

xlings 会从当前目录向上查找 `.xlings.json`，并在项目根创建 `.xlings/subos/_/`。项目依赖装在项目目录内，不依赖 home 卷。

如果希望容器启动时自动安装，显式开启（默认关闭）：

```bash
docker run --rm -it \
  -e XLINGS_AUTO_INSTALL=1 \
  -v "$PWD:/workspace" \
  -v xlings-home:/home/dev/.xlings \
  ghcr.io/zhefeng7110/xlings-docker:latest
```

入口脚本会执行 `xlings install -y`；失败只打印提示，不阻塞进入 shell。CI 中也可以这样用：

```bash
docker run --rm \
  -e XLINGS_AUTO_INSTALL=1 \
  -v "$PWD:/workspace" \
  ghcr.io/zhefeng7110/xlings-docker:latest \
  xlings list
```

建议把项目生成的目录加入你自己的 `.gitignore`：

```gitignore
.xlings/
```

> 权限说明：镜像内的 `dev` 用户是 uid/gid 1000。宿主机用户不是 1000 时，用
> `--build-arg DEV_UID=$(id -u) --build-arg DEV_GID=$(id -g)` 重新构建，或让挂载目录对 uid 1000 可写。

## 持久化

包安装在 `/home/dev/.xlings`，用命名卷保存：

```bash
docker run --rm -it -v xlings-home:/home/dev/.xlings xlings-docker:dev
```

- **推荐命名卷**：Docker 首次使用时会复制镜像内已经初始化好的 home。
- **不要**用空宿主目录 bind mount 到 `/home/dev/.xlings`，它会遮蔽镜像内容。即使发生，入口脚本也会从镜像内的 home 快照 `/opt/xlings/home.tar.gz` 离线恢复（自定义 `XLINGS_HOME` 时回退到 release 包重新 `self install`）。
- 项目依赖在项目目录的 `.xlings/` 里，随项目持久化，与 home 卷无关。

## 作为基础镜像

`USER dev` 会延续到后续 `RUN`，可以直接预装包：

```dockerfile
FROM ghcr.io/zhefeng7110/xlings-docker:2026.10.26.1

RUN xlings install -y -g ninja@1.12.1 node@20
```

也可以构建时批量安装：

```bash
docker build \
  --build-arg XLINGS_PACKAGES="ninja@1.12.1 node@20" \
  -t my-team/xlings:latest .
```

需要 root 操作时：

```dockerfile
USER root
RUN apt-get update && apt-get install -y --no-install-recommends something
USER dev
```

## 构建

```bash
make build          # 本地架构
make smoke          # 镜像级测试（IMAGE=xlings-docker:dev）
make test           # build + smoke
make build-multi    # amd64 + arm64，不推送
make push           # 推送 IMAGE:TAG，先 docker login ghcr.io
```

常用构建参数：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `BASE_IMAGE` | `ubuntu:24.04` | 基础镜像（目前只测试 Ubuntu 24.04） |
| `XLINGS_VERSION` | `2026.10.26.1` | 固定的 xlings release 版本 |
| `XLINGS_DOWNLOAD_BASE` | GitHub releases | release 下载基地址，可换镜像源 |
| `XLINGS_DEFAULT_MIRROR` | `GLOBAL` | 写入 home 的默认索引镜像（`GLOBAL` / `CN`） |
| `XLINGS_PACKAGES` | 空 | 构建时预装的包，空格分隔 |
| `DEV_UID` / `DEV_GID` | `1000` / `1000` | `dev` 用户的 uid/gid |

国内网络可以给构建换下载源，并让镜像默认使用国内索引：

```bash
docker build \
  --build-arg XLINGS_DOWNLOAD_BASE=https://gitcode.com/xlings-res/xlings/releases/download \
  --build-arg XLINGS_DEFAULT_MIRROR=CN \
  -t xlings-docker:dev .
```

`XLINGS_DOWNLOAD_BASE` 必须是“能按 `<base>/v<version>/<asset>` 提供文件”的镜像源，
并且同时提供对应的 `.sha256`；如果某个源不可达，也可以换成任意 GitHub release 代理，例如
`https://ghfast.top/https://github.com/openxlings/xlings/releases/download`。

运行时切换包索引镜像（写入 home，持久生效）：

```bash
docker run --rm -it -v xlings-home:/home/dev/.xlings xlings-docker:dev \
  xlings config --mirror CN
```

## 标签

| Tag | 内容 |
|---|---|
| `2026.10.26.1` | 固定 xlings 版本 |
| `2026.10.26.1-ubuntu24.04` | 版本 + 基础镜像 |
| `latest` | 最新稳定组合 |
| `sha-<short>` | 对应提交 |

> 镜像发布到 `ghcr.io/<github-owner>/xlings-docker`，本仓库对应 `ghcr.io/zhefeng7110/xlings-docker`。

## devcontainer / compose

- [`examples/devcontainer/devcontainer.json`](examples/devcontainer/devcontainer.json)：VS Code Dev Containers，使用 `dev` 用户，`postCreateCommand` 自动安装项目依赖。
- [`examples/compose.yaml`](examples/compose.yaml)：在 `examples/` 目录里直接 `docker compose up`，挂载该目录作为 `/workspace`。

## 容器内 sandbox / Luban

xlings 的 SubOS sandbox 依赖 bwrap 和非特权 user namespace。Docker 默认 seccomp 配置通常会阻止它，需要额外参数：

```bash
docker run --rm -it \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  -v xlings-home:/home/dev/.xlings \
  xlings-docker:dev
```

然后检查：

```bash
xlings self doctor --isolation
```

注意：

- 容器本身才是这里的隔离边界；嵌套 sandbox 主要用于开发/测试，不应作为不可信代码的唯一防线。
- 某些宿主机（rootless Docker、受限的 AppArmor/seccomp）即使加了参数也无法使用 bwrap，`xlings subos status <name>` 会说明原因。
- Luban OS、嵌套内核/虚拟机不属于本镜像的目标场景。

## 故障排查

```bash
# 镜像内自检
xlings self doctor

# home 被覆盖 / xlings 消失时，入口脚本会自动恢复；也可以手动：
# 重新运行容器，或挂载命名卷

# 查看当前 home、镜像源、SubOS
xlings self config

# 非交互环境输出乱码或 TUI 问题
xlings --agent <command>
```

常见问题：

| 现象 | 原因 / 处理 |
|---|---|
| `xlings: command not found` | 用 `--user` 改了用户但 `HOME` 不可写；改用默认 `dev` 用户，或设置可写的 `HOME`/`XLINGS_HOME` |
| 以 root 运行时首次启动很慢 | `--user root` 会在 `/root/.xlings` 执行一次 `self install`（需要网络）；复用镜像内 home 可加 `-e XLINGS_HOME=/home/dev/.xlings` |
| 项目安装报 permission denied | 宿主机 uid 与 1000 不一致；用 `DEV_UID/DEV_GID` 重建，或调整目录权限 |
| 安装包很慢/失败 | 切镜像源 `xlings config --mirror CN`，或检查网络代理 |
| `xlings` 输出中文/英文不符合预期 | `xlings config --lang zh` / `--lang en` |
| sandbox 无法启动 | 见上一节，需要额外 Docker 参数 |

## 测试

```bash
make build
IMAGE=xlings-docker:dev ./tests/smoke.sh

# 跳过需要下载包的用例；如果构建时改过 uid，传入相同的值
SMOKE_NETWORK=0 SMOKE_UID=1000 IMAGE=xlings-docker:dev ./tests/smoke.sh
```

本地不跑真实安装时，仍会验证版本、用户、入口透传、home 自愈、默认不自动安装。
如果构建时改过 uid，用相同的值跑测试，例如 `make build DEV_UID=2000` 后
`make smoke DEV_UID=2000`。

## 许可证

本仓库的文件使用 [MIT](LICENSE)。镜像内分发的 xlings 来自
[openxlings/xlings](https://github.com/openxlings/xlings)，使用 Apache-2.0，
许可证文本位于镜像的 `/usr/share/doc/xlings/LICENSE`；
基础镜像和通过 xlings 安装的软件包分别遵循它们自己的许可证。
