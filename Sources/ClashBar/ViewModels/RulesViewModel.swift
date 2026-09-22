import Foundation
import SwiftUI

enum RulesTypeFilter: String, CaseIterable, Identifiable {
    case all
    case domain
    case ip
    case ruleSet
    case other

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .all:
            "ui.rules.type.all"
        case .domain:
            "ui.rules.type.domain"
        case .ip:
            "ui.rules.type.ip"
        case .ruleSet:
            "ui.rules.type.ruleset"
        case .other:
            "ui.rules.type.other"
        }
    }

    func matches(_ type: String?) -> Bool {
        guard self != .all else { return true }
        let normalized = type.trimmedOrEmpty.lowercased()
        guard !normalized.isEmpty else { return self == .other }

        if normalized.contains("rule-set") || normalized.contains("ruleset") {
            return self == .ruleSet
        }
        if normalized.contains("domain") || normalized.contains("geosite") {
            return self == .domain
        }
        if normalized.contains("ip") || normalized.contains("geoip") {
            return self == .ip
        }
        return self == .other
    }
}

struct RulePolicyOption: Hashable, Identifiable {
    let name: String

    var id: String {
        self.name
    }

    var isAll: Bool {
        self.name.isEmpty
    }

    static let all = RulePolicyOption(name: "")
}

struct RuleGroup: Equatable, Identifiable {
    let policy: String
    let rules: [RuleItem]

    var id: String {
        self.policy
    }
}

struct PresentRulesOutput: Equatable {
    let rules: [RuleItem]
    let groups: [RuleGroup]
    let providerLookup: [String: ProviderDetail]
    let policyOptions: [RulePolicyOption]
    let typeCounts: [RulesTypeFilter: Int]

    static let empty = PresentRulesOutput(
        rules: [], groups: [], providerLookup: [:], policyOptions: [.all], typeCounts: [:])
}

@MainActor
final class RulesViewModel: ObservableObject {
    @Published var filterText: String = ""
    @Published var typeFilter: RulesTypeFilter = .all
    @Published var policyFilter: RulePolicyOption = .all
    @Published var groupByPolicy: Bool = false
    @Published private(set) var output: PresentRulesOutput = .empty

    init() {}

    func updateVisibleRules(items: [RuleItem], providers: [String: ProviderDetail]) {
        let policyOptions = self.makePolicyOptions(from: items)
        let keyword = self.filterText.trimmed
        let policyFilter = self.policyFilter
        let typeFilter = self.typeFilter

        let base: [RuleItem] = if keyword.isEmpty, policyFilter.isAll {
            items
        } else {
            items.filter { rule in
                guard policyFilter.isAll || rule.proxy.trimmedOrEmpty == policyFilter.name else { return false }
                guard keyword.isEmpty || self.searchText(for: rule).localizedStandardContains(keyword) else {
                    return false
                }
                return true
            }
        }

        let typeCounts = self.makeTypeCounts(from: base)
        let filtered = typeFilter == .all ? base : base.filter { typeFilter.matches($0.type) }

        let next = PresentRulesOutput(
            rules: filtered,
            groups: self.groupByPolicy ? self.makeGroups(from: filtered) : [],
            providerLookup: self.makeProviderLookup(from: providers),
            policyOptions: policyOptions,
            typeCounts: typeCounts)

        if !self.policyFilter.isAll, !next.policyOptions.contains(self.policyFilter) {
            self.policyFilter = .all
        }

        if next != self.output {
            self.output = next
        }
    }

    private func makeTypeCounts(from rules: [RuleItem]) -> [RulesTypeFilter: Int] {
        var counts: [RulesTypeFilter: Int] = [.all: rules.count]
        for rule in rules {
            for filter in RulesTypeFilter.allCases where filter != .all && filter.matches(rule.type) {
                counts[filter, default: 0] += 1
                break
            }
        }
        return counts
    }

    private func makeGroups(from rules: [RuleItem]) -> [RuleGroup] {
        var buckets: [String: [RuleItem]] = [:]
        for rule in rules {
            buckets[rule.proxy.trimmedOrEmpty, default: []].append(rule)
        }

        return buckets.map { RuleGroup(policy: $0.key, rules: $0.value) }.sorted { lhs, rhs in
            lhs.rules.count != rhs.rules.count
                ? lhs.rules.count > rhs.rules.count
                : lhs.policy.localizedStandardCompare(rhs.policy) == .orderedAscending
        }
    }

    private func searchText(for rule: RuleItem) -> String {
        "\(rule.payload.trimmedOrEmpty) \(rule.type.trimmedOrEmpty) \(rule.proxy.trimmedOrEmpty)"
    }

    private func makePolicyOptions(from items: [RuleItem]) -> [RulePolicyOption] {
        let names = Set(items.compactMap(\.proxy.trimmedNonEmpty))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [.all] + names.map { RulePolicyOption(name: $0) }
    }

    private func makeProviderLookup(from providers: [String: ProviderDetail]) -> [String: ProviderDetail] {
        var map: [String: ProviderDetail] = [:]
        map.reserveCapacity(providers.count * 2)

        for (key, detail) in providers {
            map[key.lowercased()] = detail
            if let name = detail.name.trimmedNonEmpty {
                map[name.lowercased()] = detail
            }
        }

        return map
    }
}
