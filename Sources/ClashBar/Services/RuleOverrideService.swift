import Darwin
import Foundation

// 规则覆写（参考 OpenClash 的自定义规则）：用户在 overrides/ 下维护三份纯文本，
// 启动 / 重载时把它们拼进所选配置，生成 state/runtime/ 下的运行时配置交给 mihomo。
// 原配置文件永远不被改写。项目不依赖 YAML 库，这里按行拼接，只支持块式 rules / rule-providers。

enum RuleOverrideFile: String, CaseIterable, Sendable {
    case prepend
    case append
    case ruleProviders

    var fileName: String {
        switch self {
        case .prepend: "prepend.list"
        case .append: "append.list"
        case .ruleProviders: "rule-providers.yaml"
        }
    }

    var template: String {
        switch self {
        case .prepend:
            """
            # 前置规则：插在订阅 rules 的最前面，优先级最高。
            # 一行一条，写法与配置文件 rules 相同，不需要开头的 "- "；以 # 开头的行是注释。
            # 引用的策略组、RULE-SET 规则集必须存在，否则配置校验会失败。
            #
            # DOMAIN-SUFFIX,example.com,DIRECT
            # RULE-SET,my-rules,Proxy

            """
        case .append:
            """
            # 追加规则：插在订阅 rules 末尾的 MATCH / FINAL 之前（放在 MATCH 之后永远匹配不到）。
            # 一行一条，写法与配置文件 rules 相同，不需要开头的 "- "；以 # 开头的行是注释。
            #
            # GEOIP,CN,DIRECT

            """
        case .ruleProviders:
            """
            # 规则集：写 rule-providers: 下面那一层，缩进会自动对齐；与订阅同名时以这里为准。
            # 在前置 / 追加规则里用 RULE-SET,<名称>,<策略> 引用。
            #
            # my-rules:
            #   type: http
            #   behavior: classical
            #   format: yaml
            #   url: https://example.com/rules.yaml
            #   path: ./ruleset/my-rules.yaml
            #   interval: 86400

            """
        }
    }
}

struct RuleOverrideCounts: Equatable, Sendable {
    var prepend = 0
    var append = 0
    var ruleProviders = 0

    var isEmpty: Bool {
        self.prepend == 0 && self.append == 0 && self.ruleProviders == 0
    }
}

struct RuleOverrideContent: Equatable, Sendable {
    var prependRules: [String] = []
    var appendRules: [String] = []
    /// 已去掉公共缩进的 rule-providers 子树（不含 `rule-providers:` 头）。
    var ruleProviderLines: [String] = []
    var ruleProviderNames: [String] = []

    var counts: RuleOverrideCounts {
        RuleOverrideCounts(
            prepend: self.prependRules.count,
            append: self.appendRules.count,
            ruleProviders: self.ruleProviderNames.count)
    }
}

enum RuleOverrideError: LocalizedError, Equatable {
    case unreadable(fileName: String)
    case unsupportedFlowStyle(key: String)
    case invalidRuleProviders(line: Int)

    var errorDescription: String? {
        switch self {
        case let .unreadable(fileName):
            "Rule override: cannot read \(fileName) as UTF-8 text"
        case let .unsupportedFlowStyle(key):
            "Rule override: the config writes `\(key):` inline ([...] / {...}); only block style is supported"
        case let .invalidRuleProviders(line):
            "Rule override: rule-providers.yaml line \(line) is not a `name:` entry or is indented under nothing"
        }
    }
}

struct RuleOverrideService {
    let workingDirectoryManager: WorkingDirectoryManager

    var overridesDirectoryURL: URL {
        self.workingDirectoryManager.rootDirectoryURL.appendingPathComponent("overrides", isDirectory: true)
    }

    var runtimeDirectoryURL: URL {
        self.workingDirectoryManager.stateDirectoryURL.appendingPathComponent("runtime", isDirectory: true)
    }

    func url(for file: RuleOverrideFile) -> URL {
        self.overridesDirectoryURL.appendingPathComponent(file.fileName, isDirectory: false)
    }

    /// 运行时配置沿用原文件名，这样校验失败弹窗里显示的仍是用户认识的名字。
    func runtimeConfigURL(forOriginal configPath: String) -> URL {
        let name = URL(fileURLWithPath: configPath).lastPathComponent
        return self.runtimeDirectoryURL.appendingPathComponent(name, isDirectory: false)
    }

    func ensureOverridesDirectory(fileManager: FileManager = .default) throws {
        let directory = try self.workingDirectoryManager.normalizeAndValidateWithinRoot(self.overridesDirectoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 编辑器里显示的文本：文件不存在时给出带注释的模板（不落盘，保存时才写）。
    func editableText(for file: RuleOverrideFile, fileManager: FileManager = .default) throws -> String {
        let url = self.url(for: file)
        guard fileManager.fileExists(atPath: url.path) else { return file.template }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw RuleOverrideError.unreadable(fileName: file.fileName)
        }
        return text
    }

    func write(_ text: String, to file: RuleOverrideFile, fileManager: FileManager = .default) throws {
        try self.ensureOverridesDirectory(fileManager: fileManager)
        let target = try self.workingDirectoryManager.normalizeAndValidateWithinRoot(self.url(for: file))
        try Data(text.utf8).write(to: target, options: .atomic)
    }

    func loadContent(fileManager: FileManager = .default) throws -> RuleOverrideContent {
        var content = RuleOverrideContent()
        content.prependRules = try Self.parseRuleList(self.readIfExists(.prepend, fileManager: fileManager))
        content.appendRules = try Self.parseRuleList(self.readIfExists(.append, fileManager: fileManager))
        let providers = try Self.parseRuleProviders(self.readIfExists(.ruleProviders, fileManager: fileManager))
        content.ruleProviderLines = providers.lines
        content.ruleProviderNames = providers.names
        return content
    }

    /// 生成运行时配置并写盘，返回写入的路径。
    func writeRuntimeConfig(
        originalConfigPath: String,
        content: RuleOverrideContent,
        fileManager: FileManager = .default) throws -> URL
    {
        guard let raw = try? String(contentsOfFile: originalConfigPath, encoding: .utf8) else {
            throw RuleOverrideError.unreadable(fileName: URL(fileURLWithPath: originalConfigPath).lastPathComponent)
        }
        let merged = try Self.apply(content, to: raw)

        let directory = try self.workingDirectoryManager.normalizeAndValidateWithinRoot(self.runtimeDirectoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = try self.workingDirectoryManager.normalizeAndValidateWithinRoot(
            self.runtimeConfigURL(forOriginal: originalConfigPath))
        try Data(merged.utf8).write(to: target, options: .atomic)
        return target
    }

    private func readIfExists(_ file: RuleOverrideFile, fileManager: FileManager) throws -> String {
        let url = self.url(for: file)
        guard fileManager.fileExists(atPath: url.path) else { return "" }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw RuleOverrideError.unreadable(fileName: file.fileName)
        }
        return text
    }
}

// MARK: - Parsing

extension RuleOverrideService {
    static func lines(of text: String) -> [String] {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        return normalized.components(separatedBy: "\n")
    }

    static func parseRuleList(_ text: String) -> [String] {
        self.lines(of: text).compactMap { line in
            var rule = line.trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty, !rule.hasPrefix("#") else { return nil }
            if rule.hasPrefix("- ") {
                rule = String(rule.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            rule = self.unquoted(rule)
            return rule.isEmpty ? nil : rule
        }
    }

    static func parseRuleProviders(_ text: String) throws -> (lines: [String], names: [String]) {
        var lines = self.lines(of: text)

        // 允许用户连同 `rule-providers:` 头一起粘贴进来。
        if let headerIndex = lines.firstIndex(where: { !self.isBlankOrComment($0) }),
           self.isTopLevelKeyLine(lines[headerIndex], key: "rule-providers")
        {
            lines.remove(at: headerIndex)
        }

        let contentLines = lines.filter { !self.isBlankOrComment($0) }
        guard let baseIndent = contentLines.map(self.indentWidth).min() else {
            return ([], [])
        }

        var names: [String] = []
        for (offset, line) in lines.enumerated() where !self.isBlankOrComment(line) {
            guard self.indentWidth(line) == baseIndent else { continue }
            guard let name = self.mappingKey(line) else {
                throw RuleOverrideError.invalidRuleProviders(line: offset + 1)
            }
            names.append(name)
        }

        let dedented = lines.map { line in
            self.isBlankOrComment(line) ? line.trimmingCharacters(in: .whitespaces) : String(line.dropFirst(baseIndent))
        }
        return (self.trimmingBlankEdges(dedented), names)
    }
}

// MARK: - Splicing

extension RuleOverrideService {
    static func apply(_ content: RuleOverrideContent, to configText: String) throws -> String {
        var lines = self.lines(of: configText)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }

        if !content.ruleProviderLines.isEmpty {
            try self.spliceRuleProviders(content, into: &lines)
        }
        if !content.prependRules.isEmpty || !content.appendRules.isEmpty {
            try self.spliceRules(content, into: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func spliceRules(_ content: RuleOverrideContent, into lines: inout [String]) throws {
        guard let header = try self.blockHeaderIndex(for: "rules", in: &lines, emptyFlow: "[]") else {
            lines.append("rules:")
            lines.append(contentsOf: (content.prependRules + content.appendRules).map { "  - \(self.quoted($0))" })
            return
        }

        let end = self.blockEnd(after: header, in: lines)
        let itemIndices = ((header + 1)..<end).filter {
            lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("-")
        }
        let indent = itemIndices.first.map { String(lines[$0].prefix(while: { $0 == " " })) } ?? "  "
        let format = { (rule: String) in "\(indent)- \(self.quoted(rule))" }

        // 追加规则先插：插入点在前置规则之后，先插不会让前置的下标失效。
        if !content.appendRules.isEmpty {
            let matchIndex = itemIndices.last(where: { self.isFinalRuleLine(lines[$0]) })
            let insertAt = matchIndex ?? itemIndices.last.map { $0 + 1 } ?? header + 1
            lines.insert(contentsOf: content.appendRules.map(format), at: insertAt)
        }
        if !content.prependRules.isEmpty {
            lines.insert(contentsOf: content.prependRules.map(format), at: header + 1)
        }
    }

    private static func spliceRuleProviders(_ content: RuleOverrideContent, into lines: inout [String]) throws {
        guard let header = try self.blockHeaderIndex(for: "rule-providers", in: &lines, emptyFlow: "{}") else {
            lines.append("rule-providers:")
            lines.append(contentsOf: self.indented(content.ruleProviderLines, by: "  "))
            return
        }

        var end = self.blockEnd(after: header, in: lines)
        let childIndent = ((header + 1)..<end)
            .first { !self.isBlankOrComment(lines[$0]) }
            .map { String(lines[$0].prefix(while: { $0 == " " })) } ?? "  "

        // 与覆写同名的订阅条目整条删掉，以覆写为准。
        let overridden = Set(content.ruleProviderNames)
        var index = header + 1
        while index < end {
            let line = lines[index]
            guard !self.isBlankOrComment(line),
                  self.indentWidth(line) == childIndent.count,
                  let name = self.mappingKey(line), overridden.contains(name)
            else {
                index += 1
                continue
            }
            var entryEnd = index + 1
            while entryEnd < end,
                  self.isBlankOrComment(lines[entryEnd]) || self.indentWidth(lines[entryEnd]) > childIndent.count
            {
                entryEnd += 1
            }
            lines.removeSubrange(index..<entryEnd)
            end -= entryEnd - index
        }

        var insertAt = end
        while insertAt > header + 1, self.isBlankOrComment(lines[insertAt - 1]) {
            insertAt -= 1
        }
        lines.insert(contentsOf: self.indented(content.ruleProviderLines, by: childIndent), at: insertAt)
    }

    /// 找到顶层 `key:`。`key: []` / `key: {}` 这种空的行内写法改写成块式头；非空行内写法无法按行拼接，直接报错。
    private static func blockHeaderIndex(for key: String, in lines: inout [String], emptyFlow: String) throws -> Int? {
        guard let index = lines.firstIndex(where: { self.isTopLevelKeyLine($0, key: key) }) else {
            return nil
        }
        let value = self.inlineValue(of: lines[index], key: key)
        if value.isEmpty {
            return index
        }
        if value.replacingOccurrences(of: " ", with: "") == emptyFlow {
            lines[index] = "\(key):"
            return index
        }
        throw RuleOverrideError.unsupportedFlowStyle(key: key)
    }

    /// 顶层块在下一个顶层键（第 0 列、非列表项、非注释）或文档分隔符处结束；第 0 列的 `- ` 仍属于本块。
    private static func blockEnd(after header: Int, in lines: [String]) -> Int {
        var index = header + 1
        while index < lines.count {
            let line = lines[index]
            if self.indentWidth(line) == 0, !self.isBlankOrComment(line) {
                if line.hasPrefix("---") || line.hasPrefix("...") { break }
                if !line.hasPrefix("-") { break }
            }
            index += 1
        }
        return index
    }

    private static func isFinalRuleLine(_ line: String) -> Bool {
        var rule = line.trimmingCharacters(in: .whitespaces)
        guard rule.hasPrefix("-") else { return false }
        rule = self.unquoted(String(rule.dropFirst()).trimmingCharacters(in: .whitespaces)).uppercased()
        return rule.hasPrefix("MATCH,") || rule.hasPrefix("FINAL,") || rule == "MATCH" || rule == "FINAL"
    }
}

// MARK: - Line helpers

extension RuleOverrideService {
    static func isTopLevelKeyLine(_ line: String, key: String) -> Bool {
        guard self.indentWidth(line) == 0 else { return false }
        return line.hasPrefix("\(key):") && (line.count == key.count + 1 || line.dropFirst(key.count + 1).first == " ")
    }

    private static func inlineValue(of line: String, key: String) -> String {
        var value = String(line.dropFirst(key.count + 1))
        if let commentRange = value.range(of: " #") {
            value = String(value[..<commentRange.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func isBlankOrComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("#")
    }

    private static func indentWidth(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    /// `name:` / `"name":` / `name: {...}` 的键名；不是映射项时返回 nil。
    private static func mappingKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("-") else { return nil }

        if let quote = trimmed.first, quote == "\"" || quote == "'" {
            let rest = trimmed.dropFirst()
            guard let close = rest.firstIndex(of: quote), rest[rest.index(after: close)...].hasPrefix(":") else {
                return nil
            }
            return String(rest[..<close])
        }

        guard let colon = trimmed.range(of: ":") else { return nil }
        let after = trimmed[colon.upperBound...]
        guard after.isEmpty || after.hasPrefix(" ") else { return nil }
        let name = trimmed[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    /// 统一输出成双引号标量，规则里出现 `: `、` #`、`\` 等字符时也不会破坏 YAML。
    private static func quoted(_ rule: String) -> String {
        let escaped = rule
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func indented(_ lines: [String], by indent: String) -> [String] {
        lines.map { $0.isEmpty ? $0 : indent + $0 }
    }

    private static func trimmingBlankEdges(_ lines: [String]) -> [String] {
        var result = lines
        while let first = result.first, first.isEmpty { result.removeFirst() }
        while let last = result.last, last.isEmpty { result.removeLast() }
        return result
    }
}

// MARK: - Monitoring

/// 监听 overrides/ 目录和其中三个文件。编辑器原地写入只会触发文件事件，
/// 原子保存（写临时文件再 rename）只会触发目录事件，所以两者都要盯；每次变化后重新挂文件源。
final class RuleOverrideDirectoryMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.clashbar.rule-override-monitor", qos: .utility)
    private let directoryURL: URL
    private let fileURLs: [URL]
    private let onChange: @Sendable () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []

    init(directoryURL: URL, fileURLs: [URL], onChange: @escaping @Sendable () -> Void) {
        self.directoryURL = directoryURL
        self.fileURLs = fileURLs
        self.onChange = onChange
        self.queue.async { self.rearm() }
    }

    func cancel() {
        self.queue.async {
            self.sources.forEach { $0.cancel() }
            self.sources.removeAll()
        }
    }

    deinit {
        self.sources.forEach { $0.cancel() }
    }

    private func rearm() {
        self.sources.forEach { $0.cancel() }
        self.sources = ([self.directoryURL] + self.fileURLs).compactMap { url in
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .extend, .rename, .revoke],
                queue: self.queue)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.rearm()
                self.onChange()
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
    }
}
