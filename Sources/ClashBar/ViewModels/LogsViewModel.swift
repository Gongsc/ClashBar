import Foundation
import SwiftUI

@MainActor
final class LogsViewModel: ObservableObject {
    @Published var selectedSources: Set<AppLogSource> = []
    @Published var selectedLevels: Set<LogLevelFilter> = []
    @Published var searchText: String = ""
    @Published private(set) var visibleLogs: [AppErrorLogEntry] = []

    init() {}

    func toggleSource(_ source: AppLogSource) {
        self.toggleSelection(source, selection: &self.selectedSources)
    }

    func toggleLevel(_ level: LogLevelFilter) {
        self.toggleSelection(level, selection: &self.selectedLevels)
    }

    func updateVisibleLogs(
        from logs: [AppErrorLogEntry],
        searchTextContent: @escaping (AppErrorLogEntry) -> String,
        normalizedLevel: @escaping (String) -> String,
        levelFilter: @escaping (String) -> LogLevelFilter)
    {
        let source = logs.prefix(120)
        let trimmedKeyword = self.searchText.trimmed
        let isShowingAllSources = self.selectedSources.isEmpty
        let isShowingAllLevels = self.selectedLevels.isEmpty

        let nextLogs: [AppErrorLogEntry] = if trimmedKeyword.isEmpty, isShowingAllSources, isShowingAllLevels {
            Array(source)
        } else {
            source.filter { log in
                guard isShowingAllSources || self.selectedSources.contains(log.source) else { return false }
                guard trimmedKeyword.isEmpty || searchTextContent(log).localizedStandardContains(trimmedKeyword)
                else {
                    return false
                }
                return isShowingAllLevels || self.selectedLevels
                    .contains(levelFilter(normalizedLevel(log.level)))
            }
        }

        guard nextLogs != self.visibleLogs else { return }
        self.visibleLogs = nextLogs
    }

    private func toggleSelection<Value: Hashable>(
        _ value: Value,
        selection: inout Set<Value>)
    {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}
