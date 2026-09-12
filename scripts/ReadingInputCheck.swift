import AppKit

/// In-process AppKit input tests. No OS events, clipboard, user files, or input-source changes.
@main struct ReadingInputCheck {
    @MainActor static func main() {
        let view = ScriptTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        var commits = 0, cancels = 0
        var composition: [Bool] = []
        view.commit = { commits += 1 }; view.cancelDraft = { cancels += 1 }
        view.compositionChanged = { composition.append(view.hasMarkedText()) }
        view.synchronize(text: "", editable: true)
        view.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(view.hasMarkedText() && composition.last == true)
        view.synchronize(text: "stale model", editable: true)
        precondition(view.string == "한", "SwiftUI must not replace active Korean composition")
        precondition(!view.handleCommand(keyCode: 36, flags: .command) && commits == 0)
        precondition(!view.handleCommand(keyCode: 53, flags: []) && cancels == 0)
        view.unmarkText()
        precondition(!view.hasMarkedText() && composition.last == false, "Composition end must reach debounce without another keystroke")
        precondition(view.handleCommand(keyCode: 36, flags: .command) && commits == 1)
        precondition(!view.handleCommand(keyCode: 36, flags: []), "Body Return inserts a new line")
        view.singleLine = true
        precondition(view.handleCommand(keyCode: 36, flags: []) && commits == 2)
        view.setMarkedText("글", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: view.string.utf16.count))
        let notifications = composition.count
        view.synchronize(text: "저장된 원문", editable: false)
        precondition(view.string == "저장된 원문" && !view.hasMarkedText() && !view.isEditable)
        precondition(composition.count == notifications, "Cancellation cannot publish the discarded draft")
        precondition(view.handleCommand(keyCode: 53, flags: []) && cancels == 1)
        print("PASS: marked Korean text, stale model update, composition end, commit/cancel keys, readonly restoration")
    }
}
