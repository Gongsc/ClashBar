import Foundation

enum RuleOverrideStatus: Equatable {
    /// 覆写开着但三个文件都没有有效内容，核心按原配置运行。
    case empty
    case applied(configName: String, at: Date)
    case failed(message: String, at: Date)
}

@MainActor
final class RuleOverrideStore: ObservableObject {
    private static let enabledKey = "clashbar.rule_override.enabled"

    private let defaults: UserDefaults

    @Published var isEnabled: Bool {
        didSet { self.defaults.set(self.isEnabled, forKey: Self.enabledKey) }
    }

    @Published var counts = RuleOverrideCounts()
    @Published var status: RuleOverrideStatus?
    @Published var isApplying = false

    var monitor: RuleOverrideDirectoryMonitor?
    var debounceTask: Task<Void, Never>?
    /// 上次应用时三份文件的内容，用来过滤 attrib / 无实际改动的文件事件。
    var lastContent: RuleOverrideContent?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }
}
