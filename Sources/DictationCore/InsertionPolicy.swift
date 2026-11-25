public enum FocusComparison { case same, different, unavailable }

/// Accessibility may not expose a focused web editor, or may recreate its AX
/// object on render. Accept that only in the same window with no intervening
/// user interaction or application/Space switch.
public enum InsertionPolicy {
    public static func allowsPaste(
        sameApplication: Bool, contextUnchanged: Bool,
        window: FocusComparison, element: FocusComparison,
        sameFieldDescription: Bool = false
    ) -> Bool {
        guard sameApplication, contextUnchanged, window != .different else { return false }
        switch element {
        case .same: return true
        case .unavailable: return window == .same
        case .different: return window == .same && sameFieldDescription
        }
    }
}
