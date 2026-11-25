import AppKit
import DictationCore

final class GlobalShortcut {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var shortcut = HoldShortcut()
    private var generation = 0
    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // Do not poll combinedSessionState for release: this tap consumes Globe
        // events, so the downstream session state need not reflect the held key.
        // Actual flagsChanged events drive release; AppModel handles sleep,
        // session deactivation, cancellation and the recording duration limit.
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let wasHeld = shortcut.isHeld
            shortcut.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if wasHeld { enqueue(onCancel) }
            return Unmanaged.passUnretained(event)
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown {
            if key == 53, shortcut.isHeld {
                shortcut.cancel()
                enqueue(onCancel)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let wasHeld = shortcut.isHeld
        let transition = shortcut.update(
            keyCode: key, control: flags.contains(.maskControl), function: flags.contains(.maskSecondaryFn),
            otherModifier: !flags.intersection([.maskCommand, .maskAlternate, .maskShift]).isEmpty
        )
        switch transition {
        case .began: enqueue(onBegin)
        case .ended: enqueue(onEnd)
        case nil: break
        }
        // Consume the Globe chord without interfering with ordinary Globe presses.
        if key == 63 && (wasHeld || shortcut.isHeld) { return nil }
        return Unmanaged.passUnretained(event)
    }

    private func enqueue(_ callback: (() -> Void)?) {
        // Microphone startup and Accessibility queries must not block the tap.
        // Main-queue FIFO preserves press/release order, including quick taps.
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tap != nil, self.generation == generation else { return }
            callback?()
        }
    }

    func cancelCurrentHold() {
        generation += 1
        shortcut.cancel()
    }

    func stop() {
        generation += 1
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        shortcut.reset()
    }

    deinit { stop() }
}
