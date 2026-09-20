import Foundation

enum APIHealth: String, Codable {
    case unknown
    case healthy
    case degraded
    case failed
}

enum CoreMode: String, Codable {
    case rule
    case global
    case direct
}

struct VersionInfo: Codable, Equatable {
    let version: String
}

struct CoreUpgradeResponse: Decodable, Equatable {
    let status: String?
    let message: String?
}

struct TrafficSnapshot: Decodable, Equatable {
    let up: Int64
    let down: Int64
    let upTotal: Int64?
    let downTotal: Int64?

    private enum CodingKeys: String, CodingKey {
        case up
        case down
        case upTotal
        case downTotal
        case upTotalLower = "uptotal"
        case downTotalLower = "downtotal"
        case uploadTotal
        case downloadTotal
    }

    init(up: Int64, down: Int64, upTotal: Int64? = nil, downTotal: Int64? = nil) {
        self.up = up
        self.down = down
        self.upTotal = upTotal
        self.downTotal = downTotal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.up = try container.decodeIfPresent(Int64.self, forKey: .up) ?? 0
        self.down = try container.decodeIfPresent(Int64.self, forKey: .down) ?? 0
        self.upTotal = try container.decodeIfPresent(Int64.self, forKey: .upTotal)
            ?? container.decodeIfPresent(Int64.self, forKey: .upTotalLower)
            ?? container.decodeIfPresent(Int64.self, forKey: .uploadTotal)
        self.downTotal = try container.decodeIfPresent(Int64.self, forKey: .downTotal)
            ?? container.decodeIfPresent(Int64.self, forKey: .downTotalLower)
            ?? container.decodeIfPresent(Int64.self, forKey: .downloadTotal)
    }
}

struct MemorySnapshot: Codable, Equatable {
    let inuse: Int64

    private enum CodingKeys: String, CodingKey {
        case inuse
    }

    init(inuse: Int64) {
        self.inuse = inuse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inuse = try container.decodeIfPresent(Int64.self, forKey: .inuse) ?? 0
    }
}

/// 流量曲线的一个采样点。带时间戳是为了让「展示时长」按真实时间裁剪：
/// 面板关闭且状态栏为「仅图标」时流量流会停掉，恢复后的历史存在真实空档，
/// 纯按下标排布会把空档压缩掉，让曲线撒谎。
struct TrafficSample: Equatable {
    let at: Date
    let up: Int64
    let down: Int64
}

/// 流量曲线展示时长。仅影响展示与内存中保留的窗口，不做持久化存储。
enum TrafficHistoryWindow: Int, CaseIterable, Identifiable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { self.rawValue }

    var duration: TimeInterval { TimeInterval(self.rawValue * 60) }

    var titleKey: String { "ui.traffic_window.\(self.rawValue)min" }
}
