import Cocoa
import Foundation

/// Quick Translate - 選択テキストの取得と翻訳
@MainActor
final class QuickTranslateService {

    private let translationService: TranslationService

    init(translationService: TranslationService) {
        self.translationService = translationService
    }

    /// アクティブアプリの選択テキストを取得（2段構え）
    /// 1. アクセシビリティ API（非破壊）
    /// 2. Cmd+C シミュレーション（クリップボード退避・復元）
    func getSelectedText() -> String? {
        // 優先: アクセシビリティ API
        if let text = getSelectedTextViaAccessibility() {
            return text
        }

        // フォールバック: Cmd+C（クリップボード非破壊）
        return getSelectedTextViaCopy()
    }

    /// 翻訳実行（言語自動検出で方向を決定）
    func translate(_ text: String) async throws -> String {
        try await translationService.translate(text, direction: .auto)
    }

    // MARK: - Private: アクセシビリティ API

    /// AXUIElement でフォーカス中のアプリの選択テキストを取得
    private func getSelectedTextViaAccessibility() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // フォーカス中のUI要素を取得
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success, let focused = focusedElement else { return nil }

        // 選択テキストを取得
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else { return nil }

        return text
    }

    // MARK: - Private: Cmd+C フォールバック

    /// Cmd+C でクリップボードにコピーしてテキストを取得（元の内容を復元）
    private func getSelectedTextViaCopy() -> String? {
        let pasteboard = NSPasteboard.general

        // 退避: 現在のクリップボード内容と changeCount
        let savedChangeCount = pasteboard.changeCount
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let types = item.types as? [NSPasteboard.PasteboardType] else { return nil }
            for type in types {
                if let data = item.data(forType: type) {
                    return (type, data)
                }
            }
            return nil
        } ?? []

        // Cmd+C シミュレーション
        simulateCopy()

        // クリップボードが更新されるのを待つ
        Thread.sleep(forTimeInterval: 0.15)

        // 新しいクリップボード内容を取得
        let newChangeCount = pasteboard.changeCount
        let selectedText = pasteboard.string(forType: .string)

        // changeCount が変わっていなければテキスト未選択
        guard newChangeCount != savedChangeCount else { return nil }

        // クリップボードを復元
        // ただし、別のアプリが更にクリップボードを更新した場合（changeCountがさらに変わった）は復元しない
        if pasteboard.changeCount == newChangeCount {
            pasteboard.clearContents()
            for (type, data) in savedItems {
                pasteboard.setData(data, forType: type)
            }
        }

        guard let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return text
    }

    /// Cmd+C キーイベントをシミュレート
    private func simulateCopy() {
        let keyCode: CGKeyCode = 8 // 'c'
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
