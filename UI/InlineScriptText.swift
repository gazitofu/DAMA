import AppKit
import SwiftUI

/// The same native text view draws and edits the paragraph; no second editor or sizing origin.
struct InlineScriptText: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool
    var title = false
    var focus = false
    var label: String
    var changed: (Bool) -> Void = { _ in }
    var commit: () -> Void = {}
    var cancel: () -> Void = {}
    var activated: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ScriptTextView {
        let view = ScriptTextView()
        view.isRichText = false; view.allowsUndo = true; view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false; view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = title ? 0 : 7
        view.defaultParagraphStyle = paragraph
        view.font = .systemFont(ofSize: title ? 27 : 17, weight: title ? .medium : .regular)
        view.textColor = .labelColor
        view.string = text; view.delegate = context.coordinator
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: ScriptTextView, context: Context) {
        context.coordinator.parent = self
        view.setAccessibilityLabel(label); view.singleLine = title
        view.commit = commit; view.cancelDraft = cancel
        view.activated = activated
        if view.string != text && !view.hasMarkedText() { view.string = text }
        view.isEditable = editable; view.isSelectable = true
        if focus && !view.focusRequested {
            view.focusRequested = true
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isEditable else { return }
                view.window?.makeFirstResponder(view)
            }
        } else if !focus { view.focusRequested = false }
        view.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ScriptTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(title ? 34 : 27, ceil(layout.usedRect(for: container).height)))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineScriptText
        init(_ parent: InlineScriptText) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; parent.changed(view.hasMarkedText())
            view.invalidateIntrinsicContentSize()
        }
        func textDidEndEditing(_ notification: Notification) {
            guard parent.title, let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            parent.commit()
        }
    }
}

final class ScriptTextView: NSTextView {
    var singleLine = false
    var focusRequested = false
    var commit: () -> Void = {}
    var cancelDraft: () -> Void = {}
    var activated: () -> Void = {}
    override func mouseDown(with event: NSEvent) { activated(); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() {
            if event.keyCode == 53 { cancelDraft(); return }
            if (event.keyCode == 36 || event.keyCode == 76) && (singleLine || event.modifierFlags.contains(.command)) { commit(); return }
        }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if singleLine, let string = insertString as? String {
            super.insertText(string.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "), replacementRange: replacementRange)
        } else { super.insertText(insertString, replacementRange: replacementRange) }
    }
}
