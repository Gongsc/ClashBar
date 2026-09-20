import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct TrafficSparklineView: View {
    let samples: [TrafficSample]
    let window: TimeInterval

    /// 相邻采样超过这个间隔就把曲线断开。流量流约每秒一个点，更大的间隔意味着
    /// 期间根本没有采集（面板关闭且状态栏为「仅图标」时流量流会停掉），
    /// 直接连起来等于凭空编造中间那段数据。
    private let gapThreshold: TimeInterval = 3

    var body: some View {
        GeometryReader { geo in
            let now = Date()
            let visible = self.samples.filter { now.timeIntervalSince($0.at) <= self.window }
            let maxY = max(1.0, Double(max(
                visible.map(\.down).max() ?? 0,
                visible.map(\.up).max() ?? 0)))
            let axisY = floor(geo.size.height * 0.5)
            let upperSpan = max(1, axisY - 2)
            let lowerSpan = max(1, geo.size.height - axisY - 2)
            let upContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: upperSpan,
                maxY: maxY,
                direction: .up,
                now: now,
                window: self.window)
            let downContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: lowerSpan,
                maxY: maxY,
                direction: .down,
                now: now,
                window: self.window)
            let runs = self.continuousRuns(in: visible)

            ZStack {
                self.axisPath(width: geo.size.width, axisY: axisY)
                    .stroke(
                        self.nativeSeparator.opacity(0.55),
                        style: StrokeStyle(lineWidth: T.stroke, lineCap: .round))

                self.areaPath(for: runs, keyPath: \.up, context: upContext)
                    .fill(
                        LinearGradient(
                            colors: [
                                self.nativeAccent.opacity(0.30),
                                self.nativeAccent.opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                self.areaPath(for: runs, keyPath: \.down, context: downContext)
                    .fill(
                        LinearGradient(
                            colors: [
                                self.nativePositive.opacity(0.32),
                                self.nativePositive.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                self.linePath(for: runs, keyPath: \.up, context: upContext)
                    .stroke(
                        self.nativeAccent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                self.linePath(for: runs, keyPath: \.down, context: downContext)
                    .stroke(
                        self.nativePositive.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// 把采样序列按空档切成若干段连续区间，每段单独成路径。
    private func continuousRuns(in samples: [TrafficSample]) -> [[TrafficSample]] {
        var runs: [[TrafficSample]] = []
        var current: [TrafficSample] = []

        for sample in samples {
            if let previous = current.last, sample.at.timeIntervalSince(previous.at) > self.gapThreshold {
                runs.append(current)
                current = []
            }
            current.append(sample)
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    private func linePath(
        for runs: [[TrafficSample]],
        keyPath: KeyPath<TrafficSample, Int64>,
        context: SparklinePathContext) -> Path
    {
        var path = Path()
        for run in runs {
            guard let first = run.first else { continue }
            path.move(to: self.point(for: first, keyPath: keyPath, context: context))
            for sample in run.dropFirst() {
                path.addLine(to: self.point(for: sample, keyPath: keyPath, context: context))
            }
            if run.count == 1 {
                // 圆头线帽让单点区间仍然画出一个可见的点，而不是什么都不画。
                path.addLine(to: self.point(for: first, keyPath: keyPath, context: context))
            }
        }
        return path
    }

    private func areaPath(
        for runs: [[TrafficSample]],
        keyPath: KeyPath<TrafficSample, Int64>,
        context: SparklinePathContext) -> Path
    {
        var path = Path()
        for run in runs {
            guard let first = run.first, let last = run.last, run.count > 1 else { continue }
            path.move(to: self.point(for: first, keyPath: keyPath, context: context))
            for sample in run.dropFirst() {
                path.addLine(to: self.point(for: sample, keyPath: keyPath, context: context))
            }
            path.addLine(to: CGPoint(x: self.xPosition(for: last, context: context), y: context.axisY))
            path.addLine(to: CGPoint(x: self.xPosition(for: first, context: context), y: context.axisY))
            path.closeSubpath()
        }
        return path
    }

    /// 横轴按真实时间排布，右边缘代表此刻。空档因此会如实留白，
    /// 而不是被压缩成相邻的两个采样点。
    private func xPosition(for sample: TrafficSample, context: SparklinePathContext) -> CGFloat {
        let age = context.now.timeIntervalSince(sample.at)
        let ratio = max(0, min(1, age / max(context.window, 1)))
        return context.width - CGFloat(ratio) * context.width
    }

    private func point(
        for sample: TrafficSample,
        keyPath: KeyPath<TrafficSample, Int64>,
        context: SparklinePathContext) -> CGPoint
    {
        CGPoint(
            x: self.xPosition(for: sample, context: context),
            y: self.yPosition(
                sample[keyPath: keyPath],
                axisY: context.axisY,
                span: context.span,
                maxY: context.maxY,
                direction: context.direction))
    }

    private func axisPath(width: CGFloat, axisY: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: axisY))
        path.addLine(to: CGPoint(x: width, y: axisY))
        return path
    }

    private func yPosition(
        _ value: Int64,
        axisY: CGFloat,
        span: CGFloat,
        maxY: Double,
        direction: LineDirection) -> CGFloat
    {
        let clamped = max(0.0, min(Double(value), maxY))
        let ratio = CGFloat(clamped / maxY)

        switch direction {
        case .up:
            return axisY - ratio * span
        case .down:
            return axisY + ratio * span
        }
    }

    private struct SparklinePathContext {
        let width: CGFloat
        let axisY: CGFloat
        let span: CGFloat
        let maxY: Double
        let direction: LineDirection
        let now: Date
        let window: TimeInterval
    }

    private enum LineDirection {
        case up
        case down
    }
}
