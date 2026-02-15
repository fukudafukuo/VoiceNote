import Cocoa
import Foundation

final class HotKeyService {

    typealias DoubleTapHandler = () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    private var rcmdPressTime: TimeInterval = 0
    private var rcmdLastTap: TimeInterval = 0
    private var rcmdWasPressed = false

    private let tapThreshold: TimeInterval = 0.25
    private let doubleTapInterval: TimeInterval = 0.5

    private let handler: DoubleTapHandler

    private let cmdFlag: UInt64 = 0x00100000
    private let rightCmdFlag: UInt64 = 0x00000010

    init(handler: @escaping DoubleTapHandler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<HotKeyService>.fromOpaque(refcon).takeUnretainedValue()
                service.handleFlagsChanged(event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "VoiceNote-HotKey"
        thread.start()
        tapThread = thread

        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        tapThread?.cancel()
        tapThread = nil
    }

    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags.rawValue
        let rcmdPressed = (flags & cmdFlag) != 0 && (flags & rightCmdFlag) != 0
        let now = ProcessInfo.processInfo.systemUptime

        if rcmdPressed && !rcmdWasPressed {
            rcmdPressTime = now
        } else if !rcmdPressed && rcmdWasPressed {
            if now - rcmdPressTime < tapThreshold {
                if now - rcmdLastTap < doubleTapInterval {
                    rcmdLastTap = 0
                    DispatchQueue.main.async { [weak self] in
                        self?.handler()
                    }
                } else {
                    rcmdLastTap = now
                }
            }
        }

        rcmdWasPressed = rcmdPressed
    }
}
