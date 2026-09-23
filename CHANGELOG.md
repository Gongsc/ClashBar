## v1.0.0

![macOS](https://img.shields.io/badge/macOS-Supported-000000?style=flat-square&logo=apple) ![Version](https://img.shields.io/badge/Release-v1.0.0-10B981?style=flat-square) ![Core](https://img.shields.io/badge/Core-Mihomo-6366f1?style=flat-square) ![Upstream](https://img.shields.io/badge/Fork_of-ClashBar_v0.3.3-8B5CF6?style=flat-square)

> ClashBarPlus 的首个版本，从上游 [Sitoi/ClashBar](https://github.com/Sitoi/ClashBar) 的 **v0.3.3** 切出，完整继承其全部能力，并修复了三个上游同样存在的问题。Bundle ID 与数据目录与上游保持一致，覆盖安装即原地升级。v0.3.3 及更早的历史见[上游更新日志](https://github.com/Sitoi/ClashBar/blob/main/CHANGELOG.md)。

### 📝 更新日志 (Changelog)

**✨ 新增功能 (New Features)**

- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **独立版本线**：自 v1.0.0 起独立编号，发布流程忽略从上游同步来的 `v0.x` 标签。
- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **流量曲线展示时长**：可选 1 / 5 / 15 / 30 分钟，默认 5 分钟，横轴按真实时间排布。
- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **保持流量曲线**：新增开关，位于「流量曲线时长」下方，默认关闭；开启后「仅图标」模式下曲线也不再断档，代价是应用不再完全空闲。

**🚀 优化改进 (Improvements)**

- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **品牌更名为 ClashBarPlus**：应用名、DMG 产物、文档站与界面文案统一更名；Bundle ID、数据目录与特权助手标签保持不变，既有配置与授权全部保留。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **流量曲线跨面板开合保留**：不再一关面板就清空；采样仅存于内存、不做持久化，未采集的时段以曲线断开如实呈现。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **延迟信号条按实测结果显示**：柱高由每次延迟决定（越慢越高，与旁边的毫秒数同向），颜色细分为 4 档，历史由最近 4 次扩展为 5 次。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **菜单栏状态对账**：打开面板时与显示模型对账一次，避免漏掉的增量更新永久留在菜单栏上。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **发布流程移除 Homebrew 环节**：不再向上游 tap 推送 cask，仅通过 GitHub Releases 分发 DMG。

**🐞 修复问题 (Bug Fixes)**

- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **TUN 已开启但菜单栏图标不变**：内核重启会让 TUN 状态短暂往返，防抖窗口内的抖动会把过期图标画上去且此后无法自愈。
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **品牌图标退化为 SF Symbol**：较新工具链把 `Assets.xcassets` 编译成 `Assets.car`，原先按相对路径查找散装 PNG 的方式全部落空。
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **启动时弹出空白 Settings 窗口**：SwiftUI 的 `Settings` 场景只是菜单命令的宿主，现已在窗口出现的瞬间关闭。
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **界面残留 ClashBar 字样**：面板标题与两份本地化统一更名，此前系统代理提示会指向并不存在的 `ClashBar.app`。
