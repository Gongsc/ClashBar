import Foundation
import SwiftUI

enum ConnectionsTransportFilter: String, CaseIterable, Identifiable {
    case all
    case tcp
    case udp
    case other

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .all:
            "ui.network.filter.transport.all"
        case .tcp:
            "ui.network.filter.transport.tcp"
        case .udp:
            "ui.network.filter.transport.udp"
        case .other:
            "ui.network.filter.transport.other"
        }
    }

    func matches(_ network: String?) -> Bool {
        let normalized = network.trimmedOrEmpty.lowercased()

        switch self {
        case .all:
            return true
        case .tcp:
            return normalized == "tcp"
        case .udp:
            return normalized == "udp"
        case .other:
            return !normalized.isEmpty && normalized != "tcp" && normalized != "udp"
        }
    }
}

enum ConnectionsSortOption: String, CaseIterable, Identifiable {
    case `default`
    case newest
    case oldest
    case uploadDesc
    case downloadDesc
    case totalDesc

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .default:
            "ui.network.sort.default"
        case .newest:
            "ui.network.sort.newest"
        case .oldest:
            "ui.network.sort.oldest"
        case .uploadDesc:
            "ui.network.sort.upload_desc"
        case .downloadDesc:
            "ui.network.sort.download_desc"
        case .totalDesc:
            "ui.network.sort.total_desc"
        }
    }
}

@MainActor
final class ConnectionsViewModel: ObservableObject {
    @Published var filterText: String = ""
    @Published var transportFilter: ConnectionsTransportFilter = .all
    @Published var sortOption: ConnectionsSortOption = .default
    @Published var hoveredConnectionID: String?
    @Published private(set) var visibleConnections: [ConnectionSummary] = []

    init() {}

    func updateVisibleConnections(
        from connections: [ConnectionSummary],
        searchText: (ConnectionSummary) -> String)
    {
        let source = connections.prefix(120)
        let keyword = self.filterText.trimmed

        let filtered: [ConnectionSummary] = if keyword.isEmpty, self.transportFilter == .all {
            Array(source)
        } else {
            source.filter { connection in
                guard self.transportFilter.matches(connection.metadata?.network) else { return false }
                guard keyword.isEmpty || searchText(connection).localizedStandardContains(keyword) else {
                    return false
                }
                return true
            }
        }

        let nextConnections = self.sortedConnections(filtered, sortOption: self.sortOption)
        guard nextConnections != self.visibleConnections else { return }
        self.visibleConnections = nextConnections
    }

    private func sortedConnections(
        _ source: [ConnectionSummary],
        sortOption: ConnectionsSortOption) -> [ConnectionSummary]
    {
        switch sortOption {
        case .default:
            source
        case .newest:
            self.connectionsSortedByTimestamp(source, descending: true)
        case .oldest:
            self.connectionsSortedByTimestamp(source, descending: false)
        case .uploadDesc:
            self.connectionsSortedByTraffic(source) { $0.upload ?? 0 }
        case .downloadDesc:
            self.connectionsSortedByTraffic(source) { $0.download ?? 0 }
        case .totalDesc:
            self.connectionsSortedByTraffic(source) { ($0.upload ?? 0) + ($0.download ?? 0) }
        }
    }

    private func connectionsSortedByTimestamp(
        _ source: [ConnectionSummary],
        descending: Bool) -> [ConnectionSummary]
    {
        let fallback: TimeInterval = descending ? -1 : .greatestFiniteMagnitude
        return source.sorted { lhs, rhs in
            let left = lhs.startTimestamp ?? fallback
            let right = rhs.startTimestamp ?? fallback
            if left != right {
                return descending ? (left > right) : (left < right)
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func connectionsSortedByTraffic(
        _ source: [ConnectionSummary],
        _ metric: (ConnectionSummary) -> Int64) -> [ConnectionSummary]
    {
        source.sorted { lhs, rhs in
            let left = metric(lhs)
            let right = metric(rhs)
            if left != right {
                return left > right
            }
            return (lhs.startTimestamp ?? -1) > (rhs.startTimestamp ?? -1)
        }
    }
}
