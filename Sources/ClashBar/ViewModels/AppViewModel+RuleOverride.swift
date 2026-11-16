import AppKit
import Foundation

/// 交给 mihomo 的实际配置：覆写生效时是 state/runtime/ 下的生成文件，工作目录仍取原配置的。
struct CoreLaunchConfig {
    let path: String
    let workingDirectory: URL?
    let overrideContent: RuleOverrideContent?

    var isOverridden: Bool {
        self.overrideContent?.counts.isEmpty == false
    }
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
        let original = CoreLaunchConfig(path: configPath, workingDirectory: nil, overrideContent: nil)
        guard !self.isRemoteTarget else { return original }
        guard self.ruleOverrideStore.isEnabled else { return original }

        do {
            let service = self.ruleOverrideService
            let content = try service.loadContent()
            self.ruleOverrideStore.counts = content.counts
            guard !content.counts.isEmpty else {
                return CoreLaunchConfig(path: configPath, workingDirectory: nil, overrideContent: content)
            }

            let runtimeURL = try service.writeRuntimeConfig(originalConfigPath: configPath, content: content)
            return CoreLaunchConfig(
                path: runtimeURL.path,
                workingDirectory: MihomoProcessManager.resolveWorkingDirectoryURL(configPath: configPath),
                overrideContent: content)
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
        guard !self.isRemoteTarget else { return }
        self.ruleOverrideStore.lastContent = launch.overrideContent
        guard let counts = launch.overrideContent?.counts else {
            self.ruleOverrideStore.status = nil
            return
        }
        guard !counts.isEmpty else {
            self.ruleOverrideStore.status = .empty
            return
        }
        let configName = URL(fileURLWithPath: launch.path).lastPathComponent
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
        do {
            try await self.submitCoreLaunchConfig(launch, client: self.clientOrThrow())
            self.markRuleOverrideApplied(launch)
        } catch {
            if launch.isOverridden {
                self.markRuleOverrideFailed(error.localizedDescription)
            }
            throw error
        }
    }

    private func submitCoreLaunchConfig(_ launch: CoreLaunchConfig, client: MihomoAPIService) async throws {
        let payload = launch.isOverridden ? try String(contentsOfFile: launch.path, encoding: .utf8) : nil
        self.ruleOverrideStore.applyingContent = launch.overrideContent
        defer { self.ruleOverrideStore.applyingContent = nil }
        try await client.requestNoResponse(.putConfigs(force: false, path: launch.path, payload: payload))
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
    func applyRuleOverridesIfRunning(force: Bool = false, afterWake: Bool = false) async {
        self.refreshRuleOverrideCounts()
        guard !self.isRemoteTarget, self.processManager.isRunning else { return }
        guard force || self.ruleOverrideStore.isEnabled else { return }
        // 启动 / 重启本身会重新生成运行时配置，这时再 PUT 只会和它抢。
        guard !self.isCoreActionProcessing else { return }
        // 重载进行中又保存了一次：记下来，等这一轮结束再补一次，而不是丢掉这次修改。
        guard !self.ruleOverrideStore.isApplying else {
            self.ruleOverrideStore.needsReapply = true
            return
        }

        self.ruleOverrideStore.isApplying = true
        defer { self.ruleOverrideStore.isApplying = false }
        repeat {
            self.ruleOverrideStore.needsReapply = false
            if afterWake, self.ruleOverrideStore.isEnabled {
                await self.reloadRuleOverridesAfterWake()
            } else {
                await self.reloadConfig()
            }
        } while self.ruleOverrideStore.needsReapply && !Task.isCancelled && !self.isRemoteTarget
            && self.processManager.isRunning && !self.isCoreActionProcessing
    }

    func refreshRuleOverrideCounts() {
        do {
            let content = try self.ruleOverrideService.loadContent()
            self.ruleOverrideStore.counts = content.counts
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
        }
    }

    // MARK: - In-panel editor

    func toggleRuleOverrideEditor(_ file: RuleOverrideFile) {
        let store = self.ruleOverrideStore
        guard store.expandedFile != file else {
            store.expandedFile = nil
            return
        }
        if store.drafts[file] == nil {
            do {
                let text = try self.ruleOverrideService.editableText(for: file)
                store.savedTexts[file] = text
                store.drafts[file] = text
            } catch {
                self.markRuleOverrideFailed(error.localizedDescription)
                return
            }
        }
        store.expandedFile = file
    }

    func saveRuleOverrideDraft(_ file: RuleOverrideFile) async {
        let store = self.ruleOverrideStore
        guard let draft = store.drafts[file], store.isDirty(file) else { return }
        do {
            try self.ruleOverrideService.write(draft, to: file)
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
            return
        }
        store.savedTexts[file] = draft
        // 文件监控随后也会触发，但那时内容已与 lastContent 相同，不会重复重载。
        await self.applyRuleOverridesIfRunning()
    }

    func revertRuleOverrideDraft(_ file: RuleOverrideFile) {
        let store = self.ruleOverrideStore
        store.drafts[file] = store.savedTexts[file]
    }

    /// 文件在面板外被改动时，把没有未保存修改的草稿同步成磁盘上的新内容；有修改的草稿保持不动。
    private func syncRuleOverrideDraftsFromDisk() {
        let store = self.ruleOverrideStore
        for file in RuleOverrideFile.allCases where store.drafts[file] != nil {
            guard let text = try? self.ruleOverrideService.editableText(for: file) else { continue }
            let wasDirty = store.isDirty(file)
            store.savedTexts[file] = text
            if !wasDirty {
                store.drafts[file] = text
            }
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
        self.syncRuleOverrideDraftsFromDisk()
        let content: RuleOverrideContent
        do {
            content = try self.ruleOverrideService.loadContent()
        } catch {
            self.markRuleOverrideFailed(error.localizedDescription)
            return
        }
        // 只动了注释、属性或保存了相同内容时不重载。
        guard content != (self.ruleOverrideStore.applyingContent ?? self.ruleOverrideStore.lastContent) else { return }
        await self.applyRuleOverridesIfRunning()
    }

    // MARK: - System wake

    func scheduleRuleOverrideRecoveryAfterWake() {
        let store = self.ruleOverrideStore
        guard !self.isRemoteTarget, store.isEnabled, store.wakeRecoveryTask == nil else { return }
        store.wakeRecoveryTask = Task { [weak self] in
            defer { self?.ruleOverrideStore.wakeRecoveryTask = nil }
            for _ in 0..<60 {
                guard (try? await Task.sleep(for: .milliseconds(500))) != nil, let self else { return }
                guard !self.isRemoteTarget, self.ruleOverrideStore.isEnabled else { return }
                if self.isCoreActionProcessing || self.shouldResumeCoreAfterNetworkRecovery { continue }
                guard self.processManager.isRunning else { return }
                if self.ruleOverrideStore.isApplying || self.isTunSyncing || self.settingsSyncingKey != nil
                    || self.networkReachabilityStatus == .offline
                {
                    continue
                }
                await self.applyRuleOverridesIfRunning(afterWake: true)
                return
            }
        }
    }

    private func reloadRuleOverridesAfterWake() async {
        guard self.ruleOverrideStore.lastContent?.counts.isEmpty == false
            || !self.ruleOverrideStore.counts.isEmpty else { return }
        guard let configPath = await self.resolveSelectedConfigPath(),
              !self.isRemoteTarget, self.processManager.isRunning, !self.isCoreActionProcessing
        else { return }

        let coreStatus = self.processManager.status
        let client = MihomoAPIService(controller: self.controller, secret: self.controllerSecret)
        var settingsPatch: [String: JSONValue]?
        var shouldRestoreSettings = false

        func isSameLocalCore() -> Bool {
            !Task.isCancelled && !self.isRemoteTarget && !self.isCoreActionProcessing
                && self.processManager.isRunning && self.processManager.status == coreStatus
                && self.configService.selectedConfig?.path == configPath
        }

        for attempt in 1...3 {
            guard isSameLocalCore(), self.ruleOverrideStore.isEnabled else { break }
            do {
                if settingsPatch == nil {
                    let config: ConfigSnapshot = try await client.request(.getConfigs)
                    guard let body = await self.editableSettingsOverlayBody(
                        EditableSettingsSnapshot(config: config),
                        tunStack: config.tun?.stack)
                    else { return }
                    settingsPatch = body.mapValues(\.jsonValue)
                }
                guard isSameLocalCore(), self.ruleOverrideStore.isEnabled else { break }
                let launch = try self.prepareCoreLaunchConfig(configPath: configPath)
                do {
                    try await self.submitCoreLaunchConfig(launch, client: client)
                    shouldRestoreSettings = true
                } catch {
                    // A lost response can mean the core already accepted the reload.
                    shouldRestoreSettings = shouldRestoreSettings || MihomoAPIService.shouldRetry(error: error)
                    throw error
                }
                guard isSameLocalCore() else { return }
                self.markRuleOverrideApplied(launch)
                break
            } catch {
                guard isSameLocalCore() else { return }
                guard attempt < 3, MihomoAPIService.shouldRetry(error: error) else {
                    self.markRuleOverrideFailed(error.localizedDescription)
                    break
                }
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            }
        }

        guard shouldRestoreSettings, let settingsPatch else { return }
        for attempt in 1...3 {
            guard isSameLocalCore() else { return }
            do {
                try await client.requestNoResponse(.patchConfigs(body: settingsPatch))
                return
            } catch {
                guard isSameLocalCore() else { return }
                guard attempt < 3, MihomoAPIService.shouldRetry(error: error) else {
                    self.appendLog(
                        level: "error",
                        message: self.tr("log.action.failed", self.tr("log.action_name.reload_config"), error.localizedDescription))
                    return
                }
                guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            }
        }
    }
}
