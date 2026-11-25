import AppKit

@MainActor
final class InsertionContext {
    private(set) var revision: UInt64 = 0
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    var isMonitoring: Bool { globalMonitor != nil && localMonitor != nil }

    func start() {
        guard !isMonitoring else { return }
        stop()
        // Modifier releases and mouse movement are deliberately excluded.
        // Clicking, typing, changing apps/Spaces invalidates the captured target,
        // even if the user subsequently returns to the original window.
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.revision &+= 1 }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.revision &+= 1
            return event
        }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.revision &+= 1 }
            })
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        revision &+= 1
    }
}
