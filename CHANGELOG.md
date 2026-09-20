## v1.0.0

![macOS](https://img.shields.io/badge/macOS-Supported-000000?style=flat-square&logo=apple) ![Version](https://img.shields.io/badge/Release-v1.0.0-10B981?style=flat-square) ![Core](https://img.shields.io/badge/Core-Mihomo-6366f1?style=flat-square) ![Upstream](https://img.shields.io/badge/Fork_of-ClashBar_v0.3.3-8B5CF6?style=flat-square)

> ClashBarPlus 的首个版本，从上游 [Sitoi/ClashBar](https://github.com/Sitoi/ClashBar) 的 **v0.3.3** 切出。完整继承 v0.3.3 的全部能力——菜单栏配置与节点管理、系统代理与 TUN、规则与连接排障、SSID 策略、远程实例、中英双语——并在此基础上修复了 TUN 菜单栏图标状态错位后无法自愈的问题。本仓库自此独立编号，不再跟随上游版本序列；v0.3.3 及更早的历史请查阅[上游更新日志](https://github.com/Sitoi/ClashBar/blob/main/CHANGELOG.md)。

### 📝 更新日志 (Changelog)

**✨ 新增功能 (New Features)**

- ![Feature](https://img.shields.io/badge/Feature-10B981?style=flat-square) **独立版本线**：自 v1.0.0 起独立编号。发布流程只识别 `v1.0.0` 及以上的标签，从上游同步过来的 `v0.x` 一律忽略；手动或推送一个低于 v1.0.0 的标签会在推送前被拒绝，不会留下脏标签。

**🚀 优化改进 (Improvements)**

- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **发布流程移除 Homebrew 环节**：删除向上游个人 tap 推送 cask 的 `update-formula` 任务。本仓库不提供 Homebrew 安装，DMG 直接从 Releases 下载。该任务原本硬编码了上游的 tap 仓库和一个 fork 里不存在的 `PAT_TOKEN`，在本仓库必然失败。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **菜单栏状态对账**：打开面板时与显示模型对账一次。此前 `refreshDisplayNow()` 全工程只在构造函数中调用过一次，任何一次漏掉的增量更新都会永久留在菜单栏上。
- ![Optimize](https://img.shields.io/badge/Optimize-3B82F6?style=flat-square) **品牌更名为 ClashBarPlus**：应用名、DMG 产物名、文档站与发布说明统一更名。Bundle ID、数据目录 `~/Library/Application Support/clashbar` 与特权助手标签保持不变，因此覆盖安装是原地升级，既有配置、订阅、设置与登录项授权全部保留。

**🐞 修复问题 (Bug Fixes)**

- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **启动时弹出空白 Settings 窗口**：SwiftUI 的 `Settings` 场景只是菜单命令的宿主，应用自身的设置在弹出面板的 System 标签里，`⌘,` 也已重定向到那里。较新 SDK 构建出的版本会在启动时把这个空窗口显示出来，现在它在出现的瞬间即被关闭，实测全程不可见、无闪烁。
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **菜单栏与面板品牌图标退化为 SF Symbol**：较新的 Swift 工具链会把 `Assets.xcassets` 编译成 `Assets.car` 并改用嵌套的 `Contents/Resources` 布局，包内不再存在散装 PNG。原实现只按相对路径拼接查找，四张品牌图会一起落空——菜单栏退化成 `bolt.horizontal.circle.fill`，面板左上角退化成 `paperplane.fill`。现在优先通过资源目录 API 读取，并保留旧版扁平布局的路径查找作为回退。
- ![Fix](https://img.shields.io/badge/Fix-EF4444?style=flat-square) **TUN 已开启但菜单栏图标停留在普通运行形态**：内核重启（如断网自动停止后恢复）会让 `isTunEnabled` 在 `false → true` 之间往返。若两次变更落进同一个防抖窗口，排队中的陈旧快照会被画到菜单栏并写入 `lastRenderedKey`；而「仅图标」模式下渲染键只由 `{显示模式, 运行中, TUN}` 构成，此后不会再有事件纠正这次错位。现在延迟重绘改为读取当前显示模型而非排队时捕获的快照，防抖降级为纯粹的限流器；同时在渲染键与已渲染值相同而提前返回时，撤销尚未执行的重绘任务。
