import Foundation

/// 把流量采样序列裁剪到展示时长之内。
///
/// 采样序列只活在内存里：面板开合之间保留，进程退出即丢弃。裁剪依据是真实时间而非
/// 下标——面板关闭且状态栏为「仅图标」时流量流会停掉，恢复后的序列里存在真实空档，
/// 按下标裁剪会把空档压缩掉。`maxCount` 只是内存兜底，防止采样频率异常时无限增长。
struct TrimTrafficHistoryUseCase {
    struct Input {
        let samples: [TrafficSample]
        let window: TimeInterval
        let now: Date
        let maxCount: Int
    }

    func execute(_ input: Input) -> [TrafficSample] {
        let cutoff = input.now.addingTimeInterval(-input.window)
        var samples = input.samples

        if let firstKept = samples.firstIndex(where: { $0.at >= cutoff }) {
            if firstKept > 0 {
                samples.removeFirst(firstKept)
            }
        } else {
            samples.removeAll(keepingCapacity: true)
        }

        if input.maxCount > 0, samples.count > input.maxCount {
            samples.removeFirst(samples.count - input.maxCount)
        }

        return samples
    }
}
