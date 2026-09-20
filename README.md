<div align="center">

<img src="./docs/public/clashbar-logo.png" width="220" alt="ClashBarPlus Logo" />

# ClashBarPlus

原生 macOS 菜单栏代理客户端，基于 `SwiftUI + AppKit`，由 `mihomo` 驱动。
轻量、稳定，在菜单栏完成配置、节点、规则、连接与系统代理管理。 ✨

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-13%2B-111111?style=flat-square&logo=apple" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift" />
  <img alt="Build" src="https://img.shields.io/badge/Build-SwiftPM-0A84FF?style=flat-square" />
  <img alt="i18n" src="https://img.shields.io/badge/i18n-zh--Hans%20%7C%20en-34C759?style=flat-square" />
  <img alt="Upstream" src="https://img.shields.io/badge/Fork_of-Sitoi%2FClashBar-8B5CF6?style=flat-square&logo=github" />
  <a href="https://github.com/Gongsc/ClashBar/releases" target="_blank" rel="noopener noreferrer">
    <img alt="Version" src="https://img.shields.io/github/v/release/Gongsc/ClashBar?style=flat-square&logo=github" />
  </a>
  <a href="https://github.com/Gongsc/ClashBar/issues" target="_blank" rel="noopener noreferrer">
    <img alt="Issues" src="https://img.shields.io/github/issues/Gongsc/ClashBar?style=flat-square&logo=github" />
  </a>
  <a href="https://github.com/Gongsc/ClashBar/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">
    <img alt="License" src="https://img.shields.io/github/license/Gongsc/ClashBar?style=flat-square" />
  </a>
</p>

</div>

<p>
  <img src="./docs/public/clashbar-black.png" width="49%" alt="ClashBarPlus Dark" />
  <img src="./docs/public/clashbar-light.png" width="49%" alt="ClashBarPlus Light" />
</p>

## 🔀 与上游的关系

ClashBarPlus 是 [Sitoi/ClashBar](https://github.com/Sitoi/ClashBar) 的 fork，基线为上游 **v0.3.3**。上游的全部功能都在，这里只做增量改动，并会持续同步上游更新。

|                | ClashBarPlus                                    | 上游 ClashBar                    |
| -------------- | ----------------------------------------------- | -------------------------------- |
| 版本号         | 自 `v1.0.0` 起独立编号，不跟随上游              | `v0.3.x`                         |
| 安装方式       | 仅 Releases 下载 DMG                            | Homebrew Cask / DMG              |
| Bundle ID      | `com.clashbar`（与上游一致）                    | `com.clashbar`                   |
| 数据目录       | `~/Library/Application Support/clashbar`（一致）| 同左                             |

> [!IMPORTANT]
> ClashBarPlus 刻意保留了上游的 Bundle ID、数据目录与特权助手标签。这意味着**覆盖安装即原地升级**——既有配置、订阅、设置以及「登录项」里的助手授权全部保留，无需重新配置。代价是它与原版 ClashBar **不能并存**，请先卸载原版再安装。

与上游的差异记录在 [CHANGELOG.md](./CHANGELOG.md)；v0.3.3 及更早的历史见[上游更新日志](https://github.com/Sitoi/ClashBar/blob/main/CHANGELOG.md)。

## ✨ 特点

- 🪶 **轻量**：去掉 Core 约 3 MB 内
- 🧭 **菜单栏优先**：配置导入/更新、节点切换、延迟测试、规则与连接排障
- 🔐 **系统集成**：系统代理、TUN、开机启动
- 📊 **可观测**：实时流量、连接、内存、日志过滤
- 🌍 **中英双语**：简体中文 / English

### 📏 体积对比（macOS Finder 显示值，仅供参考）

| 客户端                     |     体积 |
| -------------------------- | -------: |
| ClashBarPlus.app (No Core) |     3 MB |
| ClashMac.app               |  75.2 MB |
| Clash Verge.app            | 128.4 MB |
| Clash Party.app            | 496.7 MB |

## 📦 安装

**要求：** macOS 13+ 🍎

从 [Releases](https://github.com/Gongsc/ClashBar/releases) 下载 `.dmg`，将 `ClashBarPlus.app` 拖入 `/Applications`。

每个版本提供 4 个产物，按芯片和是否内置 mihomo 内核区分：

| 文件名                                    | 适用                             |
| ----------------------------------------- | -------------------------------- |
| `ClashBarPlus-<版本>-apple-silicon.dmg`         | Apple Silicon，内置内核          |
| `ClashBarPlus-<版本>-apple-silicon-no-core.dmg` | Apple Silicon，自备内核          |
| `ClashBarPlus-<版本>-intel.dmg`                 | Intel，内置内核                  |
| `ClashBarPlus-<版本>-intel-no-core.dmg`         | Intel，自备内核                  |

> 本仓库**不提供 Homebrew 安装**。若你此前用 `brew install --cask clashbar` 装过上游版本，请先 `brew uninstall --cask clashbar` 再安装本版本，否则 Homebrew 的升级会把它覆盖回上游。

> [!IMPORTANT]
>
> - ⚠️ 同一时间只让一个 mihomo / Clash 系客户端接管系统代理。
> - 📂 系统代理依赖打包后的 `.app` 与登录项授权；请放到 `/Applications` 后再使用。
> - 🔑 首次开启系统代理或开机启动时，在 **系统设置 → 通用 → 登录项** 允许 ClashBarPlus。
> - 🔄 开关异常时，先在登录项中关闭再打开后台项目，或在应用内 `Restart` 内核。

## 🚀 快速上手

1. 🖱️ 点击菜单栏图标打开面板
2. 📥 在 Proxy 选择或导入配置
3. ▶️ `Start` / `Restart` 启动内核
4. 🎛️ 选择模式：`Rule` / `Global` / `Direct`
5. 📶 切换节点并测速，确认可用后再开系统代理

## 🗺️ 功能一览

| 页面           | 内容                                            |
| -------------- | ----------------------------------------------- |
| 🧭 Proxy       | 配置、模式、系统代理、节点切换、延迟与 Provider |
| 📚 Rules       | 规则统计、筛选、Provider 更新                   |
| 🌐 Connections | 连接过滤与关闭                                  |
| 🪵 Logs        | 级别过滤、关键词检索                            |
| ⚙️ System      | 语言、状态栏、端口、`allow-lan` / `ipv6` 等     |

📁 运行时数据目录：`~/Library/Application Support/clashbar`
🧩 内置内核会复制到：`~/Library/Application Support/clashbar/core/mihomo`

## 📖 文档

文档源码在 [`docs/`](./docs) 目录，本地预览：

```sh
cd docs && pnpm install && pnpm dev
```

功能说明与上游基本一致，上游也维护了一个在线文档站：<https://clashbar.sitoi.workers.dev>

## 🛠️ 开发构建

```sh
# 依赖：Xcode / Swift 6.2+、macOS 13+
make build                 # 产出 dist/ClashBarPlus.app（默认不含 Core）
make build WITH_CORE=1     # 打包内置 mihomo
make dist WITH_CORE=1      # app + dmg
make format                # swiftformat + swiftlint
```

## 🙏 致谢

- [Sitoi/ClashBar](https://github.com/Sitoi/ClashBar) —— 本项目的上游，全部核心实现来自这里
- [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) —— 提供内核能力

## 📄 许可

沿用上游的许可协议，见 [LICENSE](./LICENSE)。
