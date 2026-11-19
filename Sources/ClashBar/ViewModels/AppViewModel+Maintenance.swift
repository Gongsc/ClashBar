import Foundation

@MainActor
extension AppViewModel {
    func upgradeCore() async {
        guard !self.isCoreUpgradeInFlight else { return }

        self.coreUpgradeFeedbackClearTask?.cancel()
        self.coreUpgradeFeedbackClearTask = nil
        self.coreUpgradeState = .running
        let settingsOverlay = self.currentEditableSettingsSnapshot()
        let previousVersion = self.version.trimmed
        let preservedTunStack = self.isRemoteTarget ? self.tunStack : nil

        do {
            self.preserveLocalSettingsOnNextSync = true
            let response: CoreUpgradeResponse = try await self.clientOrThrow().request(.upgradeCore)
            let nextState = self.coreUpgradeState(from: response)
            if case .succeeded = nextState {
                self.applyCoreUpgradeState(
                    nextState,
                    settingsOverlay: settingsOverlay,
                    previousVersion: previousVersion,
                    tunStack: preservedTunStack)
            } else {
                self.preserveLocalSettingsOnNextSync = false
                self.applyCoreUpgradeState(nextState)
            }
        } catch {
            self.preserveLocalSettingsOnNextSync = false
            self.applyCoreUpgradeState(self.coreUpgradeState(from: error))
        }
    }

    func upgradeGeo() async {
        guard !self.isGeoUpdateInFlight else { return }

        self.geoUpdateFeedbackClearTask?.cancel()
        self.geoUpdateFeedbackClearTask = nil
        self.geoUpdateState = .updating
        let settingsOverlay = self.currentEditableSettingsSnapshot()
        let preservedTunStack = self.isRemoteTarget ? self.tunStack : nil

        do {
            self.preserveLocalSettingsOnNextSync = true
            try await self.clientOrThrow().requestNoResponse(.upgradeGeo)
            await self.restoreSettingsOverlayAfterMaintenance(
                settingsOverlay,
                syncingKey: "geo-upgrade-overlay",
                tunStack: preservedTunStack)
            self.applyGeoUpdateState(.succeeded)
        } catch {
            self.preserveLocalSettingsOnNextSync = false
            self.applyGeoUpdateState(.failed(message: self.geoUpdateFailureMessage(from: error)))
        }
    }

    func flushFakeIPCache() async {
        await runNoResponseAction(tr("log.action_name.flush_fakeip_cache")) {
            try await self.clientOrThrow().requestNoResponse(.flushFakeIPCache)
        }
    }

    func flushDNSCache() async {
        await runNoResponseAction(tr("log.action_name.flush_dns_cache")) {
            try await self.clientOrThrow().requestNoResponse(.flushDNSCache)
        }
    }

    var isCoreUpgradeInFlight: Bool {
        if case .running = self.coreUpgradeState {
            return true
        }
        return false
    }

    var isGeoUpdateInFlight: Bool {
        if case .updating = self.geoUpdateState {
            return true
        }
        return false
    }

    private func applyCoreUpgradeState(
        _ state: CoreUpgradeState,
        settingsOverlay: EditableSettingsSnapshot? = nil,
        previousVersion: String? = nil,
        tunStack: String? = nil)
    {
        self.coreUpgradeState = state

        switch state {
        case .idle, .running:
            return
        case .succeeded:
            self.appendLog(level: "info", message: tr("log.core_upgrade.updated"))
            Task { [weak self] in
                await self?.restoreCoreStateAfterUpgradeIfPossible(
                    settingsOverlay: settingsOverlay,
                    previousVersion: previousVersion,
                    tunStack: tunStack)
            }
        case let .alreadyLatest(version):
            if let version, !version.isEmpty {
                self.version = AppSemanticVersion.normalizedDisplayVersion(from: version)
                self.appendLog(level: "info", message: tr("log.core_upgrade.latest_version", self.version))
            } else {
                self.appendLog(level: "info", message: tr("log.core_upgrade.latest"))
            }
        case let .failed(message):
            self.appendLog(level: "error", message: tr("log.core_upgrade.failed", message))
        }

        self.scheduleCoreUpgradeFeedbackAutoClear()
    }

    private func applyGeoUpdateState(_ state: GeoUpdateState) {
        self.geoUpdateState = state

        switch state {
        case .idle, .updating:
            return
        case .succeeded:
            self.appendLog(level: "info", message: tr("log.geo_update.updated"))
        case let .failed(message):
            self.appendLog(level: "error", message: tr("log.geo_update.failed", message))
        }

        self.scheduleGeoUpdateFeedbackAutoClear()
    }

    private func scheduleCoreUpgradeFeedbackAutoClear() {
        self.coreUpgradeFeedbackClearTask?.cancel()
        self.coreUpgradeFeedbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }

            guard let self else { return }
            guard !self.isCoreUpgradeInFlight else { return }
            self.coreUpgradeState = .idle
        }
    }

    private func scheduleGeoUpdateFeedbackAutoClear() {
        self.geoUpdateFeedbackClearTask?.cancel()
        self.geoUpdateFeedbackClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }

            guard let self else { return }
            guard !self.isGeoUpdateInFlight else { return }
            self.geoUpdateState = .idle
        }
    }

    private func restoreCoreStateAfterUpgradeIfPossible(
        settingsOverlay: EditableSettingsSnapshot?,
        previousVersion: String?,
        tunStack: String?) async
    {
        let normalizedPreviousVersion = previousVersion?.trimmedNonEmpty
        var sawRestart = false

        do {
            try await Task.sleep(nanoseconds: 750_000_000)
        } catch {
            self.preserveLocalSettingsOnNextSync = false
            return
        }

        for attempt in 0..<20 {
            guard !Task.isCancelled else {
                self.preserveLocalSettingsOnNextSync = false
                return
            }

            do {
                let versionInfo: VersionInfo = try await self.clientOrThrow().request(.version)
                guard !Task.isCancelled else {
                    self.preserveLocalSettingsOnNextSync = false
                    return
                }
                let fetchedVersion = versionInfo.version.trimmed
                self.version = versionInfo.version

                let versionChanged = normalizedPreviousVersion != nil && fetchedVersion != normalizedPreviousVersion
                if versionChanged || sawRestart || attempt >= 3 {
                    break
                }
            } catch {
                sawRestart = true
            }

            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                self.preserveLocalSettingsOnNextSync = false
                return
            }
        }

        guard !Task.isCancelled else {
            self.preserveLocalSettingsOnNextSync = false
            return
        }

        if let settingsOverlay {
            self.preserveLocalSettingsOnNextSync = true
            await self.restoreSettingsOverlayAfterMaintenance(
                settingsOverlay,
                syncingKey: "core-upgrade-overlay",
                tunStack: tunStack,
                deferIfUnreachable: true)
        } else {
            self.preserveLocalSettingsOnNextSync = false
        }

        await self.refreshProxyGroups()
    }

    private func restoreSettingsOverlayAfterMaintenance(
        _ overlay: EditableSettingsSnapshot,
        syncingKey: String,
        tunStack: String?,
        deferIfUnreachable: Bool = false) async
    {
        guard self.isRemoteTarget || self.isRuntimeRunning else {
            self.preserveLocalSettingsOnNextSync = false
            return
        }

        if let tunStack {
            guard let body = await self.editableSettingsOverlayBody(overlay, tunStack: tunStack) else {
                self.preserveLocalSettingsOnNextSync = false
                return
            }
            _ = await self.patchConfigBody(
                body,
                syncingKey: syncingKey,
                successMessage: "",
                syncSystemProxyPort: !self.isRemoteTarget)
            return
        }

        if deferIfUnreachable {
            await self.syncEditableSettingsOverlayForCoreBootstrap(overlay, syncingKey: syncingKey)
        } else {
            _ = await self.applyEditableSettingsOverlay(
                overlay,
                syncingKey: syncingKey,
                successMessage: "")
        }
    }

    private func coreUpgradeState(from response: CoreUpgradeResponse) -> CoreUpgradeState {
        if let status = response.status?.trimmedNonEmpty,
           status.caseInsensitiveCompare("ok") == .orderedSame
        {
            return .succeeded
        }

        if let message = response.message?.trimmedNonEmpty {
            return self.coreUpgradeState(fromMessage: message)
        }

        return .failed(message: tr("ui.common.unknown"))
    }

    private func coreUpgradeState(from error: Error) -> CoreUpgradeState {
        if let apiError = error as? APIError,
           case let .statusCode(_, responseBody) = apiError
        {
            if let data = responseBody.data(using: .utf8),
               let response = try? JSONDecoder().decode(CoreUpgradeResponse.self, from: data)
            {
                let state = self.coreUpgradeState(from: response)
                if case let .failed(message) = state, message == tr("ui.common.unknown") {
                    return self.coreUpgradeState(fromMessage: responseBody)
                }
                return state
            }

            return self.coreUpgradeState(fromMessage: responseBody)
        }

        return self.coreUpgradeState(fromMessage: error.localizedDescription)
    }

    private func geoUpdateFailureMessage(from error: Error) -> String {
        let raw: String = if let apiError = error as? APIError,
                             case let .statusCode(_, responseBody) = apiError
        {
            responseBody
        } else {
            error.localizedDescription
        }

        let trimmed = raw.trimmed
        return trimmed.isEmpty ? tr("ui.common.unknown") : trimmed
    }

    private func coreUpgradeState(fromMessage message: String) -> CoreUpgradeState {
        let trimmedMessage = message.trimmed
        guard !trimmedMessage.isEmpty else {
            return .failed(message: tr("ui.common.unknown"))
        }

        if self.isAlreadyLatestCoreUpgradeMessage(trimmedMessage) {
            return .alreadyLatest(version: self.latestVersion(in: trimmedMessage))
        }

        return .failed(message: trimmedMessage)
    }

    private func isAlreadyLatestCoreUpgradeMessage(_ message: String) -> Bool {
        message.range(
            of: "already using latest version",
            options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func latestVersion(in message: String) -> String? {
        let pattern = #"v?\d+(?:\.\d+)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.matches(in: message, range: range).last,
              let swiftRange = Range(match.range, in: message)
        else {
            return nil
        }

        let raw = String(message[swiftRange])
        return AppSemanticVersion.normalizedDisplayVersion(from: raw)
    }
}

extension AppViewModel {
    var currentAppVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty {
            return short
        }
        if let build, !build.isEmpty {
            return build
        }
        return "0.0.1"
    }

    var availableAppUpdate: AppReleaseInfo? {
        guard let latestAppReleaseInfo else { return nil }
        guard !latestAppReleaseInfo.isDraft, !latestAppReleaseInfo.isPrerelease else { return nil }
        guard AppSemanticVersion.isNewerRelease(
            tagName: latestAppReleaseInfo.tagName,
            than: self.currentAppVersionText)
        else {
            return nil
        }
        return latestAppReleaseInfo
    }

    var appReleaseIndexURL: URL? {
        URL(string: "https://github.com/Sitoi/ClashBar/releases")
    }

    func refreshLatestAppRelease() async {
        guard !self.isLatestAppReleaseCheckInFlight else { return }

        self.isLatestAppReleaseCheckInFlight = true
        defer {
            self.isLatestAppReleaseCheckInFlight = false
        }

        do {
            let release = try await AppReleaseService.fetchLatestRelease(currentVersion: self.currentAppVersionText)
            guard !Task.isCancelled else { return }
            guard self.latestAppReleaseInfo != release else { return }
            self.latestAppReleaseInfo = release
        } catch {
            guard !Task.isCancelled else { return }
        }
    }
}
