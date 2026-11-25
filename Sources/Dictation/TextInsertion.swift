import AppKit
import ApplicationServices
import DictationCore

// AX handles and field metadata are fully constructed on the capture task,
// then read only after awaiting its result; no mutable state is shared.
struct InsertionTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement?
    let window: AXUIElement?
    private let windowID: CGWindowID?
    private let fieldDescription: FieldDescription?

    static func capture(pid: pid_t) -> InsertionTarget? {
        guard !Task.isCancelled else { return nil }
        let element = focusedElement(pid: pid)
        guard !Task.isCancelled else { return nil }
        let window = focusedElement(pid: pid, attribute: kAXFocusedWindowAttribute)
        guard !Task.isCancelled else { return nil }
        return InsertionTarget(
            pid: pid, element: element,
            window: window,
            windowID: frontWindowID(pid: pid),
            fieldDescription: element.flatMap(FieldDescription.init)
        )
    }

    private static func focusedElement(pid: pid_t, attribute: String = kAXFocusedUIElementAttribute) -> AXUIElement? {
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func matchesFocusedElementAndWindow() -> Bool {
        let current = Self.focusedElement(pid: pid)
        let currentWindow = Self.focusedElement(pid: pid, attribute: kAXFocusedWindowAttribute)
        var windowComparison = Self.compare(window, currentWindow)
        // Electron may expose neither AXFocusedUIElement nor AXFocusedWindow.
        // Window-server IDs remain available without reading window contents.
        if windowComparison == .unavailable, let windowID, let currentID = Self.frontWindowID(pid: pid) {
            windowComparison = windowID == currentID ? .same : .different
        }
        let currentDescription = current.flatMap(FieldDescription.init)
        return InsertionPolicy.allowsPaste(
            sameApplication: true, contextUnchanged: true,
            window: windowComparison, element: Self.compare(element, current),
            sameFieldDescription: fieldDescription != nil && fieldDescription == currentDescription
        )
    }

    private static func frontWindowID(pid: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }).flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    private static func compare(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> FocusComparison {
        guard let lhs, let rhs else { return .unavailable }
        return CFEqual(lhs, rhs) ? .same : .different
    }

    private struct FieldDescription: Equatable {
        let role: String
        let identifier: String?
        let frame: CGRect

        init?(_ element: AXUIElement) {
            AXUIElementSetMessagingTimeout(element, 0.2)
            func attribute(_ name: String) -> CFTypeRef? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
                return value
            }
            guard let role = attribute(kAXRoleAttribute) as? String,
                  [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role),
                  let position = attribute(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attribute(kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero
            var dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
            self.role = role
            identifier = attribute(kAXIdentifierAttribute) as? String
            frame = CGRect(origin: origin, size: dimensions)
        }
    }
}

@MainActor
enum TextInsertion {
    enum Outcome { case pasted, copied, readyToCopy }
    private static let clipboard = ClipboardWriter()
    private static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]

    static func copy(_ text: String) { clipboard.copy(text) }

    static func insert(_ text: String, target: InsertionTarget?, contextUnchanged: () -> Bool) async -> Outcome {
        // Releasing either shortcut key ends recording. Wait for all modifiers before Cmd+V.
        for _ in 0..<40 {
            if Task.isCancelled { return .readyToCopy }
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !Task.isCancelled else { return .readyToCopy }
        guard let target, contextUnchanged(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            copy(text)
            return .copied
        }
        // AX IPC must not freeze the animation or delay input-monitor events.
        let focused = await Task.detached(priority: .userInitiated) {
            target.matchesFocusedElementAndWindow()
        }.value
        guard !Task.isCancelled else { return .readyToCopy }
        func mayPaste() -> Bool {
            contextUnchanged() && AXIsProcessTrusted()
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
                && CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty
        }
        guard focused, mayPaste(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            copy(text)
            return .copied
        }
        clipboard.preparePaste(text)
        // Clipboard owners can lazily supply data. Let pending user interaction
        // invalidate the destination before the final check and key injection.
        await Task.yield()
        guard !Task.isCancelled else { clipboard.restoreIfUnchanged(); return .readyToCopy }
        guard clipboard.isPrepared else { return .readyToCopy }
        guard mayPaste() else { copy(text); return .copied }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        return .pasted
    }
}
