# grok-build-canary

xAI [grok-build](https://github.com/xai-org/grok-build)（SpaceXAI 终端编码助手 / TUI harness）的**定时多架构镜像构建**仓库。所有构建都在 GitHub Actions 上完成，本地零构建。

![workflow](https://github.com/nextpoint999/grok-build-canary/actions/workflows/grok-build-mirror.yml/badge.svg)

## 特点

- **定时**: 每 2h 轮询上游 `main`，有新 commit 自动构建并刷新 release
- **多架构**: linux / darwin / win32 × arm64 / x64，共 6 平台（与上游 npm 平台包一致）
- **版本**: release tag/name 为上游 npm 元包版本加 `v` 前缀（如 `v0.1.220-alpha.4`）；release body 记录上游 commit SHA
- **自动刷新**: 上游 commit 变化时原位刷新同一 release 的二进制（tag 不变，Latest 徽标不回退）
- 二进制构建尊重上游 `.cargo/config.toml` 的平台链接标志（Linux 额外 strip 减体积；macOS/Windows 与上游一致不 strip）

## 安装

从 [Releases](https://github.com/nextpoint999/grok-build-canary/releases) 下载对应平台资产：

| 平台 | 资产 |
|---|---|
| Linux x64 | `grok-linux-x64` |
| Linux arm64 | `grok-linux-arm64` |
| macOS x64 | `grok-darwin-x64` |
| macOS arm64 | `grok-darwin-arm64` |
| Windows x64 | `grok-win32-x64.exe` |
| Windows arm64 | `grok-win32-arm64.exe` |

```bash
# Linux/macOS 示例
curl -fsSL -o grok https://github.com/nextpoint999/grok-build-canary/releases/latest/download/grok-linux-x64
chmod +x grok && ./grok
```

> 上游官方安装渠道: `curl -fsSL https://x.ai/cli/install.sh | bash`（需要登录 xAI 账号）。本镜像仅提供预编译二进制，运行时的认证与官方版一致。

## 手动构建

Actions 页面 → **Run workflow**：

- `ref`: 上游 git ref（分支或 commit，默认 `main`）
- `force`: 强制重建（即使上游 commit 无变化）
- `latest`: `auto`（默认，构建后钉为 Latest）/ `set` / `keep`

## 说明

- 上游 `xai-org/grok-build` 不发布 GitHub Releases，也不开放构建流程（内部 CI）；本仓库按上游 npm 包 `@xai-official/grok` 的版本号 + 提交 SHA 追踪构建。
- 上游仓库 LICENSE: Apache-2.0。
