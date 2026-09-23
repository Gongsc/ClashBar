import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct OverrideTabView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel

    var body: some View {
        RuleOverrideCard(appViewModel: self.appViewModel, store: self.appViewModel.ruleOverrideStore)
            .onAppear { self.appViewModel.refreshRuleOverrideCounts() }
    }
}

private struct RuleOverrideCard: TranslatingView {
    let appViewModel: AppViewModel
    @ObservedObject var store: RuleOverrideStore

    private var isRemote: Bool {
        self.appViewModel.isRemoteTarget
    }

    private var isCoreRunning: Bool {
        !self.isRemote && self.appViewModel.isRuntimeRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.space6) {
            VStack(spacing: 0) {
                self.cardHeader(self.tr("ui.section.rule_override"), symbol: "arrow.triangle.branch")
                self.enabledToggleRow

                if self.isRemote {
                    self.hintRow(self.tr("ui.rule_override.remote_hint"), symbol: "info.circle")
                } else if self.store.isEnabled {
                    self.fileRow(.prepend, symbol: "arrow.up.to.line", count: self.store.counts.prepend)
                    self.fileRow(.append, symbol: "arrow.down.to.line", count: self.store.counts.append)
                    self.fileRow(
                        .ruleProviders,
                        symbol: "square.stack.3d.up",
                        count: self.store.counts.ruleProviders)
                    self.statusRow
                    self.actionButtons
                } else {
                    self.hintRow(self.tr("ui.rule_override.disabled_hint"), symbol: "info.circle")
                }
            }
        }
    }

    // MARK: - Rows

    private var enabledToggleRow: some View {
        HStack(spacing: T.space8) {
            self.rowLabel(symbol: "power", title: self.tr("ui.rule_override.enabled"))
                .layoutPriority(1)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { self.store.isEnabled },
                set: { enabled in Task { await self.appViewModel.setRuleOverrideEnabled(enabled) } }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(self.isRemote || self.store.isApplying)
        }
        .menuRowPadding(vertical: T.space4)
    }

    private func fileRow(_ file: RuleOverrideFile, symbol: String, count: Int) -> some View {
        HStack(spacing: T.space8) {
            self.rowLabel(symbol: symbol, title: self.tr(self.titleKey(for: file)))
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(self.countText(for: file, count: count))
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(count > 0 ? nativeSecondaryLabel : nativeTertiaryLabel)
                .monospacedDigit()
            Button {
                self.appViewModel.openRuleOverrideFile(file)
            } label: {
                Label(self.tr("ui.rule_override.edit"), systemImage: "square.and.pencil")
            }
            .appBorderedButtonStyle()
            .controlSize(.small)
            .help(file.fileName)
        }
        .menuRowPadding(vertical: T.space4)
    }

    @ViewBuilder
    private var statusRow: some View {
        if self.store.isApplying {
            self.statusLine(symbol: nil, color: nativeSecondaryLabel, text: self.tr("ui.rule_override.status.applying"))
        } else {
            switch self.store.status {
            case let .applied(configName, at):
                HStack(spacing: T.space6) {
                    self.statusLine(
                        symbol: "checkmark.circle.fill",
                        color: nativePositive,
                        text: self.tr("ui.rule_override.status.applied", configName))
                    Text(at, style: .time)
                        .font(.app(size: T.FontSize.caption, weight: .medium))
                        .foregroundStyle(nativeTertiaryLabel)
                }
                .menuRowPadding(vertical: T.space4)
            case let .failed(message, _):
                self.failureBox(message)
            case .empty:
                self.statusLine(
                    symbol: "info.circle",
                    color: nativeTertiaryLabel,
                    text: self.tr("ui.rule_override.status.empty"))
                    .menuRowPadding(vertical: T.space4)
            case nil:
                self.statusLine(
                    symbol: "clock",
                    color: nativeTertiaryLabel,
                    text: self.tr("ui.rule_override.status.pending"))
                    .menuRowPadding(vertical: T.space4)
            }
        }
    }

    private func failureBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: T.space4) {
            self.statusLine(
                symbol: "exclamationmark.triangle.fill",
                color: nativeCritical,
                text: self.tr("ui.rule_override.status.failed"))
            Text(message)
                .font(.app(size: T.FontSize.caption, weight: .regular))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(5)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                self.appViewModel.setActiveMenuTab(.logs)
            } label: {
                Label(self.tr("ui.rule_override.view_logs"), systemImage: "doc.text")
            }
            .appBorderedButtonStyle()
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(T.space6)
        .background {
            RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                .fill(nativeCritical.opacity(T.Opacity.selection))
                .overlay {
                    RoundedRectangle(cornerRadius: T.cornerRadius, style: .continuous)
                        .stroke(nativeCritical.opacity(0.26), lineWidth: T.stroke)
                }
        }
        .menuRowPadding(vertical: T.space4)
    }

    private var actionButtons: some View {
        HStack(spacing: T.space6) {
            Button {
                Task { await self.appViewModel.applyRuleOverridesIfRunning(force: true) }
            } label: {
                Label(self.tr("ui.rule_override.apply_now"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .appBorderedButtonStyle()
            .controlSize(.small)
            .disabled(!self.isCoreRunning || self.store.isApplying)
            .opacity(self.isCoreRunning ? 1 : 0.62)

            Button {
                self.appViewModel.showRuleOverrideDirectoryInFinder()
            } label: {
                Label(self.tr("ui.rule_override.open_directory"), systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .appBorderedButtonStyle()
            .controlSize(.small)
        }
        .menuRowPadding(vertical: T.space4)
    }

    // MARK: - Building blocks

    private func cardHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .bold))
                .foregroundStyle(nativeTertiaryLabel)
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .menuRowPadding(vertical: T.space2)
    }

    private func rowLabel(symbol: String, title: String) -> some View {
        HStack(spacing: T.space6) {
            Image(systemName: symbol)
                .font(.app(size: T.FontSize.caption, weight: .semibold))
                .foregroundStyle(nativeTertiaryLabel)
                .frame(width: 14, alignment: .center)
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(nativePrimaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func hintRow(_ text: String, symbol: String) -> some View {
        self.statusLine(symbol: symbol, color: nativeTertiaryLabel, text: text)
            .menuRowPadding(vertical: T.space4)
    }

    private func statusLine(symbol: String?, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: T.space6) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .font(.app(size: T.FontSize.caption, weight: .semibold))
            .frame(width: 14, alignment: .center)
            Text(text)
                .font(.app(size: T.FontSize.caption, weight: .medium))
                .foregroundStyle(nativeSecondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func titleKey(for file: RuleOverrideFile) -> String {
        switch file {
        case .prepend: "ui.rule_override.prepend"
        case .append: "ui.rule_override.append"
        case .ruleProviders: "ui.rule_override.rule_providers"
        }
    }

    private func countText(for file: RuleOverrideFile, count: Int) -> String {
        switch file {
        case .prepend, .append: self.tr("ui.rule_override.count.rules", count)
        case .ruleProviders: self.tr("ui.rule_override.count.providers", count)
        }
    }
}
