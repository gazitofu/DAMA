import AppKit
import SwiftUI

struct EditDialog: Identifiable {
    enum Kind { case word(String), speaker(String) }
    let id = UUID()
    let kind: Kind
    let title: String
    let value: String
    let original: String?
}

struct EditDialogView: View {
    let dialog: EditDialog
    let apply: (String) -> Void
    @State private var value: String
    @Environment(\.dismiss) private var dismiss
    init(dialog: EditDialog, apply: @escaping (String) -> Void) {
        self.dialog = dialog
        self.apply = apply
        _value = State(initialValue: dialog.value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dialog.title).font(.title2)
            if let original = dialog.original {
                Text("모델 원문 보기").font(.caption).foregroundStyle(.secondary)
                Text(original).textSelection(.enabled)
                Text("수정한 글자는 원문과 별도로 저장됩니다. 시간 재정렬 안 됨.")
                    .font(.callout).foregroundStyle(.secondary)
            } else { Text("이 세션의 현재 Run에만 적용됩니다.").foregroundStyle(.secondary) }
            ExactTextEditor(text: $value, label: dialog.title).frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("적용") { apply(value); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(!canApply)
            }
        }.padding(24).frame(width: 440)
    }
    private var canApply: Bool {
        guard value != dialog.value else { return false }
        if case .speaker = dialog.kind { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }
}

/// Native text editing with all automatic rewriting disabled; local text Undo stays native.
struct ExactTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let editor = NSTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.font = .systemFont(ofSize: 17)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.setAccessibilityLabel(label)
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.text = $text
        if let editor = view.documentView as? NSTextView, editor.string != text { editor.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { text.wrappedValue = editor.string }
        }
    }
}
