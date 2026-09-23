import AppKit
import SwiftUI

/// 面向配置片段的纯文本编辑器：等宽、不折行（超长行横向滚动），并关掉智能引号 / 破折号 /
/// 自动替换——SwiftUI 的 TextEditor 会沿用系统设置把 `"` 换成弯引号，写坏 YAML 和规则。
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    /// 折叠后仍挂在视图树里时设为 false：不可编辑，并交出焦点，免得键入落进看不见的编辑器。
    var isActive = true

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: self.fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 4)

        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        textView.string = self.text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = self.$text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != self.text {
            textView.string = self.text
        }
        textView.isEditable = self.isActive
        textView.isSelectable = self.isActive
        if !self.isActive, let window = textView.window, window.firstResponder === textView {
            window.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.text.wrappedValue = textView.string
        }
    }
}
