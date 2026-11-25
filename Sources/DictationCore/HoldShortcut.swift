/// Tracks the physical Globe key separately: arrow keys also set the macOS Fn flag.
public struct HoldShortcut {
    public enum Transition: Equatable { case began, ended }
    public private(set) var isHeld = false
    private var globeDown = false
    private var blockedUntilRelease = false

    public init() {}

    public mutating func update(keyCode: Int, control: Bool, function: Bool, otherModifier: Bool) -> Transition? {
        if keyCode == 63 { globeDown = function }
        // Once Globe is held, only its own flagsChanged event can release it.
        // Other events may omit Fn after our tap consumes the Globe press.
        if !control || !globeDown { blockedUntilRelease = false }
        if isHeld && otherModifier { blockedUntilRelease = true }
        let next = control && globeDown && !otherModifier && !blockedUntilRelease
        guard next != isHeld else { return nil }
        isHeld = next
        return next ? .began : .ended
    }

    public mutating func cancel() {
        isHeld = false
        blockedUntilRelease = true
    }

    public mutating func reset() {
        self = HoldShortcut()
    }
}
