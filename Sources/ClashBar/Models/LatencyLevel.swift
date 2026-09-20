/// 延迟分级。信号条的高度与颜色都由它决定，所以「高低」和「颜色」表达的是同一件事：
/// 越靠上、越偏绿代表越快。分级只做归类，具体的颜色与高度由展示层决定。
enum LatencyLevel {
    /// 低于 200ms
    case excellent
    /// 200ms 起，低于 500ms
    case good
    /// 500ms 起，低于 1000ms
    case fair
    /// 1000ms 及以上
    case poor
    /// 测速超时（接口用 0 表示）
    case timeout

    init(delay: Int?) {
        guard let delay, delay > 0 else {
            self = .timeout
            return
        }
        switch delay {
        case ..<200: self = .excellent
        case ..<500: self = .good
        case ..<1000: self = .fair
        default: self = .poor
        }
    }
}
