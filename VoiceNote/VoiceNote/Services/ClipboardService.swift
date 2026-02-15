import Cocoa
import Foundation

final class ClipboardService {

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func pasteToActiveApp(delay: TimeInterval = 0.3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.simulatePaste()
        }
    }

    func copyAndPaste(_ text: String, delay: TimeInterval = 0.3) {
        copyToClipboard(text)
        pasteToActiveApp(delay: delay)
    }

    private func simulatePaste() {
        let keyCode: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            return
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
