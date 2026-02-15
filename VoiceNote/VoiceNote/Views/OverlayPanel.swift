import Cocoa
import SwiftUI

/// フローティングオーバーレイパネル（NSPanel）
/// 常に最前面に表示し、フォーカスを奪わない
final class OverlayPanel: NSPanel {

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 320, height: 240)

        self.contentView = contentView

        // 画面右下にデフォルト配置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - self.frame.width - 20
            let y = screenFrame.minY + 20
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// nonactivatingPanel でも、クリックした時にキー入力を受け付ける（プランA対応）
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
