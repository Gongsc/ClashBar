import Foundation
import ProxyHelperShared
import Security

enum SystemProxyHelperFailureReason: String, Equatable, Sendable {
    case helperNotRegistered
    case helperStartTimedOut
    case helperConnectionFailed
    case helperOperationFailed
    case appNotInApplications
    case helperNotBundled
    case helperAuthorizationCancelled
    case helperInstallFailed
    case unknown
}

struct SystemProxyHelperHealthSnapshot: Equatable, Sendable {
    let helperInstalled: Bool
    let helperReachable: Bool
    let failureReason: SystemProxyHelperFailureReason?
    let rawMessage: String?
}

enum SystemProxyServiceError: LocalizedError {
    case invalidHost
    case invalidPort
    case helperNotBundled
    case helperRequiresInstallToApplications
    case helperNotRegistered
    case helperStartTimedOut
    case helperAuthorizationCancelled
    case helperInstallFailed(String)
    case helperConnectionFailed(String)
    case helperOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "Invalid proxy host."
        case .invalidPort:
            "Invalid proxy port."
        case .helperNotBundled:
            "Privileged helper not found in app bundle. Please rebuild and run the packaged app."
        case .helperRequiresInstallToApplications:
            "Privileged helper can only be installed from /Applications. " +
                "Move ClashBar.app to /Applications and reopen it."
        case .helperNotRegistered:
            "Privileged helper is not installed."
        case .helperStartTimedOut:
            "Privileged helper did not respond. Turn on system proxy again to retry."
        case .helperAuthorizationCancelled:
            "Administrator authorization was cancelled."
        case let .helperInstallFailed(message):
            "Failed to install privileged helper: \(message)"
        case let .helperConnectionFailed(message):
            "Failed to connect privileged helper: \(message)"
        case let .helperOperationFailed(message):
            "Privileged helper operation failed: \(message)"
        }
    }
}

private final class ContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, Error>) {
        self.lock.lock()
        guard let continuation else {
            self.lock.unlock()
            return
        }
        self.continuation = nil
        self.lock.unlock()

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

actor SystemProxyService {
    private let helperResponseTimeoutNanoseconds: UInt64 = 4_000_000_000
    private let helperLaunchRetryDelayNanoseconds: UInt64 = 250_000_000
    private var helperPreparation: Task<Void, Error>?

    func apply(enabled: Bool, host: String, ports: SystemProxyPorts) async throws {
        try self.validateHost(host)

        if enabled {
            let resolvedPorts = try self.validateAndResolvePorts(ports, requiresEnabledPort: true)
            try await self.prepareHelperForMutation()
            try await self.invokeMutation { helper, completion in
                helper.setSystemProxy(
                    host: host,
                    httpPort: resolvedPorts.httpPort,
                    httpsPort: resolvedPorts.httpsPort,
                    socksPort: resolvedPorts.socksPort,
                    completion: completion)
            }
        } else {
            try await self.prepareHelperForMutation()
            try await self.invokeMutation { helper, completion in
                helper.clearSystemProxy(completion: completion)
            }
        }
    }

    func isEnabled() async throws -> Bool {
        try self.requireInstalledHelper()
        return try await self.invokeStateQuery()
    }

    func readActiveDisplay() async throws -> String? {
        try self.requireInstalledHelper()
        guard let target = try await self.invokeActiveTargetQuery() else {
            return nil
        }
        return self.formatProxyDisplay(host: target.host, port: target.port)
    }

    func readExceptionsList() async throws -> [String] {
        try self.requireInstalledHelper()
        return try await self.invokeExceptionsQuery()
    }

    func setExceptionsList(_ exceptions: [String]) async throws {
        try await self.prepareHelperForMutation()
        let serialized = self.serializeExceptions(exceptions)
        try await self.invokeMutation { helper, completion in
            helper.setSystemProxyExceptions(serializedExceptions: serialized, completion: completion)
        }
    }

    func readHelperHealthSnapshot() async -> SystemProxyHelperHealthSnapshot {
        guard ProxyHelperInstaller.installedHelperIsCurrent() else {
            var error: Error = SystemProxyServiceError.helperNotRegistered
            do {
                try self.validateHelperEnvironment()
            } catch let environmentError {
                error = environmentError
            }
            return self.healthSnapshot(helperInstalled: false, helperReachable: false, error: error)
        }

        do {
            try await self.invokeHelperPing()
            return self.healthSnapshot(helperInstalled: true, helperReachable: true, error: nil)
        } catch {
            return self.healthSnapshot(helperInstalled: true, helperReachable: false, error: error)
        }
    }

    func isConfigured(host: String, ports: SystemProxyPorts) async throws -> Bool {
        try self.validateHost(host)
        let resolvedPorts = try self.validateAndResolvePorts(ports, requiresEnabledPort: true)
        try self.requireInstalledHelper()
        return try await self.invokeBooleanQuery { helper, completion in
            helper.isSystemProxyConfigured(
                host: host,
                httpPort: resolvedPorts.httpPort,
                httpsPort: resolvedPorts.httpsPort,
                socksPort: resolvedPorts.socksPort,
                completion: completion)
        }
    }

    private func validateHost(_ host: String) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw SystemProxyServiceError.invalidHost
        }
    }

    private func validateAndResolvePorts(
        _ ports: SystemProxyPorts,
        requiresEnabledPort: Bool) throws -> (httpPort: Int, httpsPort: Int, socksPort: Int)
    {
        let httpPort = try self.normalizePort(ports.httpPort)
        let httpsPort = try self.normalizePort(ports.httpsPort)
        let socksPort = try self.normalizePort(ports.socksPort)

        if requiresEnabledPort, httpPort == 0, httpsPort == 0, socksPort == 0 {
            throw SystemProxyServiceError.invalidPort
        }

        return (httpPort: httpPort, httpsPort: httpsPort, socksPort: socksPort)
    }

    private func normalizePort(_ value: Int?) throws -> Int {
        guard let value else { return 0 }
        guard (1...65535).contains(value) else {
            throw SystemProxyServiceError.invalidPort
        }
        return value
    }

    private func validateHelperEnvironment() throws {
        guard self.isHelperBundledInMainApp() else {
            throw SystemProxyServiceError.helperNotBundled
        }
        guard self.isRunningFromApplicationsDirectory() else {
            throw SystemProxyServiceError.helperRequiresInstallToApplications
        }
        try self.validateHelperSigningRequirements()
    }

    private func requireInstalledHelper() throws {
        guard ProxyHelperInstaller.installedHelperIsCurrent() else {
            throw SystemProxyServiceError.helperNotRegistered
        }
    }

    private func prepareHelperForMutation() async throws {
        if let helperPreparation = self.helperPreparation {
            return try await helperPreparation.value
        }

        let preparation = Task {
            if ProxyHelperInstaller.installedHelperIsCurrent() {
                do {
                    try await self.invokeHelperPing()
                    return
                } catch {
                    guard self.isHelperConnectionFailure(error) else { throw error }
                }
            }

            try self.validateHelperEnvironment()
            try await ProxyHelperInstaller.installBundledHelper()
            guard ProxyHelperInstaller.installedHelperIsCurrent() else {
                throw SystemProxyServiceError.helperInstallFailed("Helper version was not recorded.")
            }
            try await self.invokeHelperPing()
        }
        self.helperPreparation = preparation
        defer { self.helperPreparation = nil }
        try await preparation.value
    }

    private func healthSnapshot(
        helperInstalled: Bool,
        helperReachable: Bool,
        error: Error?) -> SystemProxyHelperHealthSnapshot
    {
        SystemProxyHelperHealthSnapshot(
            helperInstalled: helperInstalled,
            helperReachable: helperReachable,
            failureReason: error.map { self.helperFailureReason(for: $0) },
            rawMessage: error.map { self.helperFailureMessage($0) })
    }

    private func helperFailureReason(for error: Error) -> SystemProxyHelperFailureReason {
        guard let serviceError = error as? SystemProxyServiceError else {
            return .unknown
        }

        switch serviceError {
        case .helperNotBundled:
            return .helperNotBundled
        case .helperRequiresInstallToApplications:
            return .appNotInApplications
        case .helperNotRegistered:
            return .helperNotRegistered
        case .helperStartTimedOut:
            return .helperStartTimedOut
        case .helperAuthorizationCancelled:
            return .helperAuthorizationCancelled
        case .helperInstallFailed:
            return .helperInstallFailed
        case .helperConnectionFailed:
            return .helperConnectionFailed
        case .helperOperationFailed:
            return .helperOperationFailed
        case .invalidHost, .invalidPort:
            return .unknown
        }
    }

    private func isHelperBundledInMainApp() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        return [ProxyHelperConstants.helperBundlePlist, ProxyHelperConstants.helperBundleProgram].allSatisfy {
            FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent($0).path)
        }
    }

    private func isRunningFromApplicationsDirectory() -> Bool {
        let bundlePath = Bundle.main.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return bundlePath.hasPrefix("/Applications/") && bundlePath.hasSuffix(".app")
    }

    private func invokeHelperPing() async throws {
        try await self.invokeHelper { helper, completion in
            helper.ping { success, message in
                completion(Self.mapHelperResult(success: success, message: message, value: ()))
            }
        }
    }

    private static func mapHelperResult<Value>(
        success: Bool,
        message: String?,
        value: @autoclosure () -> Value) -> Result<Value, Error>
    {
        if success {
            return .success(value())
        }
        return .failure(SystemProxyServiceError.helperOperationFailed(message ?? "Unknown helper error."))
    }

    private func invokeStateQuery() async throws -> Bool {
        try await self.invokeBooleanQuery { helper, completion in
            helper.getSystemProxyState(completion: completion)
        }
    }

    private func invokeMutation(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, String?) -> Void) -> Void) async throws
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, message in
                completion(Self.mapHelperResult(success: success, message: message, value: ()))
            }
        }
    }

    private func invokeBooleanQuery(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Bool, Bool, String?) -> Void) -> Void) async throws
        -> Bool
    {
        try await self.invokeHelper { helper, completion in
            invoke(helper) { success, boolValue, message in
                completion(Self.mapHelperResult(success: success, message: message, value: boolValue))
            }
        }
    }

    private func invokeActiveTargetQuery() async throws -> (host: String, port: Int)? {
        try await self.invokeHelper { helper, completion in
            helper.getSystemProxyActiveTarget { success, host, port, message in
                let target: (host: String, port: Int)? = if let host,
                                                            !host.trimmingCharacters(in: .whitespacesAndNewlines)
                                                                .isEmpty, port > 0
                {
                    (host: host, port: port)
                } else {
                    nil
                }
                completion(Self.mapHelperResult(success: success, message: message, value: target))
            }
        }
    }

    private func invokeExceptionsQuery() async throws -> [String] {
        try await self.invokeHelper { helper, completion in
            helper.getSystemProxyExceptions { success, serialized, message in
                completion(Self.mapHelperResult(
                    success: success,
                    message: message,
                    value: self.deserializeExceptions(serialized)))
            }
        }
    }

    private func formatProxyDisplay(host: String, port: Int) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.contains(":"), !trimmedHost.hasPrefix("[") {
            return "[\(trimmedHost)]:\(port)"
        }
        return "\(trimmedHost):\(port)"
    }

    private func serializeExceptions(_ exceptions: [String]) -> String {
        exceptions.joined(separator: "\n")
    }

    private func deserializeExceptions(_ serialized: String?) -> [String] {
        guard let serialized else { return [] }

        var result: [String] = []
        var seen: Set<String> = []

        for value in serialized.components(separatedBy: .newlines) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    private func helperFailureMessage(_ error: Error) -> String {
        if let serviceError = error as? SystemProxyServiceError {
            return serviceError.localizedDescription
        }
        return error.localizedDescription
    }

    private func isHelperConnectionFailure(_ error: Error) -> Bool {
        switch error as? SystemProxyServiceError {
        case .helperConnectionFailed, .helperStartTimedOut: true
        default: false
        }
    }

    private func invokeHelper<Value: Sendable>(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws
        -> Value
    {
        do {
            return try await self.invokeHelperOnce(invoke)
        } catch {
            guard self.isHelperConnectionFailure(error) else { throw error }
            try await Task.sleep(nanoseconds: self.helperLaunchRetryDelayNanoseconds)
            return try await self.invokeHelperOnce(invoke)
        }
    }

    private func invokeHelperOnce<Value: Sendable>(
        _ invoke: @escaping (ProxyHelperProtocol, @escaping (Result<Value, Error>) -> Void) -> Void) async throws
        -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            let connection = self.makeConnection()
            let box = ContinuationBox<Value>(continuation)
            let timeoutWorkItem = DispatchWorkItem {
                box.resume(with: .failure(SystemProxyServiceError.helperStartTimedOut))
                connection.invalidate()
            }
            let timeoutInterval = DispatchTimeInterval.nanoseconds(Int(self.helperResponseTimeoutNanoseconds))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeoutInterval,
                execute: timeoutWorkItem)

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                timeoutWorkItem.cancel()
                connection.invalidate()
                box.resume(with: .failure(SystemProxyServiceError.helperConnectionFailed(error.localizedDescription)))
            }) as? ProxyHelperProtocol else {
                timeoutWorkItem.cancel()
                connection.invalidate()
                box.resume(
                    with: .failure(
                        SystemProxyServiceError.helperConnectionFailed("Unable to create XPC proxy.")))
                return
            }

            invoke(helper) { result in
                timeoutWorkItem.cancel()
                defer { connection.invalidate() }
                box.resume(with: result)
            }
        }
    }

    nonisolated func clearBlocking(timeout: TimeInterval = 2.0) {
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let connection = self.makeConnection()

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
                semaphore.signal()
            }) as? ProxyHelperProtocol else {
                connection.invalidate()
                semaphore.signal()
                return
            }

            helper.clearSystemProxy { _, _ in
                connection.invalidate()
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + timeout)
    }

    private nonisolated func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: ProxyHelperConstants.machServiceName,
            options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
        if let team = self.signingTeamIdentifier(at: Bundle.main.bundleURL) {
            connection.setCodeSigningRequirement(
                "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
        }
        connection.activate()
        return connection
    }

    private func validateHelperSigningRequirements() throws {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent(ProxyHelperConstants.helperBundleProgram)
        let appTeam = self.signingTeamIdentifier(at: Bundle.main.bundleURL)
        let helperTeam = self.signingTeamIdentifier(at: helperURL)
        guard appTeam == helperTeam else {
            throw SystemProxyServiceError.helperInstallFailed(
                "App and helper Team ID mismatch (\(appTeam ?? "none") != \(helperTeam ?? "none")).")
        }
    }

    private nonisolated func signingTeamIdentifier(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else { return nil }

        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
