import Foundation

struct RemoteConfigSubscription: Codable, Equatable {
    let urlString: String
    var autoUpdateEnabled: Bool
    var autoUpdateIntervalHours: Int
    var lastUpdateCheckAt: Date?
    var lastSuccessAt: Date?
    var nextRetryAt: Date?

    static let defaultAutoUpdateIntervalHours = 6
    static let minimumAutoUpdateIntervalHours = 1
    static let failureRetryBackoffSeconds: TimeInterval = 15 * 60

    init(
        urlString: String,
        autoUpdateEnabled: Bool = false,
        autoUpdateIntervalHours: Int = defaultAutoUpdateIntervalHours,
        lastUpdateCheckAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        nextRetryAt: Date? = nil)
    {
        self.urlString = urlString
        self.autoUpdateEnabled = autoUpdateEnabled
        self.autoUpdateIntervalHours = max(Self.minimumAutoUpdateIntervalHours, autoUpdateIntervalHours)
        self.lastUpdateCheckAt = lastUpdateCheckAt
        self.lastSuccessAt = lastSuccessAt
        self.nextRetryAt = nextRetryAt
    }

    func nextUpdateAt() -> Date? {
        guard self.autoUpdateEnabled else { return nil }
        if let retryAt = self.nextRetryAt {
            return retryAt
        }
        guard let lastCheck = self.lastUpdateCheckAt else { return nil }
        return self.nextUpdateDate(from: lastCheck)
    }

    func isDue(now: Date = Date()) -> Bool {
        guard self.autoUpdateEnabled else { return false }
        guard let nextUpdateAt = self.nextUpdateAt() else { return true }
        return now >= nextUpdateAt
    }

    func markSucceeded(at date: Date = Date()) -> RemoteConfigSubscription {
        RemoteConfigSubscription(
            urlString: self.urlString,
            autoUpdateEnabled: self.autoUpdateEnabled,
            autoUpdateIntervalHours: self.autoUpdateIntervalHours,
            lastUpdateCheckAt: date,
            lastSuccessAt: date,
            nextRetryAt: nil)
    }

    func markFailed(at date: Date = Date(), isAutoUpdate: Bool) -> RemoteConfigSubscription {
        let shouldScheduleRetry = self.autoUpdateEnabled && (isAutoUpdate || self.isDue(now: date))
        let retryInterval = min(Self.failureRetryBackoffSeconds, TimeInterval(self.autoUpdateIntervalHours) * 3600)
        return RemoteConfigSubscription(
            urlString: self.urlString,
            autoUpdateEnabled: self.autoUpdateEnabled,
            autoUpdateIntervalHours: self.autoUpdateIntervalHours,
            lastUpdateCheckAt: self.lastUpdateCheckAt,
            lastSuccessAt: self.lastSuccessAt,
            nextRetryAt: shouldScheduleRetry ? date.addingTimeInterval(retryInterval) : self.nextRetryAt)
    }

    private func nextUpdateDate(from lastCheck: Date) -> Date {
        lastCheck.addingTimeInterval(TimeInterval(self.autoUpdateIntervalHours) * 3600)
    }
}
