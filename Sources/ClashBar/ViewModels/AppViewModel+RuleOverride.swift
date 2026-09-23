import AppKit
import Foundation

/// 交给 mihomo 的实际配置：覆写生效时是 state/runtime/ 下的生成文件，工作目录仍取原配置的。
struct CoreLaunchConfig {
    let path: String
    let workingDirectory: URL?
    let isOverridden: Bool
}

@MainActor
extension AppViewModel {
    var ruleOverrideService: RuleOverrideService {
        RuleOverrideService(workingDirectoryManager: self.workingDirectoryManager)
    }

    // MARK: - Launch / reload integration

    /// 覆写开启且有内容时生成运行时配置，否则原样返回。生成失败会抛出，调用方按启动失败处理——
    /// 不悄悄退回原配置，免得用户以为规则已经生效。
    func prepareCoreLaunchConfig(configPath: String) throws -> CoreLaunchConfig {
        let original = CoreLaunchConfig(path: configPath, workingDirectory: nil, isOverridden: false)
        guard !self.isRemoteTarget else { return original }
        guard self.ruleOverrideStore.isEnabled else {
            self.ruleOverrideStore.status = nil
            return original
        }

        do {
            let service = self.ruleOverrideService
            let content = try service.loadContent()
            self.ruleOverrideStore.counts = content.counts
            self.ruleOverrideStore.lastContent = content
            guard !content.counts.isEmpty else {
                self.ruleOverrideStore.status = .empty
                return original
            }

            let runtimeURL = try service.writeRuntimeConfig(originalConfigPath: configPath, content: content)
            return CoreLaunchConfig(
                path: runtimeURL.path,
                workingDirectory: MihomoProcessManager.resolveWorkingDirectoryURL(configPath: configPath),
                isOverridden: true)
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
            throw error
        }
    }

    func validateCoreLaunchConfig(_ launch: CoreLaunchConfig) async -> Bool {
        guard let details = await self.configValidationFailureDetails(
            configPath: launch.path,
            workingDirectory: launch.workingDirectory)
        else {
            return true
        }

        if launch.isOverridden {
            self.markRuleOverrideFailed(details)
        }
        self.handleConfigValidationFailure(configPath: launch.path, details: details)
        return false
    }

    func markRuleOverrideApplied(_ launch: CoreLaunchConfig) {
        guard launch.isOverridden else { return }
        let configName = URL(fileURLWithPath: launch.path).lastPathComponent
        let counts = self.ruleOverrideStore.counts
        self.ruleOverrideStore.status = .applied(configName: configName, at: Date())
        let message = self.tr(
            "log.rule_override.applied",
            configName,
            counts.prepend,
            counts.append,
            counts.ruleProviders)
        self.appendLog(level: "info", message: message)
    }

    /// `PUT /configs` 重载所选配置。覆写生效时推送生成后的内容而不是路径：
    /// 配置目录可以由用户自选，那时 state/runtime/ 不在 mihomo 的 -d 之下，按路径加载会被拒绝。
    func putSelectedConfig(configPath: String) async throws {
        let launch = try self.prepareCoreLaunchConfig(configPath: configPath)
        guard launch.isOverridden else {
            try await self.clientOrThrow().requestNoResponse(.putConfigs(force: false, path: configPath, payload: nil))
            return
        }

        do {
            let payload = try String(contentsOfFile: launch.path, encoding: .utf8)
            try await self.clientOrThrow().requestNoResponse(
                .putConfigs(force: false, path: launch.path, payload: payload))
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
            throw error
        }
        self.markRuleOverrideApplied(launch)
    }

    private func markRuleOverrideFailed(_ message: String) {
        self.ruleOverrideStore.status = .failed(message: message, at: Date())
        self.appendLog(level: "error", message: self.tr("log.rule_override.failed", message))
    }

    // MARK: - User actions

    func setRuleOverrideEnabled(_ enabled: Bool) async {
        guard self.ruleOverrideStore.isEnabled != enabled else { return }
        self.ruleOverrideStore.isEnabled = enabled
        await self.applyRuleOverridesIfRunning(force: true)
    }

    /// 核心在本机运行时重载配置让覆写生效；没运行时只刷新条数，下次启动再生成。
    func applyRuleOverridesIfRunning(force: Bool = false) async {
        self.refreshRuleOverrideCounts()
        guard !self.isRemoteTarget, self.processManager.isRunning else { return }
        guard force || self.ruleOverrideStore.isEnabled else { return }
        // 启动 / 重启本身会重新生成运行时配置，这时再 PUT 只会和它抢。
        guard !self.ruleOverrideStore.isApplying, !self.isCoreActionProcessing else { return }

        self.ruleOverrideStore.isApplying = true
        defer { self.ruleOverrideStore.isApplying = false }
        await self.reloadConfig()
    }

    func refreshRuleOverrideCounts() {
        do {
            let content = try self.ruleOverrideService.loadContent()
            self.ruleOverrideStore.counts = content.counts
            self.ruleOverrideStore.lastContent = content
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
        }
    }

    func openRuleOverrideFile(_ file: RuleOverrideFile) {
        do {
            let url = try self.ruleOverrideService.ensureTemplate(for: file)
            // .list 往往没有关联程序，此时退回文本编辑。
            if NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) {
                return
            }
            guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
            else {
                throw CocoaError(.fileReadNoPermission)
            }
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            self.appendLog(
                level: "error",
                message: self.tr("log.rule_override.open_failed", file.fileName, error.localizedDescription))
        }
    }

    func showRuleOverrideDirectoryInFinder() {
        let service = self.ruleOverrideService
        do {
            try service.ensureOverridesDirectory()
            if !NSWorkspace.shared.open(service.overridesDirectoryURL) {
                throw CocoaError(.fileNoSuchFile)
            }
        } catch {
            let path = service.overridesDirectoryURL.path
            self.appendLog(
                level: "error",
                message: self.tr("log.rule_override.open_failed", path, error.localizedDescription))
        }
    }

    // MARK: - File monitoring

    func startRuleOverrideMonitoringIfNeeded() {
        guard self.ruleOverrideStore.monitor == nil else { return }
        let service = self.ruleOverrideService
        do {
            try service.ensureOverridesDirectory()
        } catch {
            self.appendLog(level: "error", message: self.tr("log.rule_override.failed", error.localizedDescription))
            return
        }

        self.refreshRuleOverrideCounts()
        self.ruleOverrideStore.monitor = RuleOverrideDirectoryMonitor(
            directoryURL: service.overridesDirectoryURL,
            fileURLs: RuleOverrideFile.allCases.map(service.url(for:)))
        { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRuleOverrideRefresh()
            }
        }
    }

    private func scheduleRuleOverrideRefresh() {
        self.ruleOverrideStore.debounceTask?.cancel()
        self.ruleOverrideStore.debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            await self?.handleRuleOverrideFilesChanged()
        }
    }

    private func handleRuleOverrideFilesChanged() async {
        let content: RuleOverrideContent
        do {
            content = try self.ruleOverrideService.loadContent()
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
            return
        }
        // 只动了注释、属性或保存了相同内容时不重载。
        guard content != self.ruleOverrideStore.lastContent else { return }
        await self.applyRuleOverridesIfRunning()
    }
}
