# 更新日志

记录 xlings Docker 镜像的重要变更。镜像版本号与内置的 xlings release 版本一致。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [2026.11.16.1] - 2026-11-16

### 变更

- 内置 xlings 从 2026.10.26.1 升级到
  [2026.11.16.1](https://github.com/openxlings/xlings/releases/tag/v2026.11.16.1)。
- 基础镜像从 `ubuntu:24.04` 换为 `debian:trixie-slim`。xlings 自带 glibc 包，
  并会把依赖 glibc 的二进制的 ELF 解释器改到自己的 glibc 上，所以基础镜像的
  libc 只影响少数刻意使用宿主 loader 的包。仍可通过
  `--build-arg BASE_IMAGE=ubuntu:24.04` 使用 Ubuntu 24.04。
- 基础镜像标签改为 `<version>-debian-trixie`，不再发布 `-ubuntu24.04` 后缀。

### 修复

- 在属主为其他 uid 的 bind mount 上恢复 home 快照时，Debian 的 tar 报
  `.: Cannot change mode ... Operation not permitted`。Ubuntu 的 tar 1.35
  回移了上游修复，`--no-overwrite-dir` 不再碰已存在的目录；Debian 的没有。
  现在快照不再包含 `.` 成员，tar 在两种发行版上都不会触碰挂载点，
  入口脚本也不再需要 `--no-overwrite-dir`。

### 测试

- 冒烟测试新增 `node` 作为依赖 glibc 的探针，检查安装后的二进制解释器指向
  xlings 自带的 glibc 而不是宿主的。仅靠 `ninja` 测不出 glibc/elfpatch 链路
  是否正常，因为它是静态二进制。

### 文档

- 修正两份 README 中发布的容器地址。

## [2026.10.26.1] - 2026-10-29

首个版本。

### 新增

- [openxlings/xlings](https://github.com/openxlings/xlings) 包管理器的容器镜像，
  固定 xlings 2026.10.26.1，构建时校验 release 的 SHA-256。
- 非 root 用户 `dev`（uid/gid 1000，可用 `DEV_UID` / `DEV_GID` 覆盖），
  挂载的项目目录不会产生 root 属主文件。
- `linux/amd64` 与 `linux/arm64` 镜像发布到 GHCR，标签为 `<version>`、
  `<version>-ubuntu24.04`、`latest` 和 `sha-<short>`。
- 入口脚本在空卷遮蔽 home 时从镜像内快照离线恢复；设置
  `XLINGS_AUTO_INSTALL=1` 可按 `.xlings.json` 自动安装项目依赖。
- 构建参数：下载源与默认镜像源（`XLINGS_DOWNLOAD_BASE`、
  `XLINGS_DEFAULT_MIRROR`），以及派生镜像预装包（`XLINGS_PACKAGES`）。
- devcontainer 与 compose 示例、镜像级冒烟测试、带 shellcheck 和 hadolint
  的 CI 工作流。
- 中文 README 之外新增英文 README。

### 修复

- 在宿主用户属主的 bind mount 上恢复 home 快照。
- GitHub Actions 触发分支名，以及安装脚本中的 shellcheck SC2015。

[2026.11.16.1]: https://github.com/ZheFeng7110/xlings-docker/compare/v2026.10.26.1...v2026.11.16.1
[2026.10.26.1]: https://github.com/ZheFeng7110/xlings-docker/releases/tag/v2026.10.26.1
